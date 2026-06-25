package tcl

import (
	"strings"
	"testing"
)

// indexLast returns the byte offset of the last occurrence of sub in s, or -1.
func indexLast(s, sub string) int {
	return strings.LastIndex(s, sub)
}

// reachAtMarker returns the reaching-def name ranges for the variable use whose
// text starts at marker `mark` in src. +1 lands inside `$x` on the name.
func reachAtMarker(t *testing.T, src, mark string) []Definition {
	t.Helper()
	off := indexOf(t, src, mark) + 1 // +1 to land inside `$x` on the name
	defs, ok := ReachingAt(src, off)
	if !ok {
		t.Fatalf("ReachingAt(%q) ok=false", mark)
	}
	return defs
}

func indexOf(t *testing.T, src, sub string) int {
	t.Helper()
	i := indexLast(src, sub)
	if i < 0 {
		t.Fatalf("substring %q not found", sub)
	}
	return i
}

func TestReachingStraightLineLatestAssignment(t *testing.T) {
	src := "proc f {} {\n  set x 1\n  set x 2\n  puts $x\n}"
	defs := reachAtMarker(t, src, "$x")
	if len(defs) != 1 {
		t.Fatalf("want 1 reaching def, got %d: %#v", len(defs), defs)
	}
	// It must be the SECOND `set x`, not the first.
	wantStart := indexLast(src, "set x 2") + len("set ")
	if defs[0].NameStart != wantStart {
		t.Fatalf("reaching def at %d, want the `set x 2` binding at %d", defs[0].NameStart, wantStart)
	}
}

func TestReachingParamReaches(t *testing.T) {
	src := "proc f {a} {\n  puts $a\n}"
	defs := reachAtMarker(t, src, "$a")
	if len(defs) != 1 || defs[0].Name != "a" {
		t.Fatalf("param should reach: %#v", defs)
	}
}

func TestReachingIfElseJoin(t *testing.T) {
	src := "proc f {} {\n  set x 1\n  if {$c} {\n    set x 2\n  } else {\n    set x 3\n  }\n  puts $x\n}"
	defs := reachAtMarker(t, src, "$x")
	if len(defs) != 2 { // both branches reassign; set x 1 is dead
		t.Fatalf("want 2 reaching defs (x2, x3), got %d: %#v", len(defs), defs)
	}
}

func TestReachingIfNoElseKeepsPrior(t *testing.T) {
	src := "proc f {} {\n  set x 1\n  if {$c} {\n    set x 2\n  }\n  puts $x\n}"
	defs := reachAtMarker(t, src, "$x")
	if len(defs) != 2 { // fall-through keeps x1; if-branch adds x2
		t.Fatalf("want 2 (x1 fall-through + x2), got %d: %#v", len(defs), defs)
	}
}

func TestReachingLoopCarried(t *testing.T) {
	src := "proc f {} {\n  set x 0\n  while {$c} {\n    set y $x\n    set x 9\n  }\n  puts $x\n}"
	defs := reachAtMarker(t, src, "$x") // the `puts $x` after the loop
	if len(defs) != 2 {                 // x0 (zero iterations) or x9 (ran)
		t.Fatalf("want 2 reaching defs (x0, x9), got %d: %#v", len(defs), defs)
	}
}

func TestReachingForeachVar(t *testing.T) {
	src := "proc f {items} {\n  foreach it $items {\n    puts $it\n  }\n}"
	defs := reachAtMarker(t, src, "$it")
	if len(defs) != 1 || defs[0].Name != "it" {
		t.Fatalf("foreach var should reach its use: %#v", defs)
	}
}

func TestReachingEarlyReturnBranch(t *testing.T) {
	src := "proc f {} {\n  set x 1\n  if {$c} {\n    return\n  } else {\n    set x 2\n  }\n  puts $x\n}"
	defs := reachAtMarker(t, src, "$x") // return branch dead; else assigns x2; has else → x2 only
	if len(defs) != 1 {
		t.Fatalf("want 1 reaching def (x2), got %d: %#v", len(defs), defs)
	}
}

func TestReachingBreakExit(t *testing.T) {
	src := "proc f {} {\n  set x 0\n  while {$c} {\n    set x 1\n    if {$d} { break }\n    set x 2\n  }\n  puts $x\n}"
	defs := reachAtMarker(t, src, "$x") // x0 (0 iters), x1 (broke), x2 (end of iter)
	if len(defs) != 3 {
		t.Fatalf("want 3 reaching defs (x0,x1,x2), got %d: %#v", len(defs), defs)
	}
}

func TestReachingCatchConservative(t *testing.T) {
	src := "proc f {} {\n  set x 1\n  catch {\n    set x 2\n  }\n  puts $x\n}"
	defs := reachAtMarker(t, src, "$x") // x1 (error before set) OR x2
	if len(defs) != 2 {
		t.Fatalf("want 2 reaching defs (x1,x2), got %d: %#v", len(defs), defs)
	}
}

func TestReachingSwitchArms(t *testing.T) {
	src := "proc f {} {\n  set x 0\n  switch $k {\n    a { set x 1 }\n    b { set x 2 }\n  }\n  puts $x\n}"
	defs := reachAtMarker(t, src, "$x") // x0 + x1 + x2 (conservative join)
	if len(defs) != 3 {
		t.Fatalf("want 3 reaching defs (x0,x1,x2), got %d: %#v", len(defs), defs)
	}
}

func TestReachingSizeCapFallsBack(t *testing.T) {
	var b strings.Builder
	b.WriteString("proc f {} {\n")
	for i := 0; i < 40000; i++ { // ~ > 200 KB of body
		b.WriteString("  set x 1\n")
	}
	b.WriteString("  puts $x\n}")
	src := b.String()
	off := indexLast(src, "$x") + 1
	if _, ok := ReachingAt(src, off); ok {
		t.Fatalf("expected ok=false (fallback) for oversized proc body")
	}
}

func TestReachingRMWTargetIsUse(t *testing.T) {
	src := "proc f {} {\n  set x 1\n  incr x\n}"
	off := strings.Index(src, "incr x") + len("incr ") // the `x` of `incr x`
	defs, ok := ReachingAt(src, off)
	if !ok || len(defs) != 1 {
		t.Fatalf("rmw target should be a use: ok=%v defs=%#v", ok, defs)
	}
	if defs[0].NameStart != strings.Index(src, "set x 1")+len("set ") {
		t.Fatalf("want the prior `set x 1`, got %#v", defs)
	}
}
