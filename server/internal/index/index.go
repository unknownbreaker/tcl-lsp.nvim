// Package index builds a workspace-wide, fully-qualified symbol table of TCL
// definitions across files, with incremental per-file updates.
package index

import (
	"sort"

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
type Index struct {
	defsByName map[string][]Location // FQ name -> all definition sites
	fileDefs   map[string][]string   // file -> FQ names it defines (for removal)
	src        map[string]string     // file -> source text
}

// New returns an empty Index.
func New() *Index {
	return &Index{
		defsByName: map[string][]Location{},
		fileDefs:   map[string][]string{},
		src:        map[string]string{},
	}
}

// IndexFile records the workspace-visible definitions in src under path. Locals
// and global links are skipped (resolved frame-locally, not via the workspace
// table).
func (ix *Index) IndexFile(path, src string) {
	ix.RemoveFile(path)
	ix.src[path] = src
	for _, d := range tcl.FileDefs(src) {
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
}

// Lookup returns all definition sites for a fully-qualified name (nil if none).
func (ix *Index) Lookup(name string) []Location {
	return ix.defsByName[name]
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
