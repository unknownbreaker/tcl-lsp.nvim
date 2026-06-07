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
	// First word of each command.
	wantHeads := []string{"set", "puts", "incr"}
	for i, c := range got {
		if len(c.Words) != wantCounts[i] {
			t.Fatalf("command %d has %d words, want %d: %#v", i, len(c.Words), wantCounts[i], c)
		}
		if c.Words[0].Text != wantHeads[i] {
			t.Fatalf("command %d head = %q, want %q", i, c.Words[0].Text, wantHeads[i])
		}
	}
}

func TestParseSkipsComments(t *testing.T) {
	src := "# a comment\nset x 1\n# another\nputs $x"
	got := Parse(src)
	if len(got) != 2 {
		t.Fatalf("got %d commands, want 2 (comments skipped): %#v", len(got), got)
	}
	if got[0].Words[0].Text != "set" || got[1].Words[0].Text != "puts" {
		t.Fatalf("unexpected command heads: %#v", got)
	}
}

func TestParseWordKinds(t *testing.T) {
	got := Parse(`proc p {a b} "hello world"`)
	if len(got) != 1 {
		t.Fatalf("got %d commands, want 1: %#v", len(got), got)
	}
	words := got[0].Words
	wantKinds := []WordKind{WordBare, WordBare, WordBraced, WordQuoted}
	if len(words) != len(wantKinds) {
		t.Fatalf("got %d words, want %d: %#v", len(words), len(wantKinds), words)
	}
	for i, w := range words {
		if w.Kind != wantKinds[i] {
			t.Fatalf("word %d (%q) kind = %d, want %d", i, w.Text, w.Kind, wantKinds[i])
		}
	}
	// Braced/quoted word text includes its delimiters.
	if words[2].Text != "{a b}" {
		t.Fatalf("braced word text = %q, want %q", words[2].Text, "{a b}")
	}
	if words[3].Text != `"hello world"` {
		t.Fatalf("quoted word text = %q, want %q", words[3].Text, `"hello world"`)
	}
}

func TestParseRealisticSnippet(t *testing.T) {
	// A namespace command whose body is one (opaque) braced word at this layer.
	src := "namespace eval ::app {\n    set v 1\n}"
	got := Parse(src)
	if len(got) != 1 {
		t.Fatalf("got %d commands, want 1: %#v", len(got), got)
	}
	w := got[0].Words
	if len(w) != 4 {
		t.Fatalf("got %d words, want 4: %#v", len(w), w)
	}
	if w[0].Text != "namespace" || w[1].Text != "eval" || w[2].Text != "::app" {
		t.Fatalf("unexpected heads: %q %q %q", w[0].Text, w[1].Text, w[2].Text)
	}
	if w[3].Kind != WordBraced {
		t.Fatalf("body word kind = %d, want WordBraced", w[3].Kind)
	}
	// The body word's range slices back to its exact source text.
	if src[w[3].Start:w[3].End] != w[3].Text {
		t.Fatalf("body range mismatch: src[%d:%d]=%q text=%q", w[3].Start, w[3].End, src[w[3].Start:w[3].End], w[3].Text)
	}
	if w[3].Text != "{\n    set v 1\n}" {
		t.Fatalf("body text = %q", w[3].Text)
	}
}

func TestParseInlineHashIsNotComment(t *testing.T) {
	// `#` is only a comment at command start; mid-command it is a literal word.
	got := Parse("set x 1 # noise")
	if len(got) != 1 {
		t.Fatalf("got %d commands, want 1: %#v", len(got), got)
	}
	if len(got[0].Words) != 5 {
		t.Fatalf("got %d words, want 5: %#v", len(got[0].Words), got[0].Words)
	}
	if got[0].Words[3].Text != "#" || got[0].Words[4].Text != "noise" {
		t.Fatalf("unexpected trailing words: %#v", got[0].Words)
	}
}

func TestParseTrailingAndRepeatedSeparators(t *testing.T) {
	// Trailing separators and blank lines must not create empty commands.
	got := Parse("set x 1;\n\n\nputs y\n")
	if len(got) != 2 {
		t.Fatalf("got %d commands, want 2: %#v", len(got), got)
	}
	if got[0].Words[0].Text != "set" || got[1].Words[0].Text != "puts" {
		t.Fatalf("unexpected heads: %#v", got)
	}
}
