// Package resolve maps a cursor position to definition sites using the workspace
// index and TCL's name-resolution rules.
package resolve

import (
	"strings"

	"github.com/unknownbreaker/tcl-lsp/internal/index"
	"github.com/unknownbreaker/tcl-lsp/internal/tcl"
)

// Resolver resolves symbols to definitions against a workspace index.
type Resolver struct {
	ix *index.Index
}

// New returns a Resolver over the given index.
func New(ix *index.Index) *Resolver {
	return &Resolver{ix: ix}
}

// Definition returns the definition site(s) for the symbol at byte offset in the
// file with the given source. Returns nil if there is no symbol at the offset or
// it resolves to nothing.
func (r *Resolver) Definition(file, src string, offset int) []index.Location {
	ref := refAt(src, offset)
	if ref == nil {
		return nil
	}
	var out []index.Location
	for _, name := range r.candidates(ref) {
		out = append(out, r.ix.Lookup(name)...)
	}
	return out
}

// refAt returns the innermost reference whose byte range contains offset.
func refAt(src string, offset int) *tcl.ContextRef {
	refs := tcl.FileRefs(src)
	var best *tcl.ContextRef
	for i := range refs {
		rg := refs[i].Ref
		if offset >= rg.Start && offset < rg.End {
			if best == nil || (rg.End-rg.Start) < (best.Ref.End-best.Ref.Start) {
				best = &refs[i]
			}
		}
	}
	return best
}

// candidates returns the fully-qualified names to look up for a reference.
func (r *Resolver) candidates(ref *tcl.ContextRef) []string {
	name := ref.Ref.Name
	ns := ref.Namespace
	if ref.Ref.Kind == tcl.RefCommand {
		return commandCandidates(name, ns)
	}
	return variableCandidates(name, ns, ref.Frame)
}

// commandCandidates: a qualified name resolves directly; a bare name is searched
// in the current namespace then the global namespace.
func commandCandidates(name, ns string) []string {
	if isQualified(name) {
		return []string{qualify(name, ns)}
	}
	if ns == "::" {
		return []string{"::" + name}
	}
	return []string{ns + "::" + name, "::" + name}
}

// variableCandidates is completed in the next task; commands work now.
func variableCandidates(name, ns string, frame tcl.FrameKind) []string {
	return nil
}

func isQualified(name string) bool { return strings.Contains(name, "::") }

// qualify resolves name against ns: a leading "::" is absolute; otherwise the
// name is qualified into ns.
func qualify(name, ns string) string {
	if strings.HasPrefix(name, "::") {
		return name
	}
	if ns == "::" {
		return "::" + name
	}
	return ns + "::" + name
}
