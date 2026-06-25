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
