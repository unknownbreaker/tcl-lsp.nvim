// Package index builds a workspace-wide, fully-qualified symbol table of TCL
// definitions across files, with incremental per-file updates.
package index

import "github.com/unknownbreaker/tcl-lsp/internal/tcl"

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

// Lookup returns all definition sites for a fully-qualified name (nil if none).
func (ix *Index) Lookup(name string) []Location {
	return ix.defsByName[name]
}
