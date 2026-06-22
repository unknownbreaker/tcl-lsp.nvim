package tcl

// This file is the single source of truth for two things every tree walker in
// this package needs: (1) which braced words of a command are *script bodies*
// (vs. data or expressions), and (2) the namespace/frame each body executes in.
// The definition walker (defs.go), reference walker (context.go), and namespace
// walker (nsdecl.go) all recurse via childBodies, so they cannot drift -- e.g.
// one recursing into control-flow bodies while another silently does not (the
// bug that hid procs defined inside `if`/`catch` blocks from goto-definition).

// bodyScope is a braced script body to recurse into, with the namespace and
// frame it executes in.
type bodyScope struct {
	Inner string    // source text of the body's interior
	Base  int       // absolute offset of Inner's first byte
	NS    string    // namespace the body runs in
	Frame FrameKind // frame kind the body runs in
	Scope int       // enclosing proc body's interior offset; 0 at namespace frame
}

// childBodies returns the script bodies of c that walkers should recurse into,
// each tagged with the scope it runs in. `namespace eval` and `proc` introduce a
// new scope; control-flow and custom-command script bodies run in the enclosing
// namespace and frame.
func childBodies(c Command, base int, ns string, frame FrameKind, scope int) []bodyScope {
	w := c.Words
	switch {
	case isCmd(w, "namespace") && len(w) >= 4 && w[1].Text == "eval" && w[len(w)-1].Kind == WordBraced:
		// Body is the last word (Tcl's `namespace eval name script` form; for
		// multi-arg scripts Tcl concatenates, and we recurse the final braced word).
		inner, innerBase := bracedInner(w[len(w)-1], base)
		return []bodyScope{{Inner: inner, Base: innerBase, NS: qualifyNamespace(w[2].Text, ns), Frame: FrameNamespace, Scope: 0}}
	case isCmd(w, "proc") && len(w) >= 4 && w[len(w)-1].Kind == WordBraced:
		// The proc body runs in the namespace where the proc is defined. For a
		// qualified proc name (proc ::a::b {} {...}) the body runs in ::a, not the
		// current namespace; that refinement is not yet modeled, so we use ns.
		inner, innerBase := bracedInner(w[len(w)-1], base)
		return []bodyScope{{Inner: inner, Base: innerBase, NS: ns, Frame: FrameProc, Scope: innerBase}}
	default:
		// A decorated proc definition (`CACHE_PROC proc name args body`): its body
		// is a proc scope, exactly like a plain proc.
		if _, _, body, ok := decoratedProcDef(w); ok {
			inner, innerBase := bracedInner(body, base)
			return []bodyScope{{Inner: inner, Base: innerBase, NS: ns, Frame: FrameProc, Scope: innerBase}}
		}
		// Control-flow (if/while/for/foreach/catch/try) and custom-command script
		// bodies run in the enclosing namespace and frame -- no new scope.
		var out []bodyScope
		for _, body := range scriptBodies(w) {
			inner, innerBase := bracedInner(body, base)
			out = append(out, bodyScope{Inner: inner, Base: innerBase, NS: ns, Frame: frame, Scope: scope})
		}
		return out
	}
}

// decoratedProcDef recognizes a proc definition created through a proc-defining
// macro: `WRAPPER... proc NAME ARGS BODY ...`, where the command head is the macro
// (e.g. CACHE_PROC) rather than `proc`. It matches the first `proc NAME ARGS BODY`
// quadruple -- NAME a plain name, BODY braced -- that has at least one decorator
// word before `proc`. Words *after* BODY (e.g. `-ttl 60`, `-log debug`) are macro
// flags and are ignored, so the body need not be the command's last word. The
// head must not be `proc` (handled directly by the proc cases) nor a list/data
// builtin (so `lappend x proc foo {} {}` is not misread). This covers single,
// argument-taking, and stacked decorators, a qualified NAME, and trailing flags.
func decoratedProcDef(w []Word) (name, args, body Word, ok bool) {
	if len(w) < 5 || w[0].Kind != WordBare || listOrDataHeads[w[0].Text] {
		return // need at least DECORATOR proc NAME ARGS BODY, head a decorator word
	}
	// Scan for `proc NAME ARGS BODY` starting after the first (decorator) word.
	for i := 1; i+3 < len(w); i++ {
		if w[i].Kind == WordBare && w[i].Text == "proc" && isPlainName(w[i+1]) && w[i+3].Kind == WordBraced {
			return w[i+1], w[i+2], w[i+3], true
		}
	}
	return
}

// listOrDataHeads are builtins whose arguments may literally contain the word
// `proc` as data (a list element or value), so a trailing `proc name args body`
// in them is not a decorated proc definition.
var listOrDataHeads = map[string]bool{
	"set": true, "list": true, "lappend": true, "lassign": true, "lset": true,
	"linsert": true, "lreplace": true, "concat": true, "dict": true,
	"array": true, "append": true, "return": true, "expr": true,
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

// exprBodies returns the braced words a command evaluates as *expressions* (not
// scripts): every braced argument of `expr`, the conditions of if/elseif, the
// test of while, and the test clause of for. Tcl's expr engine evaluates
// [command substitutions] inside these braces even though braces normally
// suppress substitution, so the reference walker must scan them for embedded
// calls -- a proc called only inside `if {[ready]} { ... }` is otherwise
// invisible. This is the exact complement of scriptBodies/ifBodies for these
// commands: a braced if-word is either a condition (here) or a body (there),
// never both, so the two classifications cannot drift.
func exprBodies(w []Word) []Word {
	if len(w) == 0 || w[0].Kind != WordBare {
		return nil
	}
	braced := func(i int) bool { return i >= 0 && i < len(w) && w[i].Kind == WordBraced }
	switch w[0].Text {
	case "expr":
		var out []Word
		for _, x := range w[1:] {
			if x.Kind == WordBraced {
				out = append(out, x)
			}
		}
		return out
	case "while":
		if braced(1) { // while TEST body -- TEST is an expression.
			return []Word{w[1]}
		}
	case "for":
		if braced(2) { // for start TEST next body -- TEST is an expression.
			return []Word{w[2]}
		}
	case "if":
		return ifConditions(w)
	}
	return nil
}

// ifConditions returns the braced condition words of an if command: the words
// immediately following `if` or `elseif`. It is the exact complement of ifBodies,
// which returns every other braced word.
func ifConditions(w []Word) []Word {
	var conds []Word
	for i := 1; i < len(w); i++ {
		if w[i].Kind != WordBraced {
			continue
		}
		if prev := w[i-1]; prev.Kind == WordBare && (prev.Text == "if" || prev.Text == "elseif") {
			conds = append(conds, w[i])
		}
	}
	return conds
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
