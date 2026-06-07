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
