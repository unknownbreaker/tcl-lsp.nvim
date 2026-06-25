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

func TestFileDefsDecoratedProc(t *testing.T) {
	// A proc-defining macro: `WRAPPER... proc NAME ARGS BODY`. The command head is
	// the macro, not `proc`, so the proc must be recognized from the trailing
	// `proc NAME ARGS BODY` form (one or more decorator words before `proc`).
	defines := []struct{ src, name string }{
		{"CACHE_PROC proc stuff {a b} { return 1 }", "::stuff"},
		{"MEMOIZE 60 proc cached {x} {}", "::cached"},
		{"LOG CACHE_PROC proc layered {} {}", "::layered"},
		{"CACHE_PROC proc ::ns::qualified {} {}", "::ns::qualified"},
		{"namespace eval ::app {\n  CACHE_PROC proc inside {} {}\n}", "::app::inside"},
		// Body need not be the last word: a macro may take trailing flags/values
		// after `proc NAME ARGS BODY`.
		{"TRACE_PROC proc traced {x} { return $x } -log debug", "::traced"},
		{"MEMOIZE proc cached {} {} -ttl 60", "::cached"},
		{"DECORATE proc inside_block {} {} -flag", "::inside_block"},
	}
	for _, c := range defines {
		if d := findDef(FileDefs(c.src), c.name); d == nil || d.Kind != DefProc {
			t.Errorf("src %q: missing proc def %s; got %#v", c.src, c.name, FileDefs(c.src))
		}
	}
	// A decorated proc's parameters are still locals -- including when the macro
	// takes trailing flags after the body (the body is no longer the last word).
	for _, src := range []string{"CACHE_PROC proc p {a b} {}", "MEMOIZE proc p {a b} {} -ttl 60"} {
		if d := findDef(FileDefs(src), "a"); d == nil || d.Kind != DefLocal {
			t.Errorf("src %q: decorated proc params should be locals; got %#v", src, FileDefs(src))
		}
	}
	// List/data commands that merely contain the word `proc` must NOT be read as
	// definitions.
	for _, src := range []string{"lappend cmds proc foo {} {}", "set x proc foo {} {}", "list proc foo {} {}"} {
		if d := findDef(FileDefs(src), "::foo"); d != nil {
			t.Errorf("src %q: should not define ::foo; got %#v", src, FileDefs(src))
		}
	}
}

func defsNamed(defs []Definition, name string) []Definition {
	var out []Definition
	for _, d := range defs {
		if d.Name == name {
			out = append(out, d)
		}
	}
	return out
}

func TestFileDefsLocalScopeThreading(t *testing.T) {
	// Two procs each declare local `x`; their scopes differ. A `set` inside an
	// if-body shares the enclosing proc's scope (no block scope in Tcl).
	src := "proc f {x} {\n  set y 1\n  if {1} { set z 2 }\n}\nproc g {x} {}"
	defs := FileDefs(src)

	xs := defsNamed(defs, "x")
	if len(xs) != 2 {
		t.Fatalf("want 2 defs named x, got %d: %#v", len(xs), defs)
	}
	if xs[0].Scope == 0 || xs[0].Scope == xs[1].Scope {
		t.Fatalf("param x scopes wrong (want distinct nonzero): %#v", xs)
	}
	fScope := xs[0].Scope
	for _, n := range []string{"y", "z"} {
		ds := defsNamed(defs, n)
		if len(ds) != 1 || ds[0].Scope != fScope {
			t.Fatalf("local %q = %#v, want scope %d", n, ds, fScope)
		}
	}
}

func TestFileDefsLoopAndDestructuringLocals(t *testing.T) {
	src := "proc f {} {\n" +
		"  foreach it $items { puts $it }\n" +
		"  foreach {a b} $pairs {}\n" +
		"  lassign $row x y\n" +
		"  dict for {k v} $d {}\n" +
		"  variable count\n" +
		"}"
	defs := FileDefs(src)
	procScope := defsNamed(defs, "it")[0].Scope
	if procScope == 0 {
		t.Fatalf("expected nonzero proc scope")
	}
	for _, n := range []string{"it", "a", "b", "x", "y", "k", "v"} {
		ds := defsNamed(defs, n)
		if len(ds) != 1 || ds[0].Kind != DefLocal || ds[0].Scope != procScope {
			t.Fatalf("local %q = %#v, want one DefLocal in scope %d", n, ds, procScope)
		}
		if src[ds[0].NameStart:ds[0].NameEnd] != n {
			t.Fatalf("local %q offsets slice %q", n, src[ds[0].NameStart:ds[0].NameEnd])
		}
	}
	// `variable count` inside a proc yields a DefLocal alias in addition to the
	// existing DefNamespaceVar.
	cnt := defsNamed(defs, "count")
	hasLocal := false
	for _, d := range cnt {
		if d.Kind == DefLocal && d.Scope == procScope {
			hasLocal = true
		}
	}
	if !hasLocal {
		t.Fatalf("variable-in-proc should add a DefLocal: %#v", cnt)
	}
}

func TestFileDefsIncrAppendLappendLocals(t *testing.T) {
	src := "proc f {} {\n  incr n\n  append s x\n  lappend items y\n}"
	defs := FileDefs(src)
	procScope := defsNamed(defs, "n")
	if len(procScope) != 1 {
		t.Fatalf("want 1 def n, got %#v", defs)
	}
	for _, name := range []string{"n", "s", "items"} {
		ds := defsNamed(defs, name)
		if len(ds) != 1 || ds[0].Kind != DefLocal || ds[0].Scope == 0 {
			t.Fatalf("local %q = %#v, want one DefLocal with nonzero scope", name, ds)
		}
		if src[ds[0].NameStart:ds[0].NameEnd] != name {
			t.Fatalf("local %q offsets slice %q", name, src[ds[0].NameStart:ds[0].NameEnd])
		}
	}
}

func TestFileDefsArrayElementLocals(t *testing.T) {
	src := "proc f {} {\n" +
		"  set arr(a) 0\n" +
		"  incr arr(b)\n" +
		"  append str(x) hi\n" +
		"  lappend items(k) v\n" +
		"  set dyn($i) 1\n" +
		"}"
	defs := FileDefs(src)
	for _, name := range []string{"arr", "str", "items", "dyn"} {
		ds := defsNamed(defs, name)
		if len(ds) == 0 {
			t.Fatalf("no def named %q; got %#v", name, defs)
		}
		d := ds[0]
		if d.Kind != DefLocal || d.Scope == 0 {
			t.Fatalf("%q: want DefLocal in nonzero scope, got %#v", name, d)
		}
		if src[d.NameStart:d.NameEnd] != name {
			t.Fatalf("%q: range slices %q, want the base name", name, src[d.NameStart:d.NameEnd])
		}
	}
	// The parenthesized form must NOT be emitted as a name.
	if d := findDef(defs, "arr(a)"); d != nil {
		t.Fatalf("should not emit parenthesized name arr(a): %#v", d)
	}
	// A plain scalar target is unaffected.
	if d := findDef(FileDefs("proc f {} {\n  set plain 1\n}"), "plain"); d == nil {
		t.Fatalf("scalar set should still emit a DefLocal named plain")
	}
}

func TestFileDefsArrayElementNamespaceVar(t *testing.T) {
	src := "namespace eval ::app {\n  set cfg(host) x\n}"
	defs := FileDefs(src)
	d := findDef(defs, "::app::cfg")
	if d == nil || d.Kind != DefNamespaceVar {
		t.Fatalf("want DefNamespaceVar ::app::cfg, got %#v", defs)
	}
	if src[d.NameStart:d.NameEnd] != "cfg" {
		t.Fatalf("range slices %q, want cfg", src[d.NameStart:d.NameEnd])
	}
	if findDef(defs, "::app::cfg(host)") != nil {
		t.Fatalf("should not emit ::app::cfg(host)")
	}
}

func TestFileDefsGlobalUpvarOrigin(t *testing.T) {
	cases := []struct{ src, name, wantOrigin string }{
		{"proc f {} {\n  global config\n}", "config", "::config"},
		{"proc f {} {\n  global ::app::x\n}", "::app::x", "::app::x"},
		{"proc f {} {\n  upvar #0 sessions s\n}", "s", "::sessions"},
		{"proc f {} {\n  upvar 0 ::app::cfg c\n}", "c", "::app::cfg"},
		{"proc f {} {\n  upvar 1 caller v\n}", "v", ""},
		{"proc f {} {\n  set local 1\n}", "local", ""},
	}
	for _, tc := range cases {
		d := findDef(FileDefs(tc.src), tc.name)
		if d == nil {
			t.Fatalf("src %q: no def named %q in %#v", tc.src, tc.name, FileDefs(tc.src))
		}
		if d.Origin != tc.wantOrigin {
			t.Fatalf("src %q: Origin = %q, want %q", tc.src, d.Origin, tc.wantOrigin)
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

func TestFileDefsItclClass(t *testing.T) {
	src := "itcl::class ::STDisplay {\n  method field {} {}\n}"
	var got *Definition
	for _, d := range FileDefs(src) {
		if d.Kind == DefClass {
			dd := d
			got = &dd
		}
	}
	if got == nil || got.Name != "::STDisplay" {
		t.Fatalf("want DefClass ::STDisplay, got %#v", FileDefs(src))
	}
	if src[got.NameStart:got.NameEnd] != "::STDisplay" {
		t.Fatalf("name range slices %q, want ::STDisplay", src[got.NameStart:got.NameEnd])
	}
}

func TestFileDefsItclClassQualifiedHead(t *testing.T) {
	// `::itcl::class` (leading ::) must also be recognized.
	defs := FileDefs("::itcl::class ::Foo {}")
	found := false
	for _, d := range defs {
		if d.Kind == DefClass && d.Name == "::Foo" {
			found = true
		}
	}
	if !found {
		t.Fatalf("::itcl::class not recognized: %#v", defs)
	}
}
