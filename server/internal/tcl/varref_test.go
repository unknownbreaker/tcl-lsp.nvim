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

func TestWordVarRefsNamespaceQualified(t *testing.T) {
	w := Word{Kind: WordBare, Text: "$ns::name", Start: 0, End: 9}
	got := WordVarRefs(w)
	want := []VarRef{{Name: "ns::name", Start: 0, End: 9}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("\n got: %#v\nwant: %#v", got, want)
	}
}

func TestWordVarRefsGlobalQualified(t *testing.T) {
	w := Word{Kind: WordBare, Text: "$::g", Start: 0, End: 4}
	got := WordVarRefs(w)
	want := []VarRef{{Name: "::g", Start: 0, End: 4}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("\n got: %#v\nwant: %#v", got, want)
	}
}

func TestWordVarRefsArrayName(t *testing.T) {
	w := Word{Kind: WordBare, Text: "$arr(key)", Start: 0, End: 9}
	got := WordVarRefs(w)
	want := []VarRef{{Name: "arr", Start: 0, End: 4}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("\n got: %#v\nwant: %#v", got, want)
	}
}

func TestWordVarRefsArrayIndexVarAlsoFound(t *testing.T) {
	// The array name AND a variable used in the index are both references.
	w := Word{Kind: WordBare, Text: "$arr($idx)", Start: 0, End: 10}
	got := WordVarRefs(w)
	want := []VarRef{
		{Name: "arr", Start: 0, End: 4},
		{Name: "idx", Start: 5, End: 9},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("\n got: %#v\nwant: %#v", got, want)
	}
}
