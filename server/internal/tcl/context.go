package tcl

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
	}
}
