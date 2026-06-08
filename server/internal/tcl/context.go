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

// recurseBodies walks the braced bodies of a command into the right scope:
// `namespace eval` and `proc` introduce a new scope; control-flow commands run
// their bodies in the enclosing namespace and frame.
func recurseBodies(c Command, base int, ns string, frame FrameKind, out *[]ContextRef) {
	w := c.Words
	switch {
	case isCmd(w, "namespace") && len(w) >= 4 && w[1].Text == "eval" && w[len(w)-1].Kind == WordBraced:
		// Body is taken as the last word (Tcl's `namespace eval name script` form;
		// for multi-arg scripts Tcl concatenates, and we recurse the final braced word).
		child := qualifyNamespace(w[2].Text, ns)
		inner, innerBase := bracedInner(w[len(w)-1], base)
		walkScript(Parse(inner), innerBase, child, FrameNamespace, out)
	case isCmd(w, "proc") && len(w) >= 4 && w[len(w)-1].Kind == WordBraced:
		// The proc body runs in the namespace where the proc is defined. For a
		// qualified proc name the body's namespace is that of the name; this is
		// refined when definitions are added. For now, use the current namespace.
		// TODO: for a qualified proc name (proc ::a::b {} {...}) the body runs in
		// ::a, not the current namespace. Refined when definitions are added.
		inner, innerBase := bracedInner(w[len(w)-1], base)
		walkScript(Parse(inner), innerBase, ns, FrameProc, out)
	default:
		// Control-flow commands (if/while/for/foreach/catch/try) run their script
		// bodies in the enclosing namespace and frame -- no new scope. Recurse into
		// each so calls inside loops/conditionals are found.
		for _, body := range scriptBodies(w) {
			inner, innerBase := bracedInner(body, base)
			walkScript(Parse(inner), innerBase, ns, frame, out)
		}
	}
}

// scriptBodies returns the braced script-argument words of a control-flow
// command -- the bodies that execute in the enclosing scope. Expression
// arguments (a while/if condition, a for test) are deliberately excluded so
// their contents are not misread as commands.
func scriptBodies(w []Word) []Word {
	if len(w) == 0 || w[0].Kind != WordBare {
		return nil
	}
	braced := func(i int) bool { return i >= 0 && i < len(w) && w[i].Kind == WordBraced }
	last := len(w) - 1
	switch w[0].Text {
	case "while", "foreach", "lmap":
		// while test body ; foreach/lmap (var list)+ body -- body is the last word.
		if braced(last) {
			return []Word{w[last]}
		}
	case "dict":
		// dict for {k v} dict body ; dict map {k v} dict body -- body is last.
		if len(w) >= 2 && w[1].Kind == WordBare && (w[1].Text == "for" || w[1].Text == "map") && braced(last) {
			return []Word{w[last]}
		}
	case "catch":
		// catch script ?resultVar? ?optionsVar? -- the first arg is the script.
		if braced(1) {
			return []Word{w[1]}
		}
	case "for":
		// for start test next body -- start, next and body are scripts; test is expr.
		var bodies []Word
		for _, i := range []int{1, 3, 4} {
			if braced(i) {
				bodies = append(bodies, w[i])
			}
		}
		return bodies
	case "if":
		return ifBodies(w)
	case "try":
		return tryBodies(w)
	default:
		// User-defined or unrecognised commands: by strong Tcl convention a
		// trailing braced argument is a script body (custom control structures,
		// test harnesses, oo definitions; switch arms are handled transitively as
		// each parsed arm is itself such a command). Recurse it so calls inside are
		// found. Builtins whose braced argument is data or an expression are
		// excluded so their contents are not misread as command calls.
		if !dataBraceCommands[w[0].Text] && braced(last) {
			return []Word{w[last]}
		}
	}
	return nil
}

// dataBraceCommands are builtins whose braced arguments hold data or an
// expression -- never a script body -- so they are excluded from the
// trailing-braced-argument script heuristic in scriptBodies.
var dataBraceCommands = map[string]bool{
	"expr": true, "set": true, "list": true, "lappend": true, "lset": true,
	"append": true, "incr": true, "array": true, "string": true,
	"global": true, "variable": true, "return": true,
}

// ifBodies returns the braced body words of an if command, excluding the
// condition expressions. A braced word is a body unless it is the expression
// immediately following `if` or `elseif`.
func ifBodies(w []Word) []Word {
	var bodies []Word
	for i := 1; i < len(w); i++ {
		if w[i].Kind != WordBraced {
			continue
		}
		if prev := w[i-1]; prev.Kind == WordBare && (prev.Text == "if" || prev.Text == "elseif") {
			continue // condition expression, not a body
		}
		bodies = append(bodies, w[i])
	}
	return bodies
}

// tryBodies returns the braced body words of a try command: the main body, each
// on/trap handler body (3 words past the keyword, after code/pattern and the
// variable list), and the finally body. Patterns and variable lists are skipped.
func tryBodies(w []Word) []Word {
	var bodies []Word
	if len(w) >= 2 && w[1].Kind == WordBraced {
		bodies = append(bodies, w[1]) // try BODY
	}
	for i := 2; i < len(w); i++ {
		if w[i].Kind != WordBare {
			continue
		}
		switch w[i].Text {
		case "on", "trap":
			if i+3 < len(w) && w[i+3].Kind == WordBraced {
				bodies = append(bodies, w[i+3])
			}
		case "finally":
			if i+1 < len(w) && w[i+1].Kind == WordBraced {
				bodies = append(bodies, w[i+1])
			}
		}
	}
	return bodies
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
