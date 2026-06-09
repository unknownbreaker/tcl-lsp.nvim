package rvt

import (
	"testing"
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
