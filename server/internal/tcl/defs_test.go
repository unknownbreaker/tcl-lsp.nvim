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

func TestFileDefsUpvarMultiPair(t *testing.T) {
	src := "proc f {} {\n  upvar 1 $a x $b y\n}"
	got := FileDefs(src)
	for _, n := range []string{"x", "y"} {
		d := findDef(got, n)
		if d == nil || d.Kind != DefLocal {
			t.Fatalf("expected local %q from multi-pair upvar, got %#v", n, got)
		}
	}
}

func TestFileDefsGlobalAtNamespaceTopNotEmitted(t *testing.T) {
	src := "namespace eval ::app {\n  global cfg\n}"
	got := FileDefs(src)
	if d := findDef(got, "cfg"); d != nil {
		t.Fatalf("did not expect global cfg def at namespace top: %#v", got)
	}
}

func TestFileDefsParamWithDefault(t *testing.T) {
	src := "proc f {{x {a b}} y} {}"
	got := FileDefs(src)
	for _, n := range []string{"x", "y"} {
		d := findDef(got, n)
		if d == nil || d.Kind != DefLocal {
			t.Fatalf("expected local param %q, got %#v", n, got)
		}
	}
	dx := findDef(got, "x")
	if src[dx.NameStart:dx.NameEnd] != "x" {
		t.Fatalf("param x name slice = %q", src[dx.NameStart:dx.NameEnd])
	}
}

func TestFileDefsInControlFlowBodies(t *testing.T) {
	// Procs defined inside control-flow / custom-command bodies must be indexed,
	// just like procs called inside such bodies are found as references. A common
	// idiom is conditional definition: `if {![llength [info commands x]]} { proc x ... }`.
	src := "if {1} { proc cond {} {} }\n" +
		"catch { proc caught {} {} }\n" +
		"foreach v {a} { proc looped {} {} }\n" +
		"namespace eval ::app {\n  if {1} { proc nested {} {} }\n}"
	got := FileDefs(src)

	for _, want := range []string{"::cond", "::caught", "::looped", "::app::nested"} {
		if d := findDef(got, want); d == nil || d.Kind != DefProc {
			t.Fatalf("missing proc def %s (proc inside a block); got %#v", want, got)
		}
	}
}

func TestFileDefsCombined(t *testing.T) {
	src := "namespace eval ::math {\n  variable e 2.7\n  proc square {x} {\n    set r [expr {$x * $x}]\n  }\n}"
	got := FileDefs(src)

	if d := findDef(got, "::math::e"); d == nil || d.Kind != DefNamespaceVar {
		t.Fatalf("missing ::math::e namespace var: %#v", got)
	}
	if d := findDef(got, "::math::square"); d == nil || d.Kind != DefProc {
		t.Fatalf("missing ::math::square proc: %#v", got)
	}
	// param x and local r are locals
	if d := findDef(got, "x"); d == nil || d.Kind != DefLocal {
		t.Fatalf("missing local x: %#v", got)
	}
	if d := findDef(got, "r"); d == nil || d.Kind != DefLocal {
		t.Fatalf("missing local r: %#v", got)
	}
	// name ranges slice back to the source
	sq := findDef(got, "::math::square")
	if src[sq.NameStart:sq.NameEnd] != "square" {
		t.Fatalf("square name slice = %q", src[sq.NameStart:sq.NameEnd])
	}
}
