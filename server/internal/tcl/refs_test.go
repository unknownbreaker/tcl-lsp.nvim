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
