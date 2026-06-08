package resolve

import (
	"strings"
	"testing"

	"github.com/unknownbreaker/tcl-lsp/internal/index"
)

func TestDefinitionCommandSameNamespace(t *testing.T) {
	ix := index.New()
	ix.IndexFile("lib.tcl", "namespace eval ::app {\n  proc run {} {}\n}")
	r := New(ix)

	mainSrc := "namespace eval ::app {\n  run\n}"
	off := strings.Index(mainSrc, "\n  run") + 3 // on the `run` call
	locs := r.Definition("main.tcl", mainSrc, off)
	if len(locs) != 1 || locs[0].Name != "::app::run" || locs[0].File != "lib.tcl" {
		t.Fatalf("definition = %#v", locs)
	}
}

func TestDefinitionCommandQualified(t *testing.T) {
	ix := index.New()
	ix.IndexFile("lib.tcl", "namespace eval ::app {\n  proc run {} {}\n}")
	r := New(ix)

	locs := r.Definition("main.tcl", "::app::run", 3)
	if len(locs) != 1 || locs[0].Name != "::app::run" {
		t.Fatalf("definition = %#v", locs)
	}
}

func TestDefinitionCommandGlobalFallback(t *testing.T) {
	ix := index.New()
	ix.IndexFile("lib.tcl", "proc greet {} {}")
	r := New(ix)

	// A bare `greet` call from inside ::app falls back to global ::greet.
	mainSrc := "namespace eval ::app {\n  greet\n}"
	off := strings.Index(mainSrc, "\n  greet") + 3
	locs := r.Definition("main.tcl", mainSrc, off)
	if len(locs) != 1 || locs[0].Name != "::greet" {
		t.Fatalf("definition = %#v", locs)
	}
}

func TestDefinitionUnknownCommand(t *testing.T) {
	r := New(index.New())
	if locs := r.Definition("a.tcl", "doesnotexist", 0); len(locs) != 0 {
		t.Fatalf("unknown command should resolve to nothing, got %#v", locs)
	}
}

func TestDefinitionNoSymbolAtOffset(t *testing.T) {
	r := New(index.New())
	if locs := r.Definition("a.tcl", "set x 1", 100); locs != nil {
		t.Fatalf("out-of-range offset should be nil, got %#v", locs)
	}
}

func TestDefinitionNamespaceVariable(t *testing.T) {
	ix := index.New()
	ix.IndexFile("lib.tcl", "namespace eval ::app {\n  variable count 0\n}")
	r := New(ix)

	mainSrc := "namespace eval ::app {\n  puts $count\n}"
	off := strings.Index(mainSrc, "$count") + 1 // on `count`
	locs := r.Definition("main.tcl", mainSrc, off)
	if len(locs) != 1 || locs[0].Name != "::app::count" {
		t.Fatalf("definition = %#v", locs)
	}
}

func TestDefinitionQualifiedVariable(t *testing.T) {
	ix := index.New()
	ix.IndexFile("lib.tcl", "namespace eval ::app {\n  variable count 0\n}")
	r := New(ix)

	mainSrc := "puts $::app::count"
	off := strings.Index(mainSrc, "$::app::count") + 5
	locs := r.Definition("main.tcl", mainSrc, off)
	if len(locs) != 1 || locs[0].Name != "::app::count" {
		t.Fatalf("definition = %#v", locs)
	}
}

func TestDefinitionProcLocalDeferred(t *testing.T) {
	// A bare variable inside a proc body is local-only; resolving it is deferred
	// to the frame-local resolution plan. For now it returns nothing.
	r := New(index.New())
	src := "proc f {x} { puts $x }"
	off := strings.Index(src, "$x") + 1
	if locs := r.Definition("a.tcl", src, off); locs != nil {
		t.Fatalf("bare proc-local should be unresolved (deferred), got %#v", locs)
	}
}

func TestDefinitionMultipleSites(t *testing.T) {
	ix := index.New()
	ix.IndexFile("a.tcl", "proc dup {} {}")
	ix.IndexFile("b.tcl", "proc dup {} {}")
	r := New(ix)

	locs := r.Definition("main.tcl", "dup", 0)
	if len(locs) != 2 {
		t.Fatalf("expected 2 def sites for ::dup, got %#v", locs)
	}
	files := map[string]bool{}
	for _, l := range locs {
		files[l.File] = true
	}
	if !files["a.tcl"] || !files["b.tcl"] {
		t.Fatalf("expected both a.tcl and b.tcl: %#v", locs)
	}
}

func TestDefinitionNestedCommandSubstitution(t *testing.T) {
	// goto-definition on a command used inside a [command substitution].
	ix := index.New()
	ix.IndexFile("lib.tcl", "proc helper {} {}")
	r := New(ix)

	mainSrc := "set x [helper]"
	off := strings.Index(mainSrc, "helper")
	locs := r.Definition("main.tcl", mainSrc, off)
	if len(locs) != 1 || locs[0].Name != "::helper" {
		t.Fatalf("definition = %#v", locs)
	}
}
