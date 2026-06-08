package tcl

import (
	"reflect"
	"testing"
)

func findVar(refs []ContextRef, name string) *ContextRef {
	for i := range refs {
		if refs[i].Ref.Kind == RefVariable && refs[i].Ref.Name == name {
			return &refs[i]
		}
	}
	return nil
}

func TestFileRefsFlatGlobal(t *testing.T) {
	got := FileRefs("set x $y")
	want := []ContextRef{
		{Ref: Reference{Kind: RefCommand, Name: "set", Start: 0, End: 3}, Namespace: "::", Frame: FrameNamespace},
		{Ref: Reference{Kind: RefVariable, Name: "y", Start: 6, End: 8}, Namespace: "::", Frame: FrameNamespace},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("\n got: %#v\nwant: %#v", got, want)
	}
}

func TestFileRefsNamespaceEval(t *testing.T) {
	src := "namespace eval ::app {\n    set v $w\n}"
	got := FileRefs(src)
	vw := findVar(got, "w")
	if vw == nil {
		t.Fatalf("did not find var w in %#v", got)
	}
	if vw.Namespace != "::app" {
		t.Fatalf("namespace = %q, want ::app", vw.Namespace)
	}
	if vw.Frame != FrameNamespace {
		t.Fatalf("frame = %d, want FrameNamespace", vw.Frame)
	}
	if src[vw.Ref.Start:vw.Ref.End] != "$w" {
		t.Fatalf("offset slice = %q, want $w", src[vw.Ref.Start:vw.Ref.End])
	}
}

func TestFileRefsNestedNamespace(t *testing.T) {
	src := "namespace eval ::a { namespace eval b { set x $y } }"
	got := FileRefs(src)
	vy := findVar(got, "y")
	if vy == nil {
		t.Fatalf("did not find var y in %#v", got)
	}
	if vy.Namespace != "::a::b" {
		t.Fatalf("namespace = %q, want ::a::b", vy.Namespace)
	}
}
