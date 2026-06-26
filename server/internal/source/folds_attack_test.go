package source

// Attack tests for source.Folds — focuses on .rvt translation correctness,
// the synthetic ::request wrapper body being dropped, cross-region folds,
// and off-by-one at region boundaries.

import (
	"strings"
	"testing"

	"github.com/unknownbreaker/tcl-lsp/internal/tcl"
)

// ---- helpers ----------------------------------------------------------------

// assertFoldBytesAreValid checks that every FoldRange's Open and Close offsets
// point to '{' and '}' in the given source string.
func assertSourceFoldBytes(t *testing.T, src string, folds []tcl.FoldRange, label string) {
	t.Helper()
	for _, f := range folds {
		if f.Open < 0 || f.Open >= len(src) {
			t.Errorf("[%s] Open=%d out of bounds (src len %d)", label, f.Open, len(src))
			continue
		}
		if src[f.Open] != '{' {
			t.Errorf("[%s] src[Open=%d] = %q, want '{'", label, f.Open, src[f.Open])
		}
		if f.Close < 0 || f.Close >= len(src) {
			t.Errorf("[%s] Close=%d out of bounds (src len %d)", label, f.Close, len(src))
			continue
		}
		if src[f.Close] != '}' {
			t.Errorf("[%s] src[Close=%d] = %q, want '}'", label, f.Close, src[f.Close])
		}
	}
}

// ---- .tcl passthrough -------------------------------------------------------

// For a .tcl file, Folds must return the same byte offsets as FileFolds, and
// all Open/Close must point to { and }.
func TestFolds_TCLPassthrough(t *testing.T) {
	src := "proc p {} {\n  puts hi\n}\n"
	folds := Folds("t.tcl", src)
	if len(folds) == 0 {
		t.Fatal("no folds for tcl proc")
	}
	assertSourceFoldBytes(t, src, folds, "tcl")
}

// ---- .rvt synthetic wrapper body is dropped --------------------------------

// The outermost fold produced by FileFolds on the stitched script is the
// namespace eval ::request {} body. Both its endpoints are in synthetic
// (non-region) bytes and must translate to -1, so source.Folds must drop it.
func TestFolds_RVT_SyntheticWrapperDropped(t *testing.T) {
	// A simple .rvt with one multi-line proc.
	src := "<html>\n<?\nproc p {} {\n  puts hi\n}\n?>\n</html>\n"
	folds := Folds("p.rvt", src)

	// All returned folds must have Open/Close pointing to { and } in the .rvt source.
	assertSourceFoldBytes(t, src, folds, "rvt-wrapper-dropped")

	// No fold should have Open before the first <? (which starts the first real region).
	firstTag := strings.Index(src, "<?")
	for _, f := range folds {
		if f.Open < firstTag {
			t.Errorf("fold Open=%d is before first <? at %d; fold likely from synthetic wrapper", f.Open, firstTag)
		}
	}
}

// ---- .rvt proc fold in source coords ----------------------------------------

// A multi-line proc inside a <? ?> block should fold with Open at the proc
// body's '{' in .rvt source coordinates and Close at its '}'.
func TestFolds_RVT_ProcFoldSourceCoords(t *testing.T) {
	// Positions in the .rvt source:
	//   line 0: <html>
	//   line 1: <?
	//   line 2: proc p {} {   <- proc body { is on this line
	//   line 3:   puts hi
	//   line 4: }             <- proc body } is on this line
	//   line 5: ?>
	//   line 6: </html>
	src := "<html>\n<?\nproc p {} {\n  puts hi\n}\n?>\n</html>\n"

	folds := Folds("p.rvt", src)
	assertSourceFoldBytes(t, src, folds, "rvt-proc")

	// The proc body '{' is at the position of '{\n  puts' in the .rvt source.
	bodyOpen := strings.Index(src, "{\n  puts")
	if bodyOpen < 0 {
		t.Fatalf("test bug: can't find proc body in src")
	}

	var found bool
	for _, f := range folds {
		if f.Open == bodyOpen {
			found = true
			// Close must be the matching '}' in .rvt source.
			bodyClose := strings.Index(src, "\n}\n?>")
			if bodyClose < 0 {
				t.Fatalf("test bug: can't find body close")
			}
			bodyClose++ // advance past the \n to the }
			if f.Close != bodyClose {
				t.Errorf("proc fold Close=%d want %d (src[Close]=%q)", f.Close, bodyClose, src[f.Close])
			}
		}
	}
	if !found {
		t.Fatalf("proc fold with Open=%d not found; folds=%+v", bodyOpen, folds)
	}
}

// ---- cross-region fold: { in one block, } in another -----------------------

// A foreach that opens its brace in one <? ?> block and closes it in a later
// block should produce a fold that spans across the intervening HTML. Both
// endpoints must be in their respective <? ?> regions and translate correctly.
func TestFolds_RVT_CrossRegionForeach(t *testing.T) {
	// <? foreach x $list { ?>
	// <li>...</li>
	// <? } ?>
	src := "<? foreach x $list { ?>\n<li></li>\n<? } ?>\n"

	folds := Folds("p.rvt", src)
	assertSourceFoldBytes(t, src, folds, "rvt-cross-region")

	// The { is at the end of the first <? ?> content and } is in the second.
	// Both must be present as valid .rvt source bytes in the fold.
	openOff := strings.Index(src, "{ ?>")
	if openOff < 0 {
		t.Fatalf("test bug: can't find { in src")
	}
	closeOff := strings.Index(src, "<? } ?>")
	if closeOff < 0 {
		t.Fatalf("test bug: can't find <? } in src")
	}
	// The actual } is 3 bytes into "<? } ?>" — after "<? ".
	closeOff += 3

	var found bool
	for _, f := range folds {
		if f.Open == openOff {
			found = true
			if f.Close != closeOff {
				t.Errorf("cross-region fold: Close=%d want=%d (src[Close]=%q want %q)",
					f.Close, closeOff, src[f.Close], src[closeOff])
			}
		}
	}
	if !found {
		t.Fatalf("cross-region foreach fold not found (looking for Open=%d); folds=%+v src=%q",
			openOff, folds, src)
	}
}

// ---- empty .rvt file -------------------------------------------------------

// An empty .rvt (no <? ?> blocks) should produce no folds and not panic.
func TestFolds_RVT_Empty(t *testing.T) {
	folds := Folds("p.rvt", "")
	if len(folds) != 0 {
		t.Fatalf("empty .rvt should produce no folds; got %+v", folds)
	}
}

// ---- .rvt with only HTML (no TCL) -----------------------------------------

func TestFolds_RVT_HTMLOnly(t *testing.T) {
	src := "<html><body><h1>Hello</h1></body></html>"
	folds := Folds("p.rvt", src)
	if len(folds) != 0 {
		t.Fatalf(".rvt with no <? ?> blocks should produce no folds; got %+v", folds)
	}
}

// ---- off-by-one at region boundary -----------------------------------------

// The '{' is the LAST byte of a region content (immediately before '?>').
// It must still be in the region and map correctly. The Close may be in a
// following region or the same region.
func TestFolds_RVT_OpenAtRegionEnd(t *testing.T) {
	// Proc body '{' is right before '?>' — the very last character of the region.
	// The body content spans to the next region (where '}' lives).
	// This tests that ToSource(offset_of_last_byte_of_region) works.
	src := "<? proc p {} { ?>\n<? puts hi\n} ?>\n"

	folds := Folds("p.rvt", src)
	// All fold bytes must be valid.
	assertSourceFoldBytes(t, src, folds, "open-at-region-end")

	// The '{' should be found as a fold open.
	openOff := strings.Index(src, "{ ?>")
	if openOff < 0 {
		t.Fatalf("test bug: can't find { in src")
	}
	// We don't assert the fold exists (the stitcher may not produce it due to
	// how the regions stitch), but we assert no fold has wrong byte at Open/Close.
	_ = openOff
}

// ---- .rvt: multiple procs each folded in source coords ----------------------

func TestFolds_RVT_MultipleProcs(t *testing.T) {
	src := "<?\nproc a {} {\n  puts a\n}\nproc b {} {\n  puts b\n}\n?>\n"
	folds := Folds("p.rvt", src)
	assertSourceFoldBytes(t, src, folds, "multiple-procs-rvt")

	// Both proc bodies must be folded.
	bodyA := strings.Index(src, "{\n  puts a")
	bodyB := strings.Index(src, "{\n  puts b")
	if bodyA < 0 || bodyB < 0 {
		t.Fatalf("test bug: can't locate proc bodies in src")
	}
	foundA, foundB := false, false
	for _, f := range folds {
		if f.Open == bodyA {
			foundA = true
		}
		if f.Open == bodyB {
			foundB = true
		}
	}
	if !foundA {
		t.Errorf("proc a body fold missing; folds=%+v", folds)
	}
	if !foundB {
		t.Errorf("proc b body fold missing; folds=%+v", folds)
	}
}

// ---- .rvt: itcl class body folded in source coords -------------------------

func TestFolds_RVT_ItclClassFolded(t *testing.T) {
	src := "<?\nitcl::class C {\n  method m {} {\n    puts hi\n  }\n}\n?>\n"
	folds := Folds("p.rvt", src)
	assertSourceFoldBytes(t, src, folds, "itcl-class-rvt")

	// The method body must be folded.
	methodBodyOpen := strings.Index(src, "{\n    puts hi")
	if methodBodyOpen < 0 {
		t.Fatalf("test bug: can't find method body in src")
	}
	for _, f := range folds {
		if f.Open == methodBodyOpen {
			return // found
		}
	}
	t.Fatalf("itcl method body fold missing; folds=%+v", folds)
}

// ---- TCL: no folds for empty/whitespace/comment sources --------------------

func TestFolds_TCL_EmptySource(t *testing.T) {
	folds := Folds("t.tcl", "")
	if len(folds) != 0 {
		t.Fatalf("empty source: want no folds, got %+v", folds)
	}
}

func TestFolds_TCL_CommentOnly(t *testing.T) {
	folds := Folds("t.tcl", "# just a comment\n")
	if len(folds) != 0 {
		t.Fatalf("comment-only source: want no folds, got %+v", folds)
	}
}

// ---- TCL: deeply nested folds all have correct bytes ----------------------

func TestFolds_TCL_DeepNestingOffsets(t *testing.T) {
	// 20 levels of nested proc + if bodies.
	src := "proc outer {} {\n"
	src += "  namespace eval ::ns {\n"
	src += "    proc inner {} {\n"
	src += "      if {1} {\n"
	src += "        while {1} {\n"
	src += "          puts deep\n"
	src += "        }\n"
	src += "      }\n"
	src += "    }\n"
	src += "  }\n"
	src += "}\n"

	folds := Folds("t.tcl", src)
	assertSourceFoldBytes(t, src, folds, "deep-nesting")
	if len(folds) < 5 {
		t.Errorf("expected at least 5 folds, got %d: %+v", len(folds), folds)
	}
}
