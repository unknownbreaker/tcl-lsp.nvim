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
