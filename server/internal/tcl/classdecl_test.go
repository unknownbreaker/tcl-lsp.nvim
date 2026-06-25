package tcl

import (
	"reflect"
	"testing"
)

func TestFileClassesInherit(t *testing.T) {
	src := "itcl::class ::Derived { inherit ::Base }"
	m := FileClasses(src)
	got, ok := m["::Derived"]
	if !ok {
		t.Fatalf("::Derived not in FileClasses result: %#v", m)
	}
	if !reflect.DeepEqual(got, []string{"::Base"}) {
		t.Fatalf("FileClasses[::Derived] = %#v, want [::Base]", got)
	}
}

func TestFileClassesNoInherit(t *testing.T) {
	src := "itcl::class ::Standalone { method run {} {} }"
	m := FileClasses(src)
	if len(m) != 0 {
		t.Fatalf("expected empty map for class with no inherit, got %#v", m)
	}
}

func TestFileClassesMultipleBases(t *testing.T) {
	src := "itcl::class ::Child { inherit ::A ::B }"
	m := FileClasses(src)
	got := m["::Child"]
	if !reflect.DeepEqual(got, []string{"::A", "::B"}) {
		t.Fatalf("FileClasses[::Child] = %#v, want [::A ::B]", got)
	}
}

func TestFileClassesRelativeName(t *testing.T) {
	// A bare (unqualified) base name is qualified relative to the current namespace.
	src := "namespace eval ::ns { itcl::class Child { inherit Base } }"
	m := FileClasses(src)
	got := m["::ns::Child"]
	if !reflect.DeepEqual(got, []string{"::ns::Base"}) {
		t.Fatalf("FileClasses[::ns::Child] = %#v, want [::ns::Base]", got)
	}
}
