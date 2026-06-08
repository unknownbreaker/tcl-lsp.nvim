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

func TestFileDefsVariable(t *testing.T) {
	src := "namespace eval ::app {\n  variable count 0\n}"
	got := FileDefs(src)
	d := findDef(got, "::app::count")
	if d == nil {
		t.Fatalf("did not find ::app::count in %#v", got)
	}
	if d.Kind != DefNamespaceVar {
		t.Fatalf("kind = %d, want DefNamespaceVar", d.Kind)
	}
	if src[d.NameStart:d.NameEnd] != "count" {
		t.Fatalf("name slice = %q", src[d.NameStart:d.NameEnd])
	}
}

func TestFileDefsNamespaceTopSet(t *testing.T) {
	src := "namespace eval ::app {\n  set total 5\n}"
	got := FileDefs(src)
	d := findDef(got, "::app::total")
	if d == nil {
		t.Fatalf("did not find ::app::total in %#v", got)
	}
	if d.Kind != DefNamespaceVar {
		t.Fatalf("kind = %d, want DefNamespaceVar", d.Kind)
	}
}

func TestFileDefsGlobalTopSet(t *testing.T) {
	// A bare `set` at global top level defines a global (::) variable.
	got := FileDefs("set g 1")
	d := findDef(got, "::g")
	if d == nil {
		t.Fatalf("did not find ::g in %#v", got)
	}
	if d.Kind != DefNamespaceVar {
		t.Fatalf("kind = %d, want DefNamespaceVar", d.Kind)
	}
}

func TestFileDefsProcParamsAndLocals(t *testing.T) {
	src := "proc add {a b} {\n  set sum 0\n  global cfg\n}"
	got := FileDefs(src)
	// params a, b are locals
	for _, n := range []string{"a", "b", "sum"} {
		d := findDef(got, n)
		if d == nil || d.Kind != DefLocal {
			t.Fatalf("expected local %q, got %#v", n, got)
		}
	}
	// global cfg is a link to ::cfg
	g := findDef(got, "cfg")
	if g == nil || g.Kind != DefGlobalLink {
		t.Fatalf("expected DefGlobalLink cfg, got %#v", got)
	}
}

func TestFileDefsUpvarAlias(t *testing.T) {
	src := "proc bump {varname} {\n  upvar 1 $varname c\n}"
	got := FileDefs(src)
	// `c` is a local alias introduced by upvar
	d := findDef(got, "c")
	if d == nil || d.Kind != DefLocal {
		t.Fatalf("expected local alias c, got %#v", got)
	}
}
