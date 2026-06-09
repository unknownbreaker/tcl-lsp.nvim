package tcl

import "strings"

// FrameKind is the kind of scope a reference appears in. Variable resolution
// differs by frame: inside a proc body a bare variable is local-only, while at
// namespace-eval top level it is the namespace's own variable.
type FrameKind int

const (
	FrameNamespace FrameKind = iota // namespace-eval top level (incl. global ::)
	FrameProc                       // inside a proc body
)

// ContextRef is a reference together with the namespace and frame at its site.
type ContextRef struct {
	Ref       Reference
	Namespace string // e.g. "::" or "::app"
	Frame     FrameKind
}

// FileRefs parses src and returns every reference with its namespace and frame
// context, recursing into namespace eval and proc bodies.
func FileRefs(src string) []ContextRef {
	var out []ContextRef
	walkScript(Parse(src), 0, "::", FrameNamespace, &out)
	return out
}

// walkScript appends contextual refs for each command. base is added to ref
// offsets so refs from a re-parsed (braced) body map back to absolute source.
func walkScript(cmds []Command, base int, ns string, frame FrameKind, out *[]ContextRef) {
	for _, c := range cmds {
		for _, r := range CommandRefs(c) {
			r.Start += base
			r.End += base
			*out = append(*out, ContextRef{Ref: r, Namespace: ns, Frame: frame})
		}
		recurseBodies(c, base, ns, frame, out)
	}
}

// recurseBodies walks each of a command's script bodies (as classified by the
// shared childBodies) into the scope it runs in, collecting references. See
// bodies.go for the body-vs-data/expression rules.
func recurseBodies(c Command, base int, ns string, frame FrameKind, out *[]ContextRef) {
	for _, b := range childBodies(c, base, ns, frame) {
		walkScript(Parse(b.Inner), b.Base, b.NS, b.Frame, out)
	}
}

// isCmd reports whether the command's literal head equals name.
// Note: a user command whose literal first word is "proc"/"namespace" would be
// treated as a scope-introducer (an accepted limitation of lightweight parsing).
func isCmd(words []Word, name string) bool {
	return len(words) > 0 && words[0].Kind == WordBare && words[0].Text == name
}

// qualifyNamespace resolves a namespace name argument against the current
// namespace: a leading "::" is absolute, otherwise it is relative to current.
func qualifyNamespace(name, current string) string {
	if strings.HasPrefix(name, "::") {
		return name
	}
	if current == "::" {
		return "::" + name
	}
	return current + "::" + name
}

// bracedInner returns the interior of a braced word and the absolute offset of
// that interior's first byte (base + word.Start + 1).
func bracedInner(w Word, base int) (string, int) {
	t := w.Text
	if len(t) >= 2 && t[0] == '{' && t[len(t)-1] == '}' {
		return t[1 : len(t)-1], base + w.Start + 1
	}
	// The scanner guarantees WordBraced words are "{...}", so callers that pass a
	// braced word never reach this fallback; it is defensive only.
	return "", base + w.Start
}
