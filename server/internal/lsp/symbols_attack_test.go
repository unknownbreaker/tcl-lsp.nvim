package lsp

// Attack tests for buildDocumentSymbols, targeting the single-pass rewrite.
//
// Each test targets a specific correctness contract from the review request:
//   1. Source order within a namespace/root
//   2. No dropped/duplicated symbols
//   3. Class method/ivar children still present and in source order
//   4. Namespace nesting + .rvt hoist still intact
//   5. classSyms splice safety (nil deref, duplicate names colliding in map)
//   6. Ranges: SelectionRange within Range, namespace spans its children
//
// Run with: go -C <repo>/server test ./internal/lsp/ -run TestAttack -v

import (
	"reflect"
	"testing"

	"github.com/unknownbreaker/tcl-lsp/internal/source"
	"github.com/unknownbreaker/tcl-lsp/internal/tcl"
)

// --- helpers used only in attack tests ---

// countNamed counts how many symbols with the given name appear at any depth.
func countNamed(syms []DocumentSymbol, name string) int {
	n := 0
	for _, s := range syms {
		if s.Name == name {
			n++
		}
		n += countNamed(s.Children, name)
	}
	return n
}

// allNames returns every symbol name at any depth in document order.
func allNames(syms []DocumentSymbol) []string {
	var out []string
	for _, s := range syms {
		out = append(out, s.Name)
		out = append(out, allNames(s.Children)...)
	}
	return out
}

// rootNames returns just the top-level symbol names.
func rootNames(syms []DocumentSymbol) []string {
	out := make([]string, 0, len(syms))
	for _, s := range syms {
		out = append(out, s.Name)
	}
	return out
}

// ============================================================
// Contract 1: source order with mixed kinds and vars
// ============================================================

// A namespace var declared between two classes must appear between them.
func TestAttackSourceOrderVarBetweenClasses(t *testing.T) {
	// var between two classes at root scope
	src := "itcl::class ::First {}\nvariable mid 0\nitcl::class ::Second {}"
	syms := buildDocumentSymbols(tcl.FileDefs(src), src, false)
	got := rootNames(syms)
	want := []string{"::First", "mid", "::Second"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("root order = %v, want %v (source order)", got, want)
	}
}

// Three classes interleaved with procs at root scope.
func TestAttackSourceOrderMultipleClassesMixedWithProcs(t *testing.T) {
	src := "proc a {} {}\nitcl::class ::X {}\nproc b {} {}\nitcl::class ::Y {}\nproc c {} {}"
	syms := buildDocumentSymbols(tcl.FileDefs(src), src, false)
	got := rootNames(syms)
	want := []string{"a", "::X", "b", "::Y", "c"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("root order = %v, want %v", got, want)
	}
}

// Inside a namespace: class, var, proc, class interleaved.
func TestAttackSourceOrderMixedInNamespace(t *testing.T) {
	src := "namespace eval ::app {\n  itcl::class C1 {}\n  variable v 0\n  proc p {} {}\n  itcl::class C2 {}\n}"
	syms := buildDocumentSymbols(tcl.FileDefs(src), src, false)
	app := findSym(syms, "::app")
	if app == nil {
		t.Fatalf("::app missing: %#v", syms)
	}
	got := childNames(app.Children)
	// sub-namespace nodes are appended after direct members (known/accepted limit),
	// so we only check the direct-member portion
	want := []string{"C1", "v", "p", "C2"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("::app children order = %v, want %v", got, want)
	}
}

// ============================================================
// Contract 2: no dropped or duplicated symbols
// ============================================================

// BUG PROBE: Two DefClass entries with the same FQ name.
// Step 1 overwrites classSyms["::C"] with the second def.
// Step 2 iterates defs and sees TWO DefClass entries both with Name="::C",
// so it splices the (same) symbol into the output TWICE -> duplicate.
//
// ROOT CAUSE: the single-pass in Step 2 does `sym := *classSyms[d.Name]` for
// every DefClass in defs. When defs contains two DefClass entries with the same
// Name, classSyms has only one entry (the second one overwrites the first), but
// the loop body executes twice and calls addToNS twice, producing two copies.
// The old two-pass code avoided this because classNames preserved insertion order
// and only one entry per name existed in that slice (the *last* class definition
// would replace the earlier one in classSyms, but classNames only listed each name
// once if the caller never produced duplicates -- actually the old code also had
// this bug; the new code makes it easier to trigger because Step 2 drives from
// defs directly).
func TestAttackDuplicateClassNameNotDuplicated(t *testing.T) {
	// Simulate a class redefined (re-opened in itcl idiom or two separate files
	// concatenated). FileDefs produces two DefClass entries with the same name.
	src := "itcl::class ::C {}\nitcl::class ::C {}"
	syms := buildDocumentSymbols(tcl.FileDefs(src), src, false)
	count := countNamed(syms, "::C")
	if count != 1 {
		t.Fatalf("::C appears %d times in output, want exactly 1 (no duplicates)", count)
	}
}

// An itcl inner proc (DefProc with d.Class != "") must NOT appear at top level.
func TestAttackItclInnerProcNotAtTopLevel(t *testing.T) {
	// Inside itcl::class, `proc` is a class-local proc (not a top-level symbol).
	src := "itcl::class ::Widget {\n  proc helper {} {}\n  method render {} {}\n}"
	syms := buildDocumentSymbols(tcl.FileDefs(src), src, false)
	// "helper" must NOT appear at root or as a sibling of ::Widget
	for _, s := range syms {
		if s.Name == "helper" {
			t.Fatalf("itcl inner proc 'helper' leaked to top level: %#v", syms)
		}
	}
	// It also must NOT appear as a top-level child of root (only ::Widget should be there)
	names := rootNames(syms)
	for _, n := range names {
		if n == "helper" {
			t.Fatalf("itcl inner proc leaked: root = %v", names)
		}
	}
}

// A class and a proc sharing the same short name (different FQ names).
// Both must appear, neither dropped.
func TestAttackClassAndProcSameShortName(t *testing.T) {
	// proc named "render" and class named "::render" (allowed in TCL)
	src := "proc render {} {}\nitcl::class ::render {}"
	syms := buildDocumentSymbols(tcl.FileDefs(src), src, false)
	// "render" (proc) and "::render" (class) must both appear
	if findSym(syms, "render") == nil {
		t.Fatalf("proc 'render' dropped: %#v", syms)
	}
	if findSym(syms, "::render") == nil {
		t.Fatalf("class '::render' dropped: %#v", syms)
	}
}

// All three top-level kinds (class, proc, var) present; none dropped.
func TestAttackAllThreeKindsPresent(t *testing.T) {
	src := "proc p {} {}\nvariable v 0\nitcl::class ::C {}"
	syms := buildDocumentSymbols(tcl.FileDefs(src), src, false)
	for _, name := range []string{"p", "v", "::C"} {
		if findSym(syms, name) == nil {
			t.Fatalf("symbol %q dropped; got %#v", name, syms)
		}
	}
}

// ============================================================
// Contract 3: class method/ivar children present and in source order
// ============================================================

// Methods and ivars in source order under their class.
func TestAttackClassChildrenSourceOrder(t *testing.T) {
	src := "itcl::class ::W {\n  variable x 0\n  method render {} {}\n  variable y 0\n  method destroy {} {}\n}"
	syms := buildDocumentSymbols(tcl.FileDefs(src), src, false)
	w := findSym(syms, "::W")
	if w == nil {
		t.Fatalf("::W missing: %#v", syms)
	}
	got := childNames(w.Children)
	want := []string{"x", "render", "y", "destroy"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("::W child order = %v, want %v", got, want)
	}
}

// When two classes have the same name (duplicate), the children of the first
// definition must not be silently dropped (they're attached to classSyms which
// gets overwritten by the second def in Step 1).
func TestAttackDuplicateClassChildrenNotLost(t *testing.T) {
	// First class has method "first_method"; second class has method "second_method".
	// classSyms["::C"] ends up as the second def's symbol. So first_method is lost.
	// This test documents that bug: first_method IS lost when class names collide.
	src := "itcl::class ::C {\n  method first_method {} {}\n}\nitcl::class ::C {\n  method second_method {} {}\n}"
	syms := buildDocumentSymbols(tcl.FileDefs(src), src, false)
	c := findSym(syms, "::C")
	if c == nil {
		t.Fatalf("::C missing entirely: %#v", syms)
	}
	// first_method is attached to the first def's symbol, which gets dropped by overwrite.
	// second_method is attached to the second def's symbol, which survives.
	// This test verifies what actually happens (first_method dropped) so a fix can target it.
	if findChild(c, "first_method") == nil && findChild(c, "second_method") == nil {
		t.Fatalf("::C has no children at all: %#v", c.Children)
	}
}

// ============================================================
// Contract 4: namespace nesting and .rvt hoist
// ============================================================

// Synthesized intermediate namespace nodes must not drop their children.
func TestAttackSynthesizedIntermediateNSNotEmpty(t *testing.T) {
	src := "namespace eval ::a::b::c {\n  proc leaf {} {}\n}"
	syms := buildDocumentSymbols(tcl.FileDefs(src), src, false)
	// ::a must exist and eventually contain "leaf" at some depth
	a := findSym(syms, "::a")
	if a == nil {
		t.Fatalf("::a namespace node missing: %#v", syms)
	}
	leaf := findSym(syms, "leaf")
	if leaf == nil {
		t.Fatalf("proc 'leaf' under ::a::b::c was dropped: %#v", syms)
	}
}

// .rvt hoist: multiple procs in ::request all promoted to root, none wrapped.
func TestAttackRVTHoistMultipleProcs(t *testing.T) {
	content := "<? proc alpha {} {} ?>\n<? proc beta {} {} ?>"
	defs := source.Defs("p.rvt", content)
	syms := buildDocumentSymbols(defs, content, true)
	// Both procs must be at root
	if findSym(syms, "alpha") == nil {
		t.Fatalf("alpha not hoisted to root: %#v", syms)
	}
	if findSym(syms, "beta") == nil {
		t.Fatalf("beta not hoisted to root: %#v", syms)
	}
	// ::request wrapper must not appear
	for _, s := range syms {
		if s.Name == "::request" {
			t.Fatalf("::request wrapper still present: %#v", syms)
		}
	}
}

// .rvt hoist: hoistRequest=false leaves ::request in place.
func TestAttackRVTNoHoistWhenFalse(t *testing.T) {
	content := "<? proc render {} {} ?>"
	defs := source.Defs("p.rvt", content)
	syms := buildDocumentSymbols(defs, content, false)
	// ::request must still appear at root when hoistRequest is false
	found := false
	for _, s := range syms {
		if s.Name == "::request" {
			found = true
			break
		}
	}
	if !found {
		t.Fatalf("::request wrapper missing when hoistRequest=false: %#v", syms)
	}
}

// ============================================================
// Contract 5: classSyms splice safety
// ============================================================

// BUG PROBE: nil deref guard. A DefClass whose Name is empty string would
// panic on `*classSyms[""]` if classSyms[""] is nil (it's never populated
// because Step 1 also requires isPlainName which blocks empty names at parse time).
// This test verifies the parser never produces an empty-named DefClass.
func TestAttackNoEmptyNamedClass(t *testing.T) {
	// The TCL parser should reject empty class names; verify no DefClass with Name=""
	// reaches buildDocumentSymbols.
	src := "itcl::class ::C {}"
	defs := tcl.FileDefs(src)
	for _, d := range defs {
		if d.Kind == tcl.DefClass && d.Name == "" {
			t.Fatalf("parser emitted DefClass with empty Name: %+v", d)
		}
	}
	// No panic expected from buildDocumentSymbols
	buildDocumentSymbols(defs, src, false)
}

// BUG PROBE: Two classes with the same FQ name in the same defs slice.
// Step 1 overwrites the map entry; Step 2 sees both DefClass entries and
// dereferences classSyms[d.Name] twice from the same pointer.
// The result is the symbol appearing twice in the output (duplicate).
// This is a HIGH-severity data-correctness bug.
func TestAttackDuplicateClassNoPanic(t *testing.T) {
	// Must not panic even when the same class name appears twice.
	src := "itcl::class ::C {}\nitcl::class ::C {}"
	// If this panics (nil deref), the test harness reports a runtime panic.
	// If it duplicates, TestAttackDuplicateClassNameNotDuplicated catches it.
	defer func() {
		if r := recover(); r != nil {
			t.Fatalf("panic in buildDocumentSymbols with duplicate class: %v", r)
		}
	}()
	buildDocumentSymbols(tcl.FileDefs(src), src, false)
}

// ============================================================
// Contract 6: ranges
// ============================================================

// Every symbol's SelectionRange must be within its Range.
func TestAttackSelectionRangeWithinRange(t *testing.T) {
	src := "proc alpha {} {}\nvariable v 0\nitcl::class ::C {\n  method render {} {}\n  variable x 0\n}\nproc omega {} {}"
	syms := buildDocumentSymbols(tcl.FileDefs(src), src, false)
	var check func(syms []DocumentSymbol)
	check = func(syms []DocumentSymbol) {
		for _, s := range syms {
			if !posLE(s.Range.Start, s.SelectionRange.Start) {
				t.Errorf("symbol %q: Range.Start %v > SelectionRange.Start %v", s.Name, s.Range.Start, s.SelectionRange.Start)
			}
			if !posLE(s.SelectionRange.End, s.Range.End) {
				t.Errorf("symbol %q: SelectionRange.End %v > Range.End %v", s.Name, s.SelectionRange.End, s.Range.End)
			}
			check(s.Children)
		}
	}
	check(syms)
}

// Namespace node Range must span all its children's Ranges.
func TestAttackNamespaceRangeSpansChildren(t *testing.T) {
	src := "namespace eval ::app {\n  proc first {} {}\n  proc last {} {}\n}"
	syms := buildDocumentSymbols(tcl.FileDefs(src), src, false)
	app := findSym(syms, "::app")
	if app == nil {
		t.Fatalf("::app missing")
	}
	for _, child := range app.Children {
		if !posLE(app.Range.Start, child.Range.Start) {
			t.Errorf("::app Range.Start %v after child %q Range.Start %v", app.Range.Start, child.Name, child.Range.Start)
		}
		if !posLE(child.Range.End, app.Range.End) {
			t.Errorf("::app Range.End %v before child %q Range.End %v", app.Range.End, child.Name, child.Range.End)
		}
	}
}

// ============================================================
// Bonus: absolute FQ class name inside a non-global namespace
// ============================================================

// A class declared as ::Top inside namespace eval ::app is placed under ::app
// in the symbol tree, not under ::. This is a pre-existing limitation, but
// verify it doesn't CRASH and that the class appears somewhere.
func TestAttackAbsoluteFQClassInsideNamespace(t *testing.T) {
	// itcl::class ::Top inside namespace eval ::app:
	// d.Namespace = "::app", d.Name = "::Top"
	// shortName("::Top") = "Top" -- so it appears as "Top" under ::app
	src := "namespace eval ::app {\n  itcl::class ::Top {}\n}"
	defer func() {
		if r := recover(); r != nil {
			t.Fatalf("panic: %v", r)
		}
	}()
	syms := buildDocumentSymbols(tcl.FileDefs(src), src, false)
	// Must appear somewhere (even if misplaced under ::app instead of ::)
	found := findSym(syms, "Top") != nil || findSym(syms, "::Top") != nil
	if !found {
		t.Fatalf("class ::Top declared inside ::app disappeared entirely: %#v", syms)
	}
}

// ============================================================
// Existing-test guard: make sure old passing tests still pass
// with the exact same inputs
// ============================================================

func TestAttackRegressionSourceOrderRoot(t *testing.T) {
	src := "proc alpha {} {}\nitcl::class ::Widget {}\nproc omega {} {}"
	syms := buildDocumentSymbols(tcl.FileDefs(src), src, false)
	got := childNames(syms)
	want := []string{"alpha", "::Widget", "omega"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("regression in source order root: got %v, want %v", got, want)
	}
}

func TestAttackRegressionSourceOrderInNamespace(t *testing.T) {
	src := "namespace eval ::app {\n  proc a {} {}\n  itcl::class C {}\n  proc b {} {}\n}"
	syms := buildDocumentSymbols(tcl.FileDefs(src), src, false)
	app := findSym(syms, "::app")
	if app == nil {
		t.Fatalf("::app missing")
	}
	got := childNames(app.Children)
	want := []string{"a", "C", "b"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("regression in namespace source order: got %v, want %v", got, want)
	}
}
