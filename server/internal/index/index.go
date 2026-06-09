// Package index builds a workspace-wide, fully-qualified symbol table of TCL
// definitions across files, with incremental per-file updates.
package index

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/unknownbreaker/tcl-lsp/internal/source"
	"github.com/unknownbreaker/tcl-lsp/internal/tcl"
)

// Location is a single definition site.
type Location struct {
	File      string
	Name      string // fully-qualified name
	Kind      tcl.DefKind
	NameStart int
	NameEnd   int
}

// Index holds workspace-visible definitions (procs and namespace variables)
// keyed by fully-qualified name, plus each file's source for later analysis.
// Index is not safe for concurrent use; the LSP server (protocol layer, a later
// plan) must serialize access (e.g. an RWMutex: shared for Lookup/Files/Source,
// exclusive for IndexFile/RemoveFile).
type Index struct {
	defsByName map[string][]Location                    // FQ name -> all definition sites
	fileDefs   map[string][]string                      // file -> FQ names it defines (for removal)
	src        map[string]string                        // file -> source text
	fileNS     map[string]map[string]*tcl.NamespaceInfo // file -> (ns name -> decls)
	fileRefs   map[string][]tcl.ContextRef              // file -> precomputed reference sites
	nsCache    map[string]nsMerged                      // memoized merged path/imports per ns
}

// nsMerged is the merged namespace-path and import set for one namespace, cached
// so Namespace need not rescan every file on each call (it is queried once per
// unqualified command reference during a references scan — O(refs) calls).
type nsMerged struct {
	path    []string
	imports []string
}

// New returns an empty Index.
func New() *Index {
	return &Index{
		defsByName: map[string][]Location{},
		fileDefs:   map[string][]string{},
		src:        map[string]string{},
		fileNS:     map[string]map[string]*tcl.NamespaceInfo{},
		fileRefs:   map[string][]tcl.ContextRef{},
		nsCache:    map[string]nsMerged{},
	}
}

// IndexFile records the workspace-visible definitions in content under path. Locals
// and global links are skipped (resolved frame-locally, not via the workspace
// table).
func (ix *Index) IndexFile(path, content string) {
	ix.RemoveFile(path)
	ix.src[path] = content
	ix.fileNS[path] = source.Namespaces(path, content)
	// Precompute reference sites once here so a references request iterates
	// stored data instead of re-parsing every workspace file (the dominant cost
	// on large repos). Resolution stays request-time (it depends on cross-file
	// namespace state); only the parse is hoisted.
	if refs := source.Refs(path, content); len(refs) > 0 {
		ix.fileRefs[path] = refs
	}
	for _, d := range source.Defs(path, content) {
		if d.Kind != tcl.DefProc && d.Kind != tcl.DefNamespaceVar {
			continue
		}
		ix.defsByName[d.Name] = append(ix.defsByName[d.Name], Location{
			File: path, Name: d.Name, Kind: d.Kind, NameStart: d.NameStart, NameEnd: d.NameEnd,
		})
		ix.fileDefs[path] = append(ix.fileDefs[path], d.Name)
	}
}

// RemoveFile drops all definitions and stored source contributed by path.
func (ix *Index) RemoveFile(path string) {
	for _, name := range ix.fileDefs[path] {
		locs := ix.defsByName[name]
		// kept reuses locs' backing array; this is safe because Lookup returns
		// copies, so no external caller aliases this slice.
		kept := locs[:0]
		for _, l := range locs {
			if l.File != path {
				kept = append(kept, l)
			}
		}
		if len(kept) == 0 {
			delete(ix.defsByName, name)
		} else {
			ix.defsByName[name] = kept
		}
	}
	delete(ix.fileDefs, path)
	delete(ix.src, path)
	delete(ix.fileNS, path)
	delete(ix.fileRefs, path)
	// Namespace data spans files, so any file change can alter a merged result;
	// drop the whole memo and let reads rebuild lazily. IndexFile calls RemoveFile
	// first, so this covers re-index too. Reads never happen mid-mutation (the
	// server serializes index access), so lazy rebuild is safe.
	clear(ix.nsCache)
}

// FileRefs returns the precomputed reference sites for path (nil if the file is
// not indexed or has no references). The returned slice is read-only; callers
// must not mutate it.
func (ix *Index) FileRefs(path string) []tcl.ContextRef {
	return ix.fileRefs[path]
}

// Lookup returns all definition sites for a fully-qualified name (nil if none).
// The returned slice is a copy; callers may retain it across Index mutations.
func (ix *Index) Lookup(name string) []Location {
	locs := ix.defsByName[name]
	if len(locs) == 0 {
		return nil
	}
	out := make([]Location, len(locs))
	copy(out, locs)
	return out
}

// Files returns the indexed file paths, sorted for deterministic iteration.
func (ix *Index) Files() []string {
	out := make([]string, 0, len(ix.src))
	for p := range ix.src {
		out = append(out, p)
	}
	sort.Strings(out)
	return out
}

// Source returns the stored source for a file ("" if not indexed).
func (ix *Index) Source(path string) string {
	return ix.src[path]
}

// Namespace returns the merged command-search path and import source patterns
// declared for ns across the workspace, deduplicated and ordered by file then
// declaration order. Used for command resolution (namespace path / import).
// Variables are unaffected by these declarations.
// Note: this is a union approximation — in real TCL a later `namespace path`
// call replaces the earlier one, but we merge across files for static analysis.
// Namespace returns the merged namespace-path and import set declared for ns
// across all files, sorted by file for determinism. The result is memoized and
// invalidated on any index mutation; the returned slices are read-only and must
// not be mutated by callers.
func (ix *Index) Namespace(ns string) (path []string, imports []string) {
	if m, ok := ix.nsCache[ns]; ok {
		return m.path, m.imports
	}

	files := make([]string, 0, len(ix.fileNS))
	for f := range ix.fileNS {
		files = append(files, f)
	}
	sort.Strings(files)

	seenP, seenI := map[string]bool{}, map[string]bool{}
	for _, f := range files {
		info := ix.fileNS[f][ns]
		if info == nil {
			continue
		}
		for _, p := range info.Path {
			if !seenP[p] {
				seenP[p] = true
				path = append(path, p)
			}
		}
		for _, im := range info.Imports {
			if !seenI[im] {
				seenI[im] = true
				imports = append(imports, im)
			}
		}
	}
	ix.nsCache[ns] = nsMerged{path: path, imports: imports}
	return path, imports
}

// IndexDir walks root and indexes every *.tcl file found (recursively). A
// per-entry read error is recorded and the walk continues, so one unreadable
// file or directory cannot truncate the whole workspace index. The `.git`
// directory is skipped. The returned error aggregates any failures (nil if none).
func (ix *Index) IndexDir(root string) error {
	var errs []error
	walkErr := filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			// Unreadable entry: record and keep walking the rest of the tree.
			errs = append(errs, err)
			return nil
		}
		if d.IsDir() {
			if d.Name() == ".git" {
				return fs.SkipDir // never contains .tcl; skip the noise
			}
			return nil
		}
		if !strings.HasSuffix(p, ".tcl") {
			return nil
		}
		b, err := os.ReadFile(p)
		if err != nil {
			errs = append(errs, fmt.Errorf("indexing %s: %w", p, err))
			return nil
		}
		ix.IndexFile(p, string(b))
		return nil
	})
	if walkErr != nil {
		errs = append(errs, walkErr)
	}
	return errors.Join(errs...)
}
