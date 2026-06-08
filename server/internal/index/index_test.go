package index

import (
	"testing"

	"github.com/unknownbreaker/tcl-lsp/internal/tcl"
)

func TestIndexLookupProcAndVar(t *testing.T) {
	ix := New()
	ix.IndexFile("a.tcl", "namespace eval ::app {\n  variable count 0\n  proc run {} {}\n}")

	run := ix.Lookup("::app::run")
	if len(run) != 1 || run[0].Kind != tcl.DefProc || run[0].File != "a.tcl" {
		t.Fatalf("::app::run lookup = %#v", run)
	}
	count := ix.Lookup("::app::count")
	if len(count) != 1 || count[0].Kind != tcl.DefNamespaceVar {
		t.Fatalf("::app::count lookup = %#v", count)
	}
}

func TestIndexSkipsLocals(t *testing.T) {
	ix := New()
	ix.IndexFile("a.tcl", "proc f {a} { set b 1 }")
	if locs := ix.Lookup("a"); len(locs) != 0 {
		t.Fatalf("param local should not be indexed: %#v", locs)
	}
	if locs := ix.Lookup("b"); len(locs) != 0 {
		t.Fatalf("set local should not be indexed: %#v", locs)
	}
	if locs := ix.Lookup("::f"); len(locs) != 1 {
		t.Fatalf("::f proc should be indexed: %#v", locs)
	}
}

func TestIndexLookupMissing(t *testing.T) {
	ix := New()
	if locs := ix.Lookup("::nope"); locs != nil {
		t.Fatalf("missing lookup should be nil, got %#v", locs)
	}
}
