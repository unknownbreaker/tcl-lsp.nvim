package tcl

import (
	"reflect"
	"testing"
)

func TestWordVarRefsBracedNone(t *testing.T) {
	w := Word{Kind: WordBraced, Text: "{a $x b}", Start: 0, End: 8}
	if got := WordVarRefs(w); len(got) != 0 {
		t.Fatalf("braced word should yield no refs, got %#v", got)
	}
}

func TestWordVarRefsSimple(t *testing.T) {
	w := Word{Kind: WordBare, Text: "$x", Start: 4, End: 6}
	got := WordVarRefs(w)
	want := []VarRef{{Name: "x", Start: 4, End: 6}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("\n got: %#v\nwant: %#v", got, want)
	}
}

func TestWordVarRefsLoneDollar(t *testing.T) {
	w := Word{Kind: WordBare, Text: "price$", Start: 0, End: 6}
	if got := WordVarRefs(w); len(got) != 0 {
		t.Fatalf("lone $ is not a ref, got %#v", got)
	}
}

func TestWordVarRefsBracedName(t *testing.T) {
	// ${...} allows any characters (including spaces) in the name.
	w := Word{Kind: WordBare, Text: "${my var}", Start: 0, End: 9}
	got := WordVarRefs(w)
	want := []VarRef{{Name: "my var", Start: 0, End: 9}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("\n got: %#v\nwant: %#v", got, want)
	}
}
