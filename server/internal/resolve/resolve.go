// Package resolve maps a cursor position to definition sites using the workspace
// index and TCL's name-resolution rules.
package resolve

import (
	"strings"

	"github.com/unknownbreaker/tcl-lsp/internal/index"
	"github.com/unknownbreaker/tcl-lsp/internal/source"
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

// isLocalBinding reports whether a definition kind binds a proc-local name.
func isLocalBinding(k tcl.DefKind) bool {
	return k == tcl.DefLocal || k == tcl.DefGlobalLink
}

// localAt reports whether offset sits on a proc-local symbol, returning its
// bare name and scope. Definition name-ranges (local bindings) are checked
// first, then FrameProc variable references ($x uses).
func (r *Resolver) localAt(file, src string, offset int) (name string, scope int, ok bool) {
	for _, d := range source.Defs(file, src) {
		if isLocalBinding(d.Kind) && offset >= d.NameStart && offset < d.NameEnd {
			return d.Name, d.Scope, true
		}
	}
	for _, ref := range source.Refs(file, src) {
		if ref.Ref.Kind == tcl.RefVariable && ref.Frame == tcl.FrameProc &&
			offset >= ref.Ref.Start && offset < ref.Ref.End {
			return ref.Ref.Name, ref.Scope, true
		}
	}
	return "", 0, false
}

// localDefinition returns the nearest preceding binding of (name, scope) at or
// before offset, falling back to the first binding when none precedes.
func (r *Resolver) localDefinition(file, src string, offset int, name string, scope int) []index.Location {
	bestStart, bestEnd, haveBest := 0, 0, false
	firstStart, firstEnd, haveFirst := 0, 0, false
	for _, d := range source.Defs(file, src) {
		if !isLocalBinding(d.Kind) || d.Name != name || d.Scope != scope {
			continue
		}
		if !haveFirst || d.NameStart < firstStart {
			firstStart, firstEnd, haveFirst = d.NameStart, d.NameEnd, true
		}
		if d.NameStart <= offset && (!haveBest || d.NameStart > bestStart) {
			bestStart, bestEnd, haveBest = d.NameStart, d.NameEnd, true
		}
	}
	s, e := bestStart, bestEnd
	if !haveBest {
		if !haveFirst {
			return nil
		}
		s, e = firstStart, firstEnd
	}
	return []index.Location{{File: file, Name: name, Kind: tcl.DefLocal, NameStart: s, NameEnd: e}}
}

// Definition returns the definition site(s) for the symbol at byte offset in
// src. file is the path of the calling document; page-local (::request::*)
// symbols are scoped to file only. Returns nil if there is no symbol at the
// offset or it resolves to nothing. Candidates are tried in TCL precedence
// order (current namespace, then global); the first candidate that resolves
// wins (a bare name is NOT unioned across namespaces).
func (r *Resolver) Definition(file, src string, offset int) []index.Location {
	if name, scope, ok := r.localAt(file, src, offset); ok {
		return r.localDefinition(file, src, offset, name, scope)
	}
	ref := refAt(file, src, offset)
	if ref == nil {
		return nil
	}
	for _, name := range r.candidates(ref) {
		if locs := r.lookupScoped(name, file); len(locs) > 0 {
			return locs
		}
	}
	return nil
}

// refAt returns the innermost reference whose byte range contains offset, parsing
// src through the source seam so .rvt content is extracted to its stitched script
// and reported in source coordinates.
func refAt(file, src string, offset int) *tcl.ContextRef {
	refs := source.Refs(file, src)
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

// localReferences returns every occurrence of the proc-local (name, scope) in the
// current file: binding sites and $-use sites. Locals never cross files, so only
// the current document is scanned. Results are deduped by byte range.
func (r *Resolver) localReferences(file, src, name string, scope int) []index.Location {
	seen := map[[2]int]bool{}
	var out []index.Location
	add := func(start, end int) {
		key := [2]int{start, end}
		if seen[key] {
			return
		}
		seen[key] = true
		out = append(out, index.Location{File: file, Name: name, Kind: tcl.DefLocal, NameStart: start, NameEnd: end})
	}
	for _, d := range source.Defs(file, src) {
		if isLocalBinding(d.Kind) && d.Name == name && d.Scope == scope {
			add(d.NameStart, d.NameEnd)
		}
	}
	for _, ref := range source.Refs(file, src) {
		if ref.Ref.Kind == tcl.RefVariable && ref.Frame == tcl.FrameProc &&
			ref.Ref.Name == name && ref.Scope == scope {
			// Ref.Start points at '$'; the name itself starts one byte later.
			add(ref.Ref.Start+1, ref.Ref.End)
		}
	}
	return out
}

// References returns all workspace references to the symbol at byte offset in
// src. The current file is parsed from the live src; other files use the
// reference sites precomputed at index time, so a request does not re-parse the
// whole workspace. Only command and namespace/qualified-variable references are
// matched; bare proc-locals and bareword variable-name arguments are not.
func (r *Resolver) References(file, src string, offset int) []index.Location {
	if name, scope, ok := r.localAt(file, src, offset); ok {
		return r.localReferences(file, src, name, scope)
	}
	target := r.targetFQ(file, src, offset)
	if target == "" {
		return nil
	}
	// targetKind carries the target's DEFINITION kind for the protocol layer's
	// use; it is the zero value (DefProc) when the target has no definition in
	// the index (an undefined symbol). A reference site itself has no def-kind.
	var targetKind tcl.DefKind
	if defs := r.lookupScoped(target, file); len(defs) > 0 {
		targetKind = defs[0].Kind
	}

	// A page-local (::request) symbol has references only within its own page, so
	// scanning other files would risk matching an identically-named page-local
	// helper elsewhere (their primary candidate name collides).
	pageLocal := source.IsRVT(file) && strings.HasPrefix(target, "::request::")

	var out []index.Location
	scan := func(f string, refs []tcl.ContextRef) {
		for i := range refs {
			if r.refFQ(&refs[i], f) == target {
				out = append(out, index.Location{
					File: f, Name: target, Kind: targetKind,
					NameStart: refs[i].Ref.Start, NameEnd: refs[i].Ref.End,
				})
			}
		}
	}

	scan(file, source.Refs(file, src)) // current file: parse the live source via the seam
	if !pageLocal {
		for _, f := range r.ix.Files() {
			if f == file {
				continue
			}
			scan(f, r.ix.FileRefs(f))
		}
	}
	return out
}

// Declarations returns the definition site(s) of the symbol at offset -- its
// declaration(s), for find-references with includeDeclaration. Unlike Definition
// it resolves from a usage OR from the definition itself (goto-definition is a
// no-op when already at the definition), so `gr` with the cursor on the proc
// name still yields the declaration. Returns nil for an undefined symbol.
func (r *Resolver) Declarations(file, src string, offset int) []index.Location {
	if name, scope, ok := r.localAt(file, src, offset); ok {
		var out []index.Location
		for _, d := range source.Defs(file, src) {
			if isLocalBinding(d.Kind) && d.Name == name && d.Scope == scope {
				out = append(out, index.Location{File: file, Name: name, Kind: tcl.DefLocal, NameStart: d.NameStart, NameEnd: d.NameEnd})
			}
		}
		return out
	}
	target := r.targetFQ(file, src, offset)
	if target == "" {
		return nil
	}
	return r.lookupScoped(target, file)
}

// targetFQ returns the fully-qualified name of the symbol at offset: a definition
// name-range it falls within, else the reference there resolved to its FQ name.
// file selects the document (so .rvt is extracted) and scopes page-local lookups.
// Returns "" if there is no resolvable symbol.
func (r *Resolver) targetFQ(file, src string, offset int) string {
	for _, d := range source.Defs(file, src) {
		if (d.Kind == tcl.DefProc || d.Kind == tcl.DefNamespaceVar) &&
			offset >= d.NameStart && offset < d.NameEnd {
			return d.Name
		}
	}
	if ref := refAt(file, src, offset); ref != nil {
		return r.refFQ(ref, file)
	}
	return ""
}

// lookupScoped returns the definition sites of a fully-qualified name. A
// page-local name (under ::request) resolves only to definitions in file, because
// the per-request namespace is recreated per page and not shared across templates.
// All other names resolve workspace-wide.
func (r *Resolver) lookupScoped(name, file string) []index.Location {
	locs := r.ix.Lookup(name)
	// Page-locality applies only when resolving from within a template: the
	// ::request namespace is recreated per request and not shared across .rvt
	// pages. A .tcl file that writes into ::request (unusual — outside the
	// supported model, see research/05-rvt-scope.md V2) resolves workspace-wide.
	if !source.IsRVT(file) || !strings.HasPrefix(name, "::request::") {
		return locs
	}
	var kept []index.Location
	for _, l := range locs {
		if l.File == file {
			kept = append(kept, l)
		}
	}
	return kept
}

// refFQ resolves a reference to the fully-qualified name it binds to, using the
// same first-match precedence as goto-definition. file is the document the ref
// lives in (used for page-local scoping in lookups). If no candidate is defined,
// the primary candidate is used so undefined references still group together.
func (r *Resolver) refFQ(ref *tcl.ContextRef, file string) string {
	cands := r.candidates(ref)
	for _, name := range cands {
		if len(r.lookupScoped(name, file)) > 0 {
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
