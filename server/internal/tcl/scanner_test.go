package tcl

import (
	"reflect"
	"testing"
)

// kt is a compact (kind, text) pair for readable assertions.
type kt struct {
	K Kind
	T string
}

func summarize(toks []Token) []kt {
	out := make([]kt, len(toks))
	for i, tk := range toks {
		out[i] = kt{tk.Kind, tk.Text}
	}
	return out
}

func TestScanEmpty(t *testing.T) {
	got := summarize(Scan(""))
	want := []kt{{KindEOF, ""}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("Scan(\"\")\n got: %#v\nwant: %#v", got, want)
	}
}

func TestScanBarewords(t *testing.T) {
	got := summarize(Scan("set x 1"))
	want := []kt{
		{KindWord, "set"},
		{KindWord, "x"},
		{KindWord, "1"},
		{KindEOF, ""},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("Scan(\"set x 1\")\n got: %#v\nwant: %#v", got, want)
	}
}

func TestScanLeadingAndTrailingSpaces(t *testing.T) {
	got := summarize(Scan("  ab\tcd  "))
	want := []kt{
		{KindWord, "ab"},
		{KindWord, "cd"},
		{KindEOF, ""},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf(" got: %#v\nwant: %#v", got, want)
	}
}

func TestScanSeparators(t *testing.T) {
	got := summarize(Scan("a b\nc;d"))
	want := []kt{
		{KindWord, "a"},
		{KindWord, "b"},
		{KindNewline, "\n"},
		{KindWord, "c"},
		{KindSemicolon, ";"},
		{KindWord, "d"},
		{KindEOF, ""},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf(" got: %#v\nwant: %#v", got, want)
	}
}

func TestScanComment(t *testing.T) {
	got := summarize(Scan("# hi there\nset x 1"))
	want := []kt{
		{KindComment, "# hi there"},
		{KindNewline, "\n"},
		{KindWord, "set"},
		{KindWord, "x"},
		{KindWord, "1"},
		{KindEOF, ""},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf(" got: %#v\nwant: %#v", got, want)
	}
}

func TestHashMidCommandIsNotComment(t *testing.T) {
	// `#` is only a comment at command start; mid-command it is a literal word.
	got := summarize(Scan("set x #y"))
	want := []kt{
		{KindWord, "set"},
		{KindWord, "x"},
		{KindWord, "#y"},
		{KindEOF, ""},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf(" got: %#v\nwant: %#v", got, want)
	}
}

func TestScanBracedWord(t *testing.T) {
	got := summarize(Scan("proc p {a b} {body here}"))
	want := []kt{
		{KindWord, "proc"},
		{KindWord, "p"},
		{KindWord, "{a b}"},
		{KindWord, "{body here}"},
		{KindEOF, ""},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf(" got: %#v\nwant: %#v", got, want)
	}
}

func TestScanNestedBraces(t *testing.T) {
	got := summarize(Scan("set x {a {b} c}"))
	want := []kt{
		{KindWord, "set"},
		{KindWord, "x"},
		{KindWord, "{a {b} c}"},
		{KindEOF, ""},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf(" got: %#v\nwant: %#v", got, want)
	}
}

func TestScanUnterminatedBrace(t *testing.T) {
	got := summarize(Scan("set x {a b"))
	want := []kt{
		{KindWord, "set"},
		{KindWord, "x"},
		{KindWord, "{a b"},
		{KindEOF, ""},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf(" got: %#v\nwant: %#v", got, want)
	}
}

func TestScanQuotedWord(t *testing.T) {
	got := summarize(Scan(`set x "a b;c"`))
	want := []kt{
		{KindWord, "set"},
		{KindWord, "x"},
		{KindWord, `"a b;c"`},
		{KindEOF, ""},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf(" got: %#v\nwant: %#v", got, want)
	}
}

func TestScanQuotedWithEscapedQuote(t *testing.T) {
	got := summarize(Scan(`puts "she said \"hi\""`))
	want := []kt{
		{KindWord, "puts"},
		{KindWord, `"she said \"hi\""`},
		{KindEOF, ""},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf(" got: %#v\nwant: %#v", got, want)
	}
}

func TestScanBracketInBareword(t *testing.T) {
	got := summarize(Scan("set x [expr {1 + 2}]"))
	want := []kt{
		{KindWord, "set"},
		{KindWord, "x"},
		{KindWord, "[expr {1 + 2}]"},
		{KindEOF, ""},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf(" got: %#v\nwant: %#v", got, want)
	}
}

func TestScanNestedBrackets(t *testing.T) {
	got := summarize(Scan("set x a[b [c d]]e"))
	want := []kt{
		{KindWord, "set"},
		{KindWord, "x"},
		{KindWord, "a[b [c d]]e"},
		{KindEOF, ""},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf(" got: %#v\nwant: %#v", got, want)
	}
}

func TestScanEscapedSpaceInBareword(t *testing.T) {
	got := summarize(Scan(`set x a\ b`))
	want := []kt{
		{KindWord, "set"},
		{KindWord, "x"},
		{KindWord, `a\ b`},
		{KindEOF, ""},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf(" got: %#v\nwant: %#v", got, want)
	}
}

func TestScanLineContinuation(t *testing.T) {
	// Backslash-newline is whitespace, not a command separator.
	got := summarize(Scan("set x \\\n1"))
	want := []kt{
		{KindWord, "set"},
		{KindWord, "x"},
		{KindWord, "1"},
		{KindEOF, ""},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf(" got: %#v\nwant: %#v", got, want)
	}
}

func TestScanRealisticSnippet(t *testing.T) {
	src := "namespace eval ::app {\n    variable v 1\n    proc f {x} { return [expr {$x + $v}] }\n}"
	got := summarize(Scan(src))
	want := []kt{
		{KindWord, "namespace"},
		{KindWord, "eval"},
		{KindWord, "::app"},
		{KindWord, "{\n    variable v 1\n    proc f {x} { return [expr {$x + $v}] }\n}"},
		{KindEOF, ""},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf(" got: %#v\nwant: %#v", got, want)
	}
}

func TestTokenByteOffsetsAreExact(t *testing.T) {
	src := "set x 1"
	toks := Scan(src)
	// The word "x" sits at bytes [4,5).
	var xtok Token
	found := false
	for _, tk := range toks {
		if tk.Kind == KindWord && tk.Text == "x" {
			xtok = tk
			found = true
		}
	}
	if !found {
		t.Fatal("token \"x\" not found in scan output")
	}
	if xtok.Start != 4 || xtok.End != 5 {
		t.Fatalf("x offsets: got [%d,%d), want [4,5)", xtok.Start, xtok.End)
	}
	if src[xtok.Start:xtok.End] != "x" {
		t.Fatalf("offset slice mismatch: %q", src[xtok.Start:xtok.End])
	}
}

func TestScanBracedBackslashEscapedBrace(t *testing.T) {
	// In TCL a backslash-quoted brace is not counted toward depth, so the
	// matching close brace is the final one. Verified on tclsh 8.6.
	got := summarize(Scan("set a {\\}}"))
	want := []kt{
		{KindWord, "set"},
		{KindWord, "a"},
		{KindWord, "{\\}}"},
		{KindEOF, ""},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf(" got: %#v\nwant: %#v", got, want)
	}
}
