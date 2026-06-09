// Package rvt converts Apache Rivet (.rvt) templates into a stitched virtual TCL
// script plus a bidirectional byte-offset map, so the TCL core can parse template
// code and report positions back in .rvt coordinates. It is pure: no protocol, no
// index, no dependency on the tcl package.
package rvt

import "sort"

// Segment maps one verbatim region of the stitched script back to the .rvt
// source. Because the region text is copied unchanged, a single (VirtOff, SrcOff)
// pair plus Len describes the whole run; offset N within the region is VirtOff+N
// in the script and SrcOff+N in the source.
type Segment struct {
	VirtOff int // start offset of the region in Document.Script
	SrcOff  int // start offset of the same bytes in the original .rvt
	Len     int // region length in bytes (identical in both)
}

// Document is the result of Extract: the stitched TCL script and the ordered map
// of its regions. Mapping is sorted ascending by both VirtOff and SrcOff (regions
// are emitted in source order, verbatim).
type Document struct {
	Script  string
	Mapping []Segment
}

// ToSource maps an offset in d.Script to the corresponding byte offset in the
// original .rvt. Returns -1 when virtOff falls outside every mapped region (the
// synthetic namespace wrapper or a gap), which never holds a real symbol.
func (d Document) ToSource(virtOff int) int {
	segs := d.Mapping
	i := sort.Search(len(segs), func(i int) bool { return segs[i].VirtOff+segs[i].Len > virtOff })
	if i < len(segs) && virtOff >= segs[i].VirtOff {
		return segs[i].SrcOff + (virtOff - segs[i].VirtOff)
	}
	return -1
}

// ToVirtual maps a byte offset in the original .rvt to an offset in d.Script. ok
// is false when srcOff falls in literal (non-TCL) text, which has no place in the
// stitched script.
func (d Document) ToVirtual(srcOff int) (int, bool) {
	segs := d.Mapping
	i := sort.Search(len(segs), func(i int) bool { return segs[i].SrcOff+segs[i].Len > srcOff })
	if i < len(segs) && srcOff >= segs[i].SrcOff {
		return segs[i].VirtOff + (srcOff - segs[i].SrcOff), true
	}
	return 0, false
}
