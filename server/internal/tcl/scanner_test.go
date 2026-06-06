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
