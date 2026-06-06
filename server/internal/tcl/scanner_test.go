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
