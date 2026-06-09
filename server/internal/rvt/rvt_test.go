package rvt

import (
	"strings"
	"testing"

	"github.com/unknownbreaker/tcl-lsp/internal/tcl"
)

func TestDocumentToSourceToVirtual(t *testing.T) {
	// Two verbatim regions, ordered the same way in both coordinate systems.
	d := Document{Mapping: []Segment{
		{VirtOff: 10, SrcOff: 2, Len: 5},
		{VirtOff: 20, SrcOff: 30, Len: 3},
	}}

	if got := d.ToSource(12); got != 4 { // inside segment 0
		t.Fatalf("ToSource(12) = %d, want 4", got)
	}
	if got := d.ToSource(21); got != 31 { // inside segment 1
		t.Fatalf("ToSource(21) = %d, want 31", got)
	}
	if got := d.ToSource(0); got != -1 { // before any region (wrapper)
		t.Fatalf("ToSource(0) = %d, want -1", got)
	}
	if got := d.ToSource(15); got != -1 { // gap between segments
		t.Fatalf("ToSource(15) = %d, want -1", got)
	}

	if v, ok := d.ToVirtual(31); !ok || v != 21 {
		t.Fatalf("ToVirtual(31) = %d,%v want 21,true", v, ok)
	}
	if _, ok := d.ToVirtual(0); ok { // literal region
		t.Fatalf("ToVirtual(0) should be false")
	}
}

func TestExtractSingleCodeBlock(t *testing.T) {
	src := `<h1><? set title "Pets" ?></h1>`
	d := Extract(src)

	if !strings.Contains(d.Script, "namespace eval ::request {") {
		t.Fatalf("script not wrapped in ::request:\n%s", d.Script)
	}
	if !strings.Contains(d.Script, `set title "Pets"`) {
		t.Fatalf("code not stitched verbatim:\n%s", d.Script)
	}

	// The stitched code parses, and the top-level set lands in ::request.
	defs := tcl.FileDefs(d.Script)
	var def *tcl.Definition
	for i := range defs {
		if defs[i].Name == "::request::title" {
			def = &defs[i]
		}
	}
	if def == nil {
		t.Fatalf("expected ::request::title definition; defs=%#v", defs)
	}

	// Its name range maps back onto `title` in the .rvt source.
	srcOff := d.ToSource(def.NameStart)
	if srcOff < 0 || !strings.HasPrefix(src[srcOff:], "title") {
		end := min(srcOff+8, len(src))
		t.Fatalf("NameStart %d mapped to src %d (%q), want start of 'title'",
			def.NameStart, srcOff, src[max(srcOff, 0):end])
	}
}

func TestExtractOutputShorthand(t *testing.T) {
	src := `<h1><?= $title ?></h1>`
	d := Extract(src)

	var found bool
	for _, r := range tcl.FileRefs(d.Script) {
		if r.Ref.Kind == tcl.RefVariable && r.Ref.Name == "title" {
			found = true
			srcOff := d.ToSource(r.Ref.Start)
			// Start may or may not include the leading '$'; accept either, but it
			// must map back onto the title token in the source.
			if srcOff < 0 || !(strings.HasPrefix(src[srcOff:], "title") || strings.HasPrefix(src[srcOff:], "$title")) {
				end := min(srcOff+8, len(src))
				t.Fatalf("ref mapped to src %d (%q), want 'title'/'$title'", srcOff, src[max(srcOff, 0):end])
			}
		}
	}
	if !found {
		t.Fatalf("expected $title variable ref from <?= ?>; refs=%#v", tcl.FileRefs(d.Script))
	}
}

func TestExtractControlFlowSpansBlocks(t *testing.T) {
	// foreach opens in one block, body is HTML + <?= ?>, closes in a later block.
	src := "<? foreach it $items { ?>\n  <li><?= $it ?></li>\n<? } ?>\n"
	d := Extract(src)

	refs := tcl.FileRefs(d.Script)

	// The loop variable used inside <?= ?> is seen — proof the braces stitched
	// across blocks into one balanced foreach (an unbalanced stitch would not
	// parse the body).
	var sawIt, sawItems bool
	for _, r := range refs {
		if r.Ref.Kind == tcl.RefVariable && r.Ref.Name == "it" {
			sawIt = true
		}
		if r.Ref.Kind == tcl.RefVariable && r.Ref.Name == "items" {
			sawItems = true
			if d.ToSource(r.Ref.Start) < 0 {
				t.Fatalf("$items did not map back to source")
			}
		}
	}
	if !sawIt {
		t.Fatalf("expected $it inside the stitched loop body; script:\n%s\nrefs:%#v", d.Script, refs)
	}
	if !sawItems {
		t.Fatalf("expected $items reference; refs:%#v", refs)
	}
}

func TestExtractNoTags(t *testing.T) {
	d := Extract("<html><body>no code here</body></html>")
	if len(d.Mapping) != 0 {
		t.Fatalf("expected no segments, got %#v", d.Mapping)
	}
	if defs := tcl.FileDefs(d.Script); len(defs) != 0 {
		t.Fatalf("expected no defs from a tag-less file, got %#v", defs)
	}
}

func TestExtractEmpty(t *testing.T) {
	d := Extract("")
	if len(d.Mapping) != 0 {
		t.Fatalf("expected no segments")
	}
	if !strings.Contains(d.Script, "namespace eval ::request {") {
		t.Fatalf("wrapper missing for empty input: %q", d.Script)
	}
}

func TestExtractUnterminatedTag(t *testing.T) {
	src := "<? set x 1\nset y 2" // no closing ?>
	d := Extract(src)
	var sawX bool
	for _, dfn := range tcl.FileDefs(d.Script) {
		if dfn.Name == "::request::x" {
			sawX = true
		}
	}
	if !sawX {
		t.Fatalf("unterminated tag should emit code to EOF; defs=%#v", tcl.FileDefs(d.Script))
	}
}

func TestExtractStrayCloseTag(t *testing.T) {
	// A stray ?> in literal text (no preceding <?) is dropped as literal; the
	// real code after it still parses.
	src := "plain ?> text <? set a 1 ?>"
	d := Extract(src)
	var sawA bool
	for _, dfn := range tcl.FileDefs(d.Script) {
		if dfn.Name == "::request::a" {
			sawA = true
		}
	}
	if !sawA {
		t.Fatalf("code after a stray ?> should still parse; defs=%#v", tcl.FileDefs(d.Script))
	}
}
