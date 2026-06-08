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

func TestDefinitionCommandPrecedenceShadow(t *testing.T) {
	ix := index.New()
	ix.IndexFile("app.tcl", "namespace eval ::app {\n  proc greet {} {}\n}") // ::app::greet
	ix.IndexFile("global.tcl", "proc greet {} {}")                          // ::greet
	r := New(ix)

	mainSrc := "namespace eval ::app {\n  greet\n}"
	off := strings.Index(mainSrc, "\n  greet") + 3
	locs := r.Definition("main.tcl", mainSrc, off)
	if len(locs) != 1 || locs[0].Name != "::app::greet" {
		t.Fatalf("expected ::app::greet to shadow ::greet, got %#v", locs)
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

func TestReferencesCommandAcrossFiles(t *testing.T) {
	ix := index.New()
	ix.IndexFile("lib.tcl", "proc greet {} {}")
	ix.IndexFile("a.tcl", "greet")
	ix.IndexFile("b.tcl", "greet\ngreet")
	r := New(ix)

	// Cursor on the call in a.tcl. The proc-name token in lib.tcl is a
	// definition, not a reference, so it is not counted.
	locs := r.References("a.tcl", "greet", 0)
	if len(locs) != 3 {
		t.Fatalf("expected 3 reference uses, got %#v", locs)
	}
}

func TestReferencesFromDefinition(t *testing.T) {
	ix := index.New()
	libSrc := "proc greet {} {}"
	ix.IndexFile("lib.tcl", libSrc)
	ix.IndexFile("a.tcl", "greet")
	r := New(ix)

	// Cursor on `greet` in the proc definition name (offset 5).
	locs := r.References("lib.tcl", libSrc, 5)
	if len(locs) != 1 || locs[0].File != "a.tcl" {
		t.Fatalf("expected 1 ref in a.tcl, got %#v", locs)
	}
}

func TestReferencesUnknownIsEmpty(t *testing.T) {
	r := New(index.New())
	if locs := r.References("a.tcl", "set x 1", 100); locs != nil {
		t.Fatalf("no symbol at offset should be nil, got %#v", locs)
	}
}

func TestReferencesRespectsPrecedence(t *testing.T) {
	ix := index.New()
	ix.IndexFile("g.tcl", "proc greet {} {}")                               // ::greet
	ix.IndexFile("app.tcl", "namespace eval ::app {\n  proc greet {} {}\n}") // ::app::greet
	ix.IndexFile("useglobal.tcl", "greet")                                  // -> ::greet
	ix.IndexFile("useapp.tcl", "namespace eval ::app {\n  greet\n}")        // -> ::app::greet
	r := New(ix)

	// Target ::greet (cursor on the global proc's name).
	locs := r.References("g.tcl", "proc greet {} {}", 5)
	for _, l := range locs {
		if l.File == "useapp.tcl" {
			t.Fatalf("a ::app::greet use must not match ::greet: %#v", locs)
		}
	}
	found := false
	for _, l := range locs {
		if l.File == "useglobal.tcl" {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected the global use in useglobal.tcl: %#v", locs)
	}
}

func TestReferencesNamespaceVariable(t *testing.T) {
	ix := index.New()
	libSrc := "namespace eval ::app {\n  variable count 0\n}"
	ix.IndexFile("lib.tcl", libSrc)
	ix.IndexFile("use.tcl", "namespace eval ::app {\n  puts $count\n}")
	r := New(ix)

	// Cursor on `count` in the variable declaration.
	off := strings.Index(libSrc, "count")
	locs := r.References("lib.tcl", libSrc, off)
	found := false
	for _, l := range locs {
		if l.File == "use.tcl" {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected the $count use in use.tcl: %#v", locs)
	}
}

func TestReferencesProcLocalDeferred(t *testing.T) {
	r := New(index.New())
	src := "proc f {x} { puts $x }"
	off := strings.Index(src, "$x") + 1
	if locs := r.References("a.tcl", src, off); locs != nil {
		t.Fatalf("proc-local references are deferred, got %#v", locs)
	}
}

func TestReferencesUsesLiveSourceForCurrentFile(t *testing.T) {
	ix := index.New()
	ix.IndexFile("lib.tcl", "proc greet {} {}")
	ix.IndexFile("a.tcl", "") // indexed as empty (stale)
	r := New(ix)

	// Unsaved edit to a.tcl adds two calls; References must use the live src,
	// not the stale indexed copy.
	liveSrc := "greet\ngreet"
	locs := r.References("a.tcl", liveSrc, 0)
	if len(locs) != 2 {
		t.Fatalf("expected 2 refs from live src, got %#v", locs)
	}
	for _, l := range locs {
		if l.File != "a.tcl" {
			t.Fatalf("unexpected file in refs: %#v", locs)
		}
	}
}
