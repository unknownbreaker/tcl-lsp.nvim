package tcl

// DefKind classifies a definition.
type DefKind int

const (
	DefProc        DefKind = iota // a proc (command) definition
	DefNamespaceVar               // a namespace variable (variable / qualified set / ns-top set)
	DefLocal                      // a proc-local variable (param, set, upvar alias)
	DefGlobalLink                 // a `global name` link to ::name
)

// Definition is a declaration site. Name is fully qualified for proc and
// namespace-variable kinds; for locals it is the bare local name. NameStart and
// NameEnd are the absolute byte range of the declared name token.
type Definition struct {
	Kind      DefKind
	Name      string
	Namespace string // the namespace the definition lives in ("::" for locals' enclosing)
	NameStart int
	NameEnd   int
}

// FileDefs parses src and returns the definitions it declares, recursing into
// namespace eval and proc bodies.
func FileDefs(src string) []Definition {
	var out []Definition
	walkDefs(Parse(src), 0, "::", FrameNamespace, &out)
	return out
}

func walkDefs(cmds []Command, base int, ns string, frame FrameKind, out *[]Definition) {
	for _, c := range cmds {
		emitDefs(c, base, ns, frame, out)
		recurseDefBodies(c, base, ns, out)
	}
}

func emitDefs(c Command, base int, ns string, frame FrameKind, out *[]Definition) {
	w := c.Words
	if isCmd(w, "proc") && len(w) >= 2 && isPlainName(w[1]) {
		name := qualifyName(w[1].Text, ns)
		*out = append(*out, Definition{
			Kind:      DefProc,
			Name:      name,
			Namespace: ns,
			NameStart: base + w[1].Start,
			NameEnd:   base + w[1].End,
		})
	}
	if isCmd(w, "variable") && len(w) >= 2 && isPlainName(w[1]) {
		*out = append(*out, Definition{
			Kind:      DefNamespaceVar,
			Name:      qualifyName(w[1].Text, ns),
			Namespace: ns,
			NameStart: base + w[1].Start,
			NameEnd:   base + w[1].End,
		})
	}
	if isCmd(w, "set") && frame == FrameNamespace && len(w) >= 2 && isPlainName(w[1]) {
		*out = append(*out, Definition{
			Kind:      DefNamespaceVar,
			Name:      qualifyName(w[1].Text, ns),
			Namespace: ns,
			NameStart: base + w[1].Start,
			NameEnd:   base + w[1].End,
		})
	}
}

func recurseDefBodies(c Command, base int, ns string, out *[]Definition) {
	w := c.Words
	if isCmd(w, "namespace") && len(w) >= 4 && w[1].Text == "eval" && w[len(w)-1].Kind == WordBraced {
		child := qualifyNamespace(w[2].Text, ns)
		inner, innerBase := bracedInner(w[len(w)-1], base)
		walkDefs(Parse(inner), innerBase, child, FrameNamespace, out)
	}
	if isCmd(w, "proc") && len(w) >= 4 && w[len(w)-1].Kind == WordBraced {
		inner, innerBase := bracedInner(w[len(w)-1], base)
		walkDefs(Parse(inner), innerBase, ns, FrameProc, out)
	}
}

// isPlainName reports whether a word is a bareword usable as a declared name
// (no substitution). Used for proc/variable/set targets.
func isPlainName(w Word) bool {
	return isLiteralName(w)
}

// qualifyName resolves a command/variable name against the current namespace:
// a leading "::" is absolute, otherwise it is qualified into current.
func qualifyName(name, current string) string {
	if len(name) >= 2 && name[0] == ':' && name[1] == ':' {
		return name
	}
	if current == "::" {
		return "::" + name
	}
	return current + "::" + name
}
