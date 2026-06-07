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
