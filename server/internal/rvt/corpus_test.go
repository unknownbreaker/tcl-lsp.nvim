package rvt

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/unknownbreaker/tcl-lsp/internal/tcl"
)

// TestCorpusExtractionInvariants sweeps every .rvt shape in testdata/corpus and
// asserts the extraction + mapping invariants that must hold for ANY template, so
// a regression in Extract/ToSource surfaces across realistic shapes -- not only
// the hand-written unit cases. The central invariant is verbatim fidelity: because
// regions are copied unchanged, the bytes at a mapped source range must equal the
// bytes at the corresponding script range. That single check catches off-by-one,
// wrong-segment, and boundary bugs without depending on token semantics.
func TestCorpusExtractionInvariants(t *testing.T) {
	files, err := filepath.Glob("testdata/corpus/*.rvt")
	if err != nil {
		t.Fatal(err)
	}
	if len(files) == 0 {
		t.Fatal("no corpus fixtures found under testdata/corpus")
	}

	for _, f := range files {
		t.Run(filepath.Base(f), func(t *testing.T) {
			b, err := os.ReadFile(f)
			if err != nil {
				t.Fatal(err)
			}
			src := string(b)

			doc := Extract(src) // must not panic on any shape

			// Mapping is well-formed: strictly increasing in both coordinate
			// systems, in-bounds, non-empty, and verbatim.
			prevV, prevS := -1, -1
			for i, seg := range doc.Mapping {
				if seg.Len <= 0 {
					t.Fatalf("segment %d has Len %d (want > 0)", i, seg.Len)
				}
				if seg.VirtOff < 0 || seg.VirtOff+seg.Len > len(doc.Script) {
					t.Fatalf("segment %d virt range [%d,%d) out of script bounds %d",
						i, seg.VirtOff, seg.VirtOff+seg.Len, len(doc.Script))
				}
				if seg.SrcOff < 0 || seg.SrcOff+seg.Len > len(src) {
					t.Fatalf("segment %d src range [%d,%d) out of source bounds %d",
						i, seg.SrcOff, seg.SrcOff+seg.Len, len(src))
				}
				if seg.VirtOff <= prevV || seg.SrcOff <= prevS {
					t.Fatalf("segment %d not strictly increasing (virt %d<=%d or src %d<=%d)",
						i, seg.VirtOff, prevV, seg.SrcOff, prevS)
				}
				prevV, prevS = seg.VirtOff, seg.SrcOff

				if got, want := src[seg.SrcOff:seg.SrcOff+seg.Len], doc.Script[seg.VirtOff:seg.VirtOff+seg.Len]; got != want {
					t.Fatalf("segment %d not verbatim:\n src=%q\n scr=%q", i, got, want)
				}
				if s := doc.ToSource(seg.VirtOff); s != seg.SrcOff {
					t.Fatalf("segment %d ToSource(VirtOff)=%d, want SrcOff %d", i, s, seg.SrcOff)
				}
				if v, ok := doc.ToVirtual(seg.SrcOff); !ok || v != seg.VirtOff {
					t.Fatalf("segment %d ToVirtual(SrcOff)=%d,%v, want %d,true", i, v, ok, seg.VirtOff)
				}
			}

			// Every def/ref parsed from the stitched script must map back to the
			// same bytes in the original .rvt (or to -1 for synthetic wrapper
			// tokens, which carry no source position).
			for _, d := range tcl.FileDefs(doc.Script) {
				assertVerbatimMapping(t, doc, src, d.NameStart, d.NameEnd, "def "+d.Name)
			}
			for _, r := range tcl.FileRefs(doc.Script) {
				assertVerbatimMapping(t, doc, src, r.Ref.Start, r.Ref.End, "ref "+r.Ref.Name)
			}
		})
	}
}

// assertVerbatimMapping checks that the script range [start,end) maps to a source
// range holding identical bytes. A start that maps to -1 is a synthetic wrapper
// token (the `namespace eval ::request` prefix) and is skipped.
func assertVerbatimMapping(t *testing.T, doc Document, src string, start, end int, what string) {
	t.Helper()
	s := doc.ToSource(start)
	if s < 0 {
		return // wrapper-synthetic; no source position
	}
	n := end - start
	if s+n > len(src) {
		t.Fatalf("%s: mapped source range [%d,%d) exceeds source len %d", what, s, s+n, len(src))
	}
	if got, want := src[s:s+n], doc.Script[start:end]; got != want {
		t.Fatalf("%s: verbatim mismatch src[%d:%d]=%q != script[%d:%d]=%q",
			what, s, s+n, got, start, end, want)
	}
}
