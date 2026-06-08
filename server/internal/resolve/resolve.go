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
		return r.commandCandidates(name, ns)
	}
	return variableCandidates(name, ns, ref.Frame)
}

// commandCandidates returns the FQ command names to try, in TCL precedence
// order: current namespace, imported names, namespace-path entries, then global.
// A qualified name resolves directly.
func (r *Resolver) commandCandidates(name, ns string) []string {
	if isQualified(name) {
		return []string{qualify(name, ns)}
	}
	cands := []string{qualify(name, ns)} // current namespace

	path, imports := r.ix.Namespace(ns)
	// Imported commands behave like commands in the current namespace. A glob
	// import (last == "*") adds srcNs::name even when name is not actually
	// exported by srcNs; Lookup filters non-existent names, so this only
	// over-matches when srcNs::name happens to exist (export patterns are not
	// yet modeled — research OQ6).
	for _, imp := range imports {
		if srcNs, last, ok := splitLastSegment(imp); ok && (last == name || last == "*") {
			if srcNs == "::" {
				cands = append(cands, "::"+name)
			} else {
				cands = append(cands, srcNs+"::"+name)
			}
		}
	}
	// namespace path entries (already fully qualified).
	for _, p := range path {
		cands = append(cands, p+"::"+name)
	}
	// global fallback.
	if ns != "::" {
		cands = append(cands, "::"+name)
	}
	return dedup(cands)
}

// splitLastSegment splits a qualified name into (namespace, lastSegment), e.g.
// "::p::pub" -> ("::p", "pub") and "::pub" -> ("::", "pub"). Returns ok=false
// when there is no "::" separator.
func splitLastSegment(qname string) (nsPart, last string, ok bool) {
	i := strings.LastIndex(qname, "::")
	if i < 0 {
		return "", "", false
	}
	nsPart = qname[:i]
	if nsPart == "" {
		nsPart = "::"
	}
	return nsPart, qname[i+2:], true
}

func dedup(in []string) []string {
	seen := make(map[string]bool, len(in))
	out := in[:0]
	for _, s := range in {
		if !seen[s] {
			seen[s] = true
			out = append(out, s)
		}
	}
	return out
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

// References returns all workspace references to the symbol at byte offset in
// src. The current file is parsed from the live src; other files use the
// reference sites precomputed at index time, so a request does not re-parse the
// whole workspace. Only command and namespace/qualified-variable references are
// matched; bare proc-locals and bareword variable-name arguments are not.
func (r *Resolver) References(file, src string, offset int) []index.Location {
	target := r.targetFQ(file, src, offset)
	if target == "" {
		return nil
	}
	// targetKind carries the target's DEFINITION kind for the protocol layer's
	// use; it is the zero value (DefProc) when the target has no definition in
	// the index (an undefined symbol). A reference site itself has no def-kind.
	var targetKind tcl.DefKind
	if defs := r.ix.Lookup(target); len(defs) > 0 {
		targetKind = defs[0].Kind
	}

	var out []index.Location
	scan := func(f string, refs []tcl.ContextRef) {
		for i := range refs {
			if r.refFQ(&refs[i]) == target {
				out = append(out, index.Location{
					File: f, Name: target, Kind: targetKind,
					NameStart: refs[i].Ref.Start, NameEnd: refs[i].Ref.End,
				})
			}
		}
	}

	scan(file, tcl.FileRefs(src)) // current file: parse the live source
	for _, f := range r.ix.Files() {
		if f == file {
			continue
		}
		scan(f, r.ix.FileRefs(f)) // other files: precomputed at index time, no re-parse
	}
	return out
}

// targetFQ returns the fully-qualified name of the symbol at offset: a
// definition name-range it falls within, else the reference there resolved to
// its FQ name. Returns "" if there is no resolvable symbol.
// file is currently unused but reserved for frame-local resolution (a later phase).
func (r *Resolver) targetFQ(file, src string, offset int) string {
	for _, d := range tcl.FileDefs(src) {
		if (d.Kind == tcl.DefProc || d.Kind == tcl.DefNamespaceVar) &&
			offset >= d.NameStart && offset < d.NameEnd {
			return d.Name
		}
	}
	if ref := refAt(src, offset); ref != nil {
		return r.refFQ(ref)
	}
	return ""
}

// refFQ resolves a reference to the fully-qualified name it binds to, using the
// same first-match precedence as goto-definition. If no candidate is defined in
// the index, the primary (first) candidate is used so undefined references still
// group together. Returns "" when there are no candidates (e.g. a bare
// proc-local variable).
func (r *Resolver) refFQ(ref *tcl.ContextRef) string {
	cands := r.candidates(ref)
	for _, name := range cands {
		if len(r.ix.Lookup(name)) > 0 {
			return name
		}
	}
	if len(cands) > 0 {
		return cands[0]
	}
	return ""
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
