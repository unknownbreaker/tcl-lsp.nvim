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

func TestDefinitionProcLocalDeclaration(t *testing.T) {
	r := New(index.New())
	// Two `set total` bindings: under reaching-defs semantics, goto-def from
	// `return $total` lands on the LAST `set total` — the one that actually
	// reaches the use. The first `set total 0` is killed by `set total 1`
	// in a straight-line sequence.
	src := "proc f {x} {\n  set total 0\n  set total 1\n  return $total\n}"
	off := strings.Index(src, "return $total") + len("return $")
	locs := r.Definition("a.tcl", src, off)
	if len(locs) != 1 {
		t.Fatalf("want 1 def, got %#v", locs)
	}
	if got := src[locs[0].NameStart:locs[0].NameEnd]; got != "total" {
		t.Fatalf("slice %q", got)
	}
	// strings.LastIndex finds the LAST `set total` — the one that reaches the use.
	if locs[0].NameStart != strings.LastIndex(src, "set total")+len("set ") {
		t.Fatalf("expected last `set total` (reaching def), got offset %d", locs[0].NameStart)
	}
}

func TestDefinitionProcLocalParamFallback(t *testing.T) {
	r := New(index.New())
	src := "proc f {x} {\n  return $x\n}"
	off := strings.Index(src, "$x") + 1
	locs := r.Definition("a.tcl", src, off)
	if len(locs) != 1 || src[locs[0].NameStart:locs[0].NameEnd] != "x" {
		t.Fatalf("param fallback failed: %#v", locs)
	}
	if locs[0].NameStart != strings.Index(src, "{x}")+1 {
		t.Fatalf("expected the param x, got %d", locs[0].NameStart)
	}
}

func TestDefinitionProcLocalScopeIsolation(t *testing.T) {
	r := New(index.New())
	src := "proc f {} {\n  set v 1\n  puts $v\n}\nproc g {} {\n  set v 2\n}"
	off := strings.Index(src, "puts $v") + len("puts $")
	locs := r.Definition("a.tcl", src, off)
	if len(locs) != 1 {
		t.Fatalf("want 1, got %#v", locs)
	}
	// must resolve to f's `set v`, not g's.
	if locs[0].NameStart != strings.Index(src, "set v 1")+len("set ") {
		t.Fatalf("crossed proc scope: %#v", locs)
	}
}

func TestDefinitionProcLocalUndefinedIsNil(t *testing.T) {
	r := New(index.New())
	src := "proc f {} {\n  puts $missing\n}"
	off := strings.Index(src, "$missing") + 1
	if locs := r.Definition("a.tcl", src, off); locs != nil {
		t.Fatalf("undefined local should be nil, got %#v", locs)
	}
}

func TestDefinitionProcLocalJumpsToReachingDefNotEarliestBinding(t *testing.T) {
	r := New(index.New())
	// Declared once with `set`, later mutated with a build-up command (lappend).
	// Under reaching-defs semantics:
	//   - From the use ($thing in return): lappend kills the prior set, so goto-def
	//     lands on the `lappend thing` site (the mutation that reaches the use).
	//   - From the mutation (lappend thing): the reaching set at that RMW binding
	//     is the prior `set thing`, so goto-def still lands on the declaration.
	//   - From the declaration itself: goto-def is idempotent (stays put).
	src := "proc f {} {\n  set thing [list]\n  lappend thing $blah\n  return $thing\n}"
	decl := strings.Index(src, "set thing") + len("set ")
	lappendThing := strings.Index(src, "lappend thing") + len("lappend ")

	useOff := strings.Index(src, "return $thing") + len("return $")
	if locs := r.Definition("a.tcl", src, useOff); len(locs) != 1 || locs[0].NameStart != lappendThing {
		t.Fatalf("from use: expected reaching def lappend thing at %d, got %#v", lappendThing, locs)
	}

	mutOff := strings.Index(src, "lappend thing") + len("lappend ")
	if locs := r.Definition("a.tcl", src, mutOff); len(locs) != 1 || locs[0].NameStart != decl {
		t.Fatalf("from mutation: expected declaration at %d, got %#v", decl, locs)
	}

	// From the declaration itself, goto-def is idempotent (stays put).
	if locs := r.Definition("a.tcl", src, decl); len(locs) != 1 || locs[0].NameStart != decl {
		t.Fatalf("from declaration: expected idempotent, got %#v", locs)
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
	ix.IndexFile("global.tcl", "proc greet {} {}")                           // ::greet
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
	ix.IndexFile("g.tcl", "proc greet {} {}")                                // ::greet
	ix.IndexFile("app.tcl", "namespace eval ::app {\n  proc greet {} {}\n}") // ::app::greet
	ix.IndexFile("useglobal.tcl", "greet")                                   // -> ::greet
	ix.IndexFile("useapp.tcl", "namespace eval ::app {\n  greet\n}")         // -> ::app::greet
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

func TestReferencesProcLocalAllOccurrences(t *testing.T) {
	r := New(index.New())
	src := "proc f {x} {\n  set x 1\n  incr x\n  puts $x\n}"
	off := strings.Index(src, "$x") + 1
	locs := r.References("a.tcl", src, off)
	// param x, set x, incr x  => 3 binding sites (slice to "x")
	// puts $x                  => 1 use site (slice to "$x")
	if len(locs) != 4 {
		t.Fatalf("want 4 occurrences, got %d: %#v", len(locs), locs)
	}
	var nBindings, nUses int
	for _, l := range locs {
		if l.File != "a.tcl" {
			t.Fatalf("local reference leaked to wrong file: %#v", l)
		}
		switch src[l.NameStart:l.NameEnd] {
		case "x":
			nBindings++
		case "$x":
			nUses++
		default:
			t.Fatalf("unexpected slice %q in occurrence %#v", src[l.NameStart:l.NameEnd], l)
		}
	}
	if nBindings != 3 || nUses != 1 {
		t.Fatalf("want 3 binding sites + 1 use, got %d bindings + %d uses", nBindings, nUses)
	}
}

func TestReferencesProcLocalForeachVar(t *testing.T) {
	r := New(index.New())
	src := "proc f {} {\n  foreach it $items {\n    puts $it\n  }\n}"
	// Use LastIndex to land on the $it in `puts $it`, not the $it prefix of $items.
	off := strings.LastIndex(src, "$it") + 1
	locs := r.References("a.tcl", src, off)
	// foreach binding `it` + `$it` use.
	if len(locs) != 2 {
		t.Fatalf("want 2, got %#v", locs)
	}
}

func TestReferencesProcLocalCurrentFileOnly(t *testing.T) {
	ix := index.New()
	// A second file with an identically-named proc-local must not be matched.
	ix.IndexFile("other.tcl", "proc g {} {\n  set v 9\n  puts $v\n}")
	r := New(ix)
	src := "proc f {} {\n  set v 1\n  puts $v\n}"
	off := strings.Index(src, "$v") + 1
	locs := r.References("a.tcl", src, off)
	for _, l := range locs {
		if l.File != "a.tcl" {
			t.Fatalf("local references leaked to %s: %#v", l.File, locs)
		}
	}
	if len(locs) != 2 {
		t.Fatalf("want 2 (set v, $v) in a.tcl, got %#v", locs)
	}
}

func TestReferencesProcLocalGlobalLink(t *testing.T) {
	r := New(index.New())
	src := "proc f {} {\n  global config\n  puts $config\n}"
	off := strings.Index(src, "$config") + 1
	locs := r.References("a.tcl", src, off)
	// `global config` link site + `$config` use.
	if len(locs) != 2 {
		t.Fatalf("want 2, got %#v", locs)
	}
}

func TestReferencesSameFileAsDefinition(t *testing.T) {
	ix := index.New()
	src := "proc greet {} {}\ngreet"
	ix.IndexFile("lib.tcl", src)
	r := New(ix)

	// Cursor on the proc name; the call later in the SAME file is a reference.
	locs := r.References("lib.tcl", src, 5)
	if len(locs) != 1 || locs[0].File != "lib.tcl" {
		t.Fatalf("expected 1 self-file ref in lib.tcl, got %#v", locs)
	}
}

func TestReferencesInsideCommandSubstitution(t *testing.T) {
	ix := index.New()
	src := "proc helper {} {}\nset x [helper]"
	ix.IndexFile("lib.tcl", src)
	r := New(ix)

	// Cursor on the helper definition name; the [helper] call is a reference.
	locs := r.References("lib.tcl", src, 5)
	if len(locs) != 1 {
		t.Fatalf("expected 1 ref (the [helper] call), got %#v", locs)
	}
}

func TestReferencesInsideConditionSubstitution(t *testing.T) {
	ix := index.New()
	// helper is called only inside an if-condition's [substitution] -- an expr
	// position Tcl evaluates, so the call is a real reference.
	src := "proc helper {} {}\nif {[helper]} { puts hi }"
	ix.IndexFile("lib.tcl", src)
	r := New(ix)

	// find-references from the definition includes the in-condition call site.
	locs := r.References("lib.tcl", src, 5)
	if len(locs) != 1 {
		t.Fatalf("expected 1 ref (the [helper] call in the if-condition), got %#v", locs)
	}

	// goto-definition from the in-condition call site resolves back to the proc.
	callOff := strings.Index(src, "[helper]") + 1
	defs := r.Definition("lib.tcl", src, callOff)
	if len(defs) != 1 || defs[0].Name != "::helper" {
		t.Fatalf("goto-def from in-condition call = %#v", defs)
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

func TestDefinitionViaNamespacePath(t *testing.T) {
	ix := index.New()
	ix.IndexFile("lib.tcl", "namespace eval ::lib {\n  proc helper {} {}\n}")
	src := "namespace eval ::user {\n  namespace path ::lib\n  helper\n}"
	ix.IndexFile("user.tcl", src)
	r := New(ix)

	off := strings.Index(src, "\n  helper") + 3 // the `helper` call
	locs := r.Definition("user.tcl", src, off)
	if len(locs) != 1 || locs[0].Name != "::lib::helper" {
		t.Fatalf("via namespace path = %#v", locs)
	}
}

func TestDefinitionViaNamespaceImport(t *testing.T) {
	ix := index.New()
	ix.IndexFile("p.tcl", "namespace eval ::provider {\n  namespace export pub\n  proc pub {} {}\n}")
	src := "namespace eval ::consumer {\n  namespace import ::provider::pub\n  pub\n}"
	ix.IndexFile("c.tcl", src)
	r := New(ix)

	off := strings.Index(src, "\n  pub\n") + 3 // the bare `pub` call
	locs := r.Definition("c.tcl", src, off)
	if len(locs) != 1 || locs[0].Name != "::provider::pub" {
		t.Fatalf("via namespace import = %#v", locs)
	}
}

func TestDefinitionViaGlobImport(t *testing.T) {
	ix := index.New()
	ix.IndexFile("p.tcl", "namespace eval ::provider {\n  namespace export *\n  proc tool {} {}\n}")
	src := "namespace eval ::consumer {\n  namespace import ::provider::*\n  tool\n}"
	ix.IndexFile("c.tcl", src)
	r := New(ix)

	off := strings.Index(src, "\n  tool\n") + 3
	locs := r.Definition("c.tcl", src, off)
	if len(locs) != 1 || locs[0].Name != "::provider::tool" {
		t.Fatalf("via glob import = %#v", locs)
	}
}

func TestDefinitionCurrentNamespaceBeatsPath(t *testing.T) {
	ix := index.New()
	ix.IndexFile("lib.tcl", "namespace eval ::lib { proc helper {} {} }")
	src := "namespace eval ::user {\n  namespace path ::lib\n  proc helper {} {}\n  helper\n}"
	ix.IndexFile("user.tcl", src)
	r := New(ix)

	off := strings.LastIndex(src, "helper") // the call, after the local proc def
	locs := r.Definition("user.tcl", src, off)
	if len(locs) != 1 || locs[0].Name != "::user::helper" {
		t.Fatalf("current ns should beat path: %#v", locs)
	}
}

func TestDefinitionImportSourceMissing(t *testing.T) {
	ix := index.New()
	src := "namespace eval ::consumer {\n  namespace import ::nonexistent::pub\n  pub\n}"
	ix.IndexFile("c.tcl", src)
	r := New(ix)
	off := strings.Index(src, "\n  pub\n") + 3
	if locs := r.Definition("c.tcl", src, off); locs != nil {
		t.Fatalf("import of a non-existent source should not resolve, got %#v", locs)
	}
}

func TestReferencesGlobImportDoesNotOverMatch(t *testing.T) {
	ix := index.New()
	ix.IndexFile("p.tcl", "namespace eval ::provider {\n  proc tool {} {}\n}")
	// ::consumer glob-imports ::provider but calls `other`, which ::provider
	// does NOT define; a global ::other exists instead.
	ix.IndexFile("c.tcl", "namespace eval ::consumer {\n  namespace import ::provider::*\n  other\n}")
	gsrc := "proc other {} {}"
	ix.IndexFile("g.tcl", gsrc)
	r := New(ix)
	// References to ::other should include the call in c.tcl (it resolves to
	// ::other, not the non-existent ::provider::other).
	off := strings.Index(gsrc, "other")
	locs := r.References("g.tcl", gsrc, off)
	found := false
	for _, l := range locs {
		if l.File == "c.tcl" {
			found = true
		}
	}
	if !found {
		t.Fatalf("c.tcl `other` should resolve to ::other despite the glob import: %#v", locs)
	}
}

func TestReferencesViaNamespaceImport(t *testing.T) {
	ix := index.New()
	pSrc := "namespace eval ::provider {\n  namespace export pub\n  proc pub {} {}\n}"
	ix.IndexFile("p.tcl", pSrc)
	ix.IndexFile("c.tcl", "namespace eval ::consumer {\n  namespace import ::provider::pub\n  pub\n}")
	r := New(ix)

	// From the definition of ::provider::pub, references should include the
	// imported call in c.tcl (which resolves to ::provider::pub).
	off := strings.Index(pSrc, "proc pub") + 5 // the `pub` proc name
	locs := r.References("p.tcl", pSrc, off)
	found := false
	for _, l := range locs {
		if l.File == "c.tcl" {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected the imported call in c.tcl among references: %#v", locs)
	}
}

func TestRVTProcPageLocalDefinition(t *testing.T) {
	ix := index.New()
	src := "<? proc greet {} {} ?>\n<? greet ?>"
	ix.IndexFile("page.rvt", src)
	r := New(ix)

	off := strings.LastIndex(src, "greet") // the call
	locs := r.Definition("page.rvt", src, off)
	if len(locs) != 1 || locs[0].Name != "::request::greet" || locs[0].File != "page.rvt" {
		t.Fatalf("page-local goto-def = %#v", locs)
	}
}

func TestRVTPageLocalNoCrossPageMatch(t *testing.T) {
	ix := index.New()
	a := "<? proc render {} {} ?>\n<? render ?>"
	b := "<? proc render {} {} ?>\n<? render ?>"
	ix.IndexFile("a.rvt", a)
	ix.IndexFile("b.rvt", b)
	r := New(ix)

	// goto-def from a.rvt's call resolves only to a.rvt's definition.
	off := strings.LastIndex(a, "render")
	locs := r.Definition("a.rvt", a, off)
	if len(locs) != 1 || locs[0].File != "a.rvt" {
		t.Fatalf("expected only a.rvt def, got %#v", locs)
	}

	// find-references from a.rvt must not include b.rvt's identically-named helper.
	refs := r.References("a.rvt", a, off)
	for _, l := range refs {
		if l.File == "b.rvt" {
			t.Fatalf("page-local references leaked into b.rvt: %#v", refs)
		}
	}
}

func TestRVTPageLocalShadowsGlobal(t *testing.T) {
	ix := index.New()
	ix.IndexFile("lib.tcl", "proc greet {} {}") // ::greet
	page := "<? proc greet {} {} ?>\n<? greet ?>"
	ix.IndexFile("page.rvt", page)
	r := New(ix)

	off := strings.LastIndex(page, "greet") // the call
	locs := r.Definition("page.rvt", page, off)
	if len(locs) != 1 || locs[0].Name != "::request::greet" || locs[0].File != "page.rvt" {
		t.Fatalf("page-local should shadow global: %#v", locs)
	}
}

func TestReferencesProcLocalArray(t *testing.T) {
	r := New(index.New())
	src := "proc f {} {\n  set arr(a) 0\n  set arr(b) 1\n  return [list $arr(a) $arr(b)]\n}"
	useOff := strings.Index(src, "$arr(a)") + 1
	// goto-def from a use lands on the first element write (the declaration).
	defs := r.Definition("a.tcl", src, useOff)
	if len(defs) != 1 || defs[0].NameStart != strings.Index(src, "set arr(a)")+len("set ") {
		t.Fatalf("array goto-def = %#v", defs)
	}
	if src[defs[0].NameStart:defs[0].NameEnd] != "arr" {
		t.Fatalf("range slices %q, want arr", src[defs[0].NameStart:defs[0].NameEnd])
	}
	// find-refs gathers both element writes + both uses, current file only.
	refs := r.References("a.tcl", src, useOff)
	if len(refs) != 4 {
		t.Fatalf("want 4 occurrences (2 writes + 2 uses), got %#v", refs)
	}
	for _, l := range refs {
		if l.File != "a.tcl" {
			t.Fatalf("leaked to %s: %#v", l.File, refs)
		}
	}
}

func TestReferencesProcLocalArrayScopeIsolation(t *testing.T) {
	r := New(index.New())
	src := "proc f {} {\n  set m(x) 1\n  puts $m(x)\n}\nproc g {} {\n  set m(y) 2\n}"
	useOff := strings.Index(src, "$m(x)") + 1
	defs := r.Definition("a.tcl", src, useOff)
	if len(defs) != 1 || defs[0].NameStart != strings.Index(src, "set m(x)")+len("set ") {
		t.Fatalf("crossed scope or wrong target: %#v", defs)
	}
}

func TestDefinitionArrayNamespaceCrossFile(t *testing.T) {
	ix := index.New()
	lib := "namespace eval ::app {\n  set cfg(host) localhost\n}"
	page := "namespace eval ::app {\n  puts $cfg(host)\n}"
	ix.IndexFile("lib.tcl", lib)
	ix.IndexFile("use.tcl", page)
	r := New(ix)

	off := strings.Index(page, "$cfg(host)") + 1
	locs := r.Definition("use.tcl", page, off)
	if len(locs) != 1 || locs[0].File != "lib.tcl" || locs[0].Name != "::app::cfg" {
		t.Fatalf("namespace array cross-file goto-def = %#v", locs)
	}

	defOff := strings.Index(lib, "cfg(host)")
	refs := r.References("lib.tcl", lib, defOff)
	found := false
	for _, l := range refs {
		if l.File == "use.tcl" {
			found = true
		}
	}
	if !found {
		t.Fatalf("references missing the ::app::cfg use in use.tcl: %#v", refs)
	}
}

func TestDefinitionGlobalChasesToOrigin(t *testing.T) {
	ix := index.New()
	ix.IndexFile("lib.tcl", "set ::config 1")
	use := "proc f {} {\n  global config\n  return $config\n}"
	ix.IndexFile("use.tcl", use)
	r := New(ix)

	off := strings.Index(use, "return $config") + len("return $")
	locs := r.Definition("use.tcl", use, off)
	if len(locs) != 1 || locs[0].File != "lib.tcl" || locs[0].Name != "::config" {
		t.Fatalf("global chase = %#v", locs)
	}
}

func TestDefinitionGlobalFallsBackToLink(t *testing.T) {
	r := New(index.New())
	src := "proc f {} {\n  global config\n  return $config\n}"
	off := strings.Index(src, "return $config") + len("return $")
	locs := r.Definition("a.tcl", src, off)
	if len(locs) != 1 || locs[0].File != "a.tcl" {
		t.Fatalf("want fallback to link in a.tcl, got %#v", locs)
	}
	// ::config is undefined in the workspace -> land on the `global config` line.
	if locs[0].NameStart != strings.Index(src, "global config")+len("global ") {
		t.Fatalf("expected the `global config` link, got %#v", locs)
	}
}

func TestDefinitionUpvarHashZeroChasesToOrigin(t *testing.T) {
	ix := index.New()
	ix.IndexFile("lib.tcl", "set ::sessions {}")
	use := "proc f {} {\n  upvar #0 sessions s\n  return $s\n}"
	ix.IndexFile("use.tcl", use)
	r := New(ix)

	off := strings.Index(use, "return $s") + len("return $")
	locs := r.Definition("use.tcl", use, off)
	if len(locs) != 1 || locs[0].File != "lib.tcl" || locs[0].Name != "::sessions" {
		t.Fatalf("upvar #0 chase = %#v", locs)
	}
}

func TestDefinitionUpvarFrameRelativeStaysOnLink(t *testing.T) {
	r := New(index.New())
	src := "proc f {} {\n  upvar 1 caller v\n  return $v\n}"
	off := strings.Index(src, "return $v") + len("return $")
	locs := r.Definition("a.tcl", src, off)
	if len(locs) != 1 || locs[0].File != "a.tcl" {
		t.Fatalf("want link in a.tcl, got %#v", locs)
	}
	// frame-relative target is dynamic -> land on the upvar alias `v`.
	if locs[0].NameStart != strings.Index(src, "caller v")+len("caller ") {
		t.Fatalf("expected the upvar alias v, got %#v", locs)
	}
}

func TestRVTToTCLCrossFile(t *testing.T) {
	ix := index.New()
	ix.IndexFile("lib.tcl", "namespace eval ::lib { proc helper {} {} }")
	page := "<h1><?= [::lib::helper] ?></h1>"
	ix.IndexFile("page.rvt", page)
	r := New(ix)

	// goto-definition from the .rvt call jumps into lib.tcl.
	off := strings.Index(page, "helper")
	locs := r.Definition("page.rvt", page, off)
	if len(locs) != 1 || locs[0].File != "lib.tcl" || locs[0].Name != "::lib::helper" {
		t.Fatalf("rvt->tcl goto-def = %#v", locs)
	}

	// find-references from the lib.tcl definition includes the .rvt call site.
	libSrc := ix.Source("lib.tcl")
	defOff := strings.Index(libSrc, "helper")
	got := r.References("lib.tcl", libSrc, defOff)
	var inRVT bool
	for _, l := range got {
		if l.File == "page.rvt" {
			inRVT = true
		}
	}
	if !inRVT {
		t.Fatalf("expected page.rvt among references to ::lib::helper: %#v", got)
	}
}

func TestDefinitionLocalReachingBranch(t *testing.T) {
	r := New(index.New())
	src := "proc f {} {\n  set x 1\n  if {$c} { set x 2 } else { set x 3 }\n  puts $x\n}"
	off := strings.LastIndex(src, "$x") + 1
	defs := r.Definition("a.tcl", src, off)
	if len(defs) != 2 { // reaches set x 2 and set x 3, not set x 1
		t.Fatalf("reaching goto-def: want 2, got %#v", defs)
	}
}

func TestDefinitionLocalReachingLatestStraightLine(t *testing.T) {
	r := New(index.New())
	src := "proc f {} {\n  set x 1\n  set x 2\n  puts $x\n}"
	off := strings.LastIndex(src, "$x") + 1
	defs := r.Definition("a.tcl", src, off)
	if len(defs) != 1 || defs[0].NameStart != strings.LastIndex(src, "set x 2")+len("set ") {
		t.Fatalf("want the latest binding (set x 2), got %#v", defs)
	}
}

func TestDefinitionItclClassInstantiation(t *testing.T) {
	ix := index.New()
	ix.IndexFile("disp.tcl", "itcl::class ::STDisplay {\n  method field {} {}\n}")
	r := New(ix)
	src := "set d [::STDisplay #auto]"
	off := strings.Index(src, "::STDisplay") // cursor on the class in the instantiation
	locs := r.Definition("use.tcl", src, off)
	if len(locs) != 1 || locs[0].File != "disp.tcl" || locs[0].Name != "::STDisplay" {
		t.Fatalf("instantiation goto-def = %#v", locs)
	}
}

func TestReferencesItclClass(t *testing.T) {
	ix := index.New()
	ix.IndexFile("disp.tcl", "itcl::class ::STDisplay {\n  method field {} {}\n}")
	ix.IndexFile("a.tcl", "set d [::STDisplay #auto]")
	r := New(ix)
	defSrc := ix.Source("disp.tcl")
	defOff := strings.Index(defSrc, "::STDisplay") // cursor on the class name at its definition
	refs := r.References("disp.tcl", defSrc, defOff)
	var inA bool
	for _, l := range refs {
		if l.File == "a.tcl" {
			inA = true
		}
	}
	if !inA {
		t.Fatalf("class references should include the a.tcl instantiation: %#v", refs)
	}
}

func TestDefinitionIntraClassMethod(t *testing.T) {
	ix := index.New()
	ix.IndexFile("c.tcl",
		"itcl::class ::Base { method helper {} {} }\n"+
			"itcl::class ::Derived {\n  inherit ::Base\n"+
			"  method run {} {\n    helper\n    field\n  }\n"+
			"  method field {} {}\n}")
	r := New(ix)
	src := ix.Source("c.tcl")
	// bare `field` call inside run() -> Derived's own method
	offField := strings.Index(src, "    field") + len("    ")
	if locs := r.Definition("c.tcl", src, offField); len(locs) != 1 || locs[0].Name != "field" {
		t.Fatalf("intra-class method `field` = %#v", locs)
	}
	// bare `helper` call -> inherited from ::Base (MRO)
	offHelper := strings.Index(src, "    helper") + len("    ")
	if locs := r.Definition("c.tcl", src, offHelper); len(locs) != 1 || locs[0].Name != "helper" {
		t.Fatalf("inherited method `helper` = %#v", locs)
	}
}

func TestDefinitionIvar(t *testing.T) {
	ix := index.New()
	ix.IndexFile("c.tcl",
		"itcl::class ::Base { variable shared 0 }\n"+
			"itcl::class ::Derived {\n  inherit ::Base\n  variable count 0\n"+
			"  method run {} {\n    return [list $count $shared]\n  }\n}")
	r := New(ix)
	src := ix.Source("c.tcl")
	offCount := strings.Index(src, "$count") + 1
	if locs := r.Definition("c.tcl", src, offCount); len(locs) != 1 || locs[0].Name != "count" {
		t.Fatalf("ivar $count = %#v", locs)
	}
	offShared := strings.Index(src, "$shared") + 1
	if locs := r.Definition("c.tcl", src, offShared); len(locs) != 1 || locs[0].Name != "shared" {
		t.Fatalf("inherited ivar $shared = %#v", locs)
	}
}
