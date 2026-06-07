package tcl

import (
	"reflect"
	"testing"
)

func TestParseEmpty(t *testing.T) {
	got := Parse("")
	if len(got) != 0 {
		t.Fatalf("Parse(\"\") = %#v, want no commands", got)
	}
}

func TestParseWhitespaceOnly(t *testing.T) {
	got := Parse("   \n\t\n")
	if len(got) != 0 {
		t.Fatalf("Parse(whitespace) = %#v, want no commands", got)
	}
}

func TestParseSingleCommand(t *testing.T) {
	got := Parse("set x 1")
	want := []Command{
		{Words: []Word{
			{Kind: WordBare, Text: "set", Start: 0, End: 3},
			{Kind: WordBare, Text: "x", Start: 4, End: 5},
			{Kind: WordBare, Text: "1", Start: 6, End: 7},
		}},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("\n got: %#v\nwant: %#v", got, want)
	}
}

func TestParseMultipleCommands(t *testing.T) {
	got := Parse("set x 1\nputs $x;incr x")
	if len(got) != 3 {
		t.Fatalf("got %d commands, want 3: %#v", len(got), got)
	}
	// Command word counts: [set x 1], [puts $x], [incr x]
	wantCounts := []int{3, 2, 2}
	for i, c := range got {
		if len(c.Words) != wantCounts[i] {
			t.Fatalf("command %d has %d words, want %d: %#v", i, len(c.Words), wantCounts[i], c)
		}
	}
	// First word of each command.
	wantHeads := []string{"set", "puts", "incr"}
	for i, c := range got {
		if c.Words[0].Text != wantHeads[i] {
			t.Fatalf("command %d head = %q, want %q", i, c.Words[0].Text, wantHeads[i])
		}
	}
}
