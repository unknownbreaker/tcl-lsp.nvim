package tcl

import (
	"reflect"
	"testing"
)

func findDef(defs []Definition, name string) *Definition {
	for i := range defs {
		if defs[i].Name == name {
			return &defs[i]
		}
	}
	return nil
}

func TestFileDefsProcGlobal(t *testing.T) {
	got := FileDefs("proc greet {} {}")
	want := []Definition{
		{Kind: DefProc, Name: "::greet", Namespace: "::", NameStart: 5, NameEnd: 10},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("\n got: %#v\nwant: %#v", got, want)
	}
}

func TestFileDefsProcInNamespace(t *testing.T) {
	src := "namespace eval ::app {\n  proc f {} {}\n}"
	got := FileDefs(src)
	d := findDef(got, "::app::f")
	if d == nil {
		t.Fatalf("did not find ::app::f in %#v", got)
	}
	if d.Kind != DefProc {
		t.Fatalf("kind = %d, want DefProc", d.Kind)
	}
	if src[d.NameStart:d.NameEnd] != "f" {
		t.Fatalf("name slice = %q, want f", src[d.NameStart:d.NameEnd])
	}
}
