package tcl

import "strings"

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
		recurseDefBodies(c, base, ns, frame, out)
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
	if isCmd(w, "set") && frame == FrameProc && len(w) >= 2 && isPlainName(w[1]) {
		*out = append(*out, Definition{
			Kind: DefLocal, Name: w[1].Text, Namespace: ns,
			NameStart: base + w[1].Start, NameEnd: base + w[1].End,
		})
	}
	if isCmd(w, "global") && frame == FrameProc {
		for _, gw := range w[1:] {
			if isPlainName(gw) {
				*out = append(*out, Definition{
					Kind: DefGlobalLink, Name: gw.Text, Namespace: ns,
					NameStart: base + gw.Start, NameEnd: base + gw.End,
				})
			}
		}
	}
	if isCmd(w, "upvar") && frame == FrameProc && len(w) >= 3 {
		args := w[1:]
		// Optional leading level (e.g. 1 or #0); the rest are (otherVar, alias)
		// pairs. The alias names are static locals; the otherVar targets are often
		// dynamic and not recorded here.
		if len(args) > 0 && isUpvarLevel(args[0]) {
			args = args[1:]
		}
		for i := 1; i < len(args); i += 2 {
			alias := args[i]
			if isPlainName(alias) {
				*out = append(*out, Definition{
					Kind: DefLocal, Name: alias.Text, Namespace: ns,
					NameStart: base + alias.Start, NameEnd: base + alias.End,
				})
			}
		}
	}
}

func recurseDefBodies(c Command, base int, ns string, frame FrameKind, out *[]Definition) {
	// A proc's parameters are local definitions specific to the def walker; emit
	// them before recursing the body. Body recursion uses the shared childBodies
	// (bodies.go) so definitions and references descend the same bodies --
	// including control-flow ones, so a proc defined inside an if/catch/foreach
	// (e.g. conditional definition) is indexed.
	w := c.Words
	if isCmd(w, "proc") && len(w) >= 4 && w[len(w)-1].Kind == WordBraced {
		emitProcParams(w[2], base, ns, out)
	}
	for _, b := range childBodies(c, base, ns, frame) {
		walkDefs(Parse(b.Inner), b.Base, b.NS, b.Frame, out)
	}
}

// isPlainName is currently equivalent to isLiteralName; kept as a distinct
// entry point in case definition-target rules diverge from command-name rules.
//
// isPlainName reports whether a word is a bareword usable as a declared name
// (no substitution). Used for proc/variable/set targets.
func isPlainName(w Word) bool {
	return isLiteralName(w)
}

// isUpvarLevel reports whether a word is an upvar level argument (a number like
// "1" or a #-prefixed absolute level like "#0"), as opposed to a variable name.
func isUpvarLevel(w Word) bool {
	if w.Kind != WordBare || w.Text == "" {
		return false
	}
	if w.Text[0] == '#' {
		return true
	}
	for i := 0; i < len(w.Text); i++ {
		if w.Text[i] < '0' || w.Text[i] > '9' {
			return false
		}
	}
	return true
}

// emitProcParams emits a DefLocal for each parameter name in a proc args word.
func emitProcParams(argsWord Word, base int, ns string, out *[]Definition) {
	inner, innerBase := argsWord, base
	text := inner.Text
	start := innerBase + inner.Start
	if inner.Kind == WordBraced && len(text) >= 2 {
		text = text[1 : len(text)-1]
		start = innerBase + inner.Start + 1
	}
	for _, p := range scanParams(text, start) {
		*out = append(*out, Definition{
			Kind: DefLocal, Name: p.Name, Namespace: ns,
			NameStart: p.Start, NameEnd: p.End,
		})
	}
}

type paramName struct {
	Name       string
	Start, End int
}

func scanParams(text string, base int) []paramName {
	var ps []paramName
	cmds := Parse(text)
	for _, c := range cmds {
		for _, word := range c.Words {
			name, s, e := paramFromWord(word, base)
			if name != "" {
				ps = append(ps, paramName{Name: name, Start: s, End: e})
			}
		}
	}
	return ps
}

// paramFromWord extracts the parameter name and its absolute range from one
// args-list element: a bareword `name`, or a braced `{name default}` (first
// inner word). base is the absolute offset of the params text's first byte.
func paramFromWord(w Word, base int) (string, int, int) {
	if w.Kind == WordBraced && len(w.Text) >= 2 {
		inner := w.Text[1 : len(w.Text)-1]
		innerBase := base + w.Start + 1
		for _, c := range Parse(inner) {
			if len(c.Words) > 0 {
				fw := c.Words[0]
				return fw.Text, innerBase + fw.Start, innerBase + fw.End
			}
		}
		return "", 0, 0
	}
	if w.Kind == WordBare && w.Text != "" {
		return w.Text, base + w.Start, base + w.End
	}
	return "", 0, 0
}

// qualifyName resolves a command/variable name against the current namespace:
// a leading "::" is absolute, otherwise it is qualified into current.
func qualifyName(name, current string) string {
	if strings.HasPrefix(name, "::") {
		return name
	}
	if current == "::" {
		return "::" + name
	}
	return current + "::" + name
}
