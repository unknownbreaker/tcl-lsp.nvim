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

// Definition returns the definition site(s) for the symbol at byte offset in
// src. file is the path of the calling document; it is currently unused but
// reserved for frame-local resolution (a later phase). Returns nil if there is
// no symbol at the offset or it resolves to nothing. Candidates are tried in
// TCL precedence order (current namespace, then global); the first candidate
// that resolves wins (a bare name is NOT unioned across namespaces).
func (r *Resolver) Definition(file, src string, offset int) []index.Location {
	ref := refAt(src, offset)
	if ref == nil {
		return nil
	}
	for _, name := range r.candidates(ref) {
		if locs := r.ix.Lookup(name); len(locs) > 0 {
			return locs
		}
	}
	return nil
}

// refAt returns the innermost reference whose byte range contains offset.
func refAt(src string, offset int) *tcl.ContextRef {
	refs := tcl.FileRefs(src)
	var best *tcl.ContextRef
	for i := range refs {
		rg := refs[i].Ref
		if offset >= rg.Start && offset < rg.End {
			// Innermost wins (smallest range). Ties on identical ranges — which the
			// current parser does not produce — keep the first ref encountered.
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
// in the current namespace, then the global namespace.
// TODO(namespace-path): insert each `namespace path` entry between current and
// global once the parser surfaces path info (design §4); deferred for now.
func commandCandidates(name, ns string) []string {
	if isQualified(name) {
		return []string{qualify(name, ns)}
	}
	if ns == "::" {
		return []string{"::" + name}
	}
	return []string{ns + "::" + name, "::" + name}
}

// variableCandidates: a qualified variable resolves directly; a bare variable at
// namespace-eval top level is the current namespace's own variable. A bare
// variable inside a proc body is local-only and not resolvable via the workspace
// index (frame-local resolution is a later plan) — returns nil.
func variableCandidates(name, ns string, frame tcl.FrameKind) []string {
	if isQualified(name) {
		return []string{qualify(name, ns)}
	}
	if frame == tcl.FrameNamespace {
		if ns == "::" {
			return []string{"::" + name}
		}
		return []string{ns + "::" + name}
	}
	return nil // bare proc-local — deferred
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
