package tcl

import (
	"reflect"
	"testing"
)

func TestCommandRefsSimple(t *testing.T) {
	// "set x $y": head `set`, arg `x` is a literal bareword (no ref at this
	// layer — it is a definition target handled later), arg `$y` is a var ref.
	cmds := Parse("set x $y")
	got := CommandRefs(cmds[0])
	want := []Reference{
		{Kind: RefCommand, Name: "set", Start: 0, End: 3},
		{Kind: RefVariable, Name: "y", Start: 6, End: 8},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("\n got: %#v\nwant: %#v", got, want)
	}
}

func TestCommandRefsBareCommandOnly(t *testing.T) {
	cmds := Parse("exit")
	got := CommandRefs(cmds[0])
	want := []Reference{{Kind: RefCommand, Name: "exit", Start: 0, End: 4}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("\n got: %#v\nwant: %#v", got, want)
	}
}

func TestCommandRefsDynamicHead(t *testing.T) {
	// First word `$handler` is dynamic (contains $): not a command-name ref,
	// but the variable `handler` is a reference. Arg `arg` yields nothing.
	cmds := Parse("$handler arg")
	got := CommandRefs(cmds[0])
	want := []Reference{{Kind: RefVariable, Name: "handler", Start: 0, End: 8}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("\n got: %#v\nwant: %#v", got, want)
	}
}

func TestCommandRefsBracketRecursion(t *testing.T) {
	// "set y [foo $x]": head set, nested command foo, nested var x.
	cmds := Parse("set y [foo $x]")
	got := CommandRefs(cmds[0])
	want := []Reference{
		{Kind: RefCommand, Name: "set", Start: 0, End: 3},
		{Kind: RefCommand, Name: "foo", Start: 7, End: 10},
		{Kind: RefVariable, Name: "x", Start: 11, End: 13},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("\n got: %#v\nwant: %#v", got, want)
	}
}

func TestCommandRefsNestedBrackets(t *testing.T) {
	cmds := Parse("puts [a [b $x]]")
	got := CommandRefs(cmds[0])
	want := []Reference{
		{Kind: RefCommand, Name: "puts", Start: 0, End: 4},
		{Kind: RefCommand, Name: "a", Start: 6, End: 7},
		{Kind: RefCommand, Name: "b", Start: 9, End: 10},
		{Kind: RefVariable, Name: "x", Start: 11, End: 13},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("\n got: %#v\nwant: %#v", got, want)
	}
}

func TestCommandRefsBracketHead(t *testing.T) {
	// Dynamic head via command substitution: "[get] a" -> command `get`.
	cmds := Parse("[get] a")
	got := CommandRefs(cmds[0])
	want := []Reference{{Kind: RefCommand, Name: "get", Start: 1, End: 4}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("\n got: %#v\nwant: %#v", got, want)
	}
}

func TestCommandRefsAbsoluteOffsets(t *testing.T) {
	src := "lappend ::items $x"
	cmds := Parse(src)
	got := CommandRefs(cmds[0])
	want := []Reference{
		{Kind: RefCommand, Name: "lappend", Start: 0, End: 7},
		{Kind: RefVariable, Name: "x", Start: 16, End: 18},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("\n got: %#v\nwant: %#v", got, want)
	}
	if src[got[0].Start:got[0].End] != "lappend" {
		t.Fatalf("command offset slice = %q", src[got[0].Start:got[0].End])
	}
	if src[got[1].Start:got[1].End] != "$x" {
		t.Fatalf("var offset slice = %q", src[got[1].Start:got[1].End])
	}
}

func TestCommandRefsBracketEmpty(t *testing.T) {
	// An empty/whitespace-only [ ] span yields no nested references.
	cmds := Parse("set x [ ]")
	got := CommandRefs(cmds[0])
	want := []Reference{{Kind: RefCommand, Name: "set", Start: 0, End: 3}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("\n got: %#v\nwant: %#v", got, want)
	}
}

func TestCommandRefsExprBracedLimitation(t *testing.T) {
	// KNOWN LIMITATION: a variable inside a braced expr argument is not found
	// (braces suppress substitution structurally; we do not model expr's
	// re-evaluation of its argument). We still find `set` and `expr`.
	cmds := Parse("set y [expr {$x + 1}]")
	got := CommandRefs(cmds[0])
	for _, r := range got {
		if r.Kind == RefVariable && r.Name == "x" {
			t.Fatalf("did not expect $x inside braced expr arg (known limitation): %#v", got)
		}
	}
	foundExpr := false
	for _, r := range got {
		if r.Kind == RefCommand && r.Name == "expr" {
			foundExpr = true
		}
	}
	if !foundExpr {
		t.Fatalf("expected expr command in: %#v", got)
	}
}
