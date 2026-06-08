package index

import (
	"reflect"
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

func TestIndexMultipleFilesSameName(t *testing.T) {
	ix := New()
	ix.IndexFile("a.tcl", "proc dup {} {}")
	ix.IndexFile("b.tcl", "proc dup {} {}")
	if locs := ix.Lookup("::dup"); len(locs) != 2 {
		t.Fatalf("expected 2 def sites for ::dup, got %#v", locs)
	}
}

func TestIndexReindexReplaces(t *testing.T) {
	ix := New()
	ix.IndexFile("a.tcl", "proc old {} {}")
	ix.IndexFile("a.tcl", "proc new {} {}") // re-index the same path
	if locs := ix.Lookup("::old"); len(locs) != 0 {
		t.Fatalf("old def should be gone after re-index: %#v", locs)
	}
	if locs := ix.Lookup("::new"); len(locs) != 1 {
		t.Fatalf("new def should be present: %#v", locs)
	}
}

func TestIndexRemoveFile(t *testing.T) {
	ix := New()
	ix.IndexFile("a.tcl", "proc dup {} {}")
	ix.IndexFile("b.tcl", "proc dup {} {}")
	ix.RemoveFile("a.tcl")
	locs := ix.Lookup("::dup")
	if len(locs) != 1 || locs[0].File != "b.tcl" {
		t.Fatalf("after removing a.tcl, expected only b.tcl: %#v", locs)
	}
	// fully removing the last definer deletes the key
	ix.RemoveFile("b.tcl")
	if locs := ix.Lookup("::dup"); locs != nil {
		t.Fatalf("expected nil after all definers removed, got %#v", locs)
	}
}

func TestIndexFilesAndSource(t *testing.T) {
	ix := New()
	ix.IndexFile("b.tcl", "proc b {} {}")
	ix.IndexFile("a.tcl", "proc a {} {}")

	if files := ix.Files(); !reflect.DeepEqual(files, []string{"a.tcl", "b.tcl"}) {
		t.Fatalf("Files() = %#v, want sorted [a.tcl b.tcl]", files)
	}
	if got := ix.Source("a.tcl"); got != "proc a {} {}" {
		t.Fatalf("Source(a.tcl) = %q", got)
	}
	ix.RemoveFile("a.tcl")
	if got := ix.Source("a.tcl"); got != "" {
		t.Fatalf("Source after remove = %q, want empty", got)
	}
	if files := ix.Files(); !reflect.DeepEqual(files, []string{"b.tcl"}) {
		t.Fatalf("Files() after remove = %#v", files)
	}
}
