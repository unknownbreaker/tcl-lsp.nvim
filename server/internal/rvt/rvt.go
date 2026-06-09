// Package rvt converts Apache Rivet (.rvt) templates into a stitched virtual TCL
// script plus a bidirectional byte-offset map, so the TCL core can parse template
// code and report positions back in .rvt coordinates. It is pure: no protocol, no
// index, no dependency on the tcl package.
package rvt

import (
	"sort"
	"strings"
)

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

const (
	nsPrefix = "namespace eval ::request {\n"
	nsSuffix = "}\n"
)

// Extract converts .rvt bytes into a stitched virtual TCL Document. The bodies of
// every <? … ?> and <?= … ?> region are concatenated verbatim, newline-joined,
// inside a `namespace eval ::request { … }` wrapper so template-top-level symbols
// parse as ::request::*. Literal (non-tag) text is dropped. Extraction is
// tolerant: an unterminated <? emits the remainder of the file as code.
func Extract(src string) Document {
	var b strings.Builder
	b.WriteString(nsPrefix)
	var mapping []Segment

	i := 0
	for i < len(src) {
		open := strings.Index(src[i:], "<?")
		if open < 0 {
			break // remainder is literal output
		}
		codeStart := i + open + 2
		// <?= shorthand: the inner expression's symbols still parse as references,
		// so skip only the '=' marker and emit the expression body.
		if codeStart < len(src) && src[codeStart] == '=' {
			codeStart++
		}
		rel := strings.Index(src[codeStart:], "?>")
		codeEnd := len(src) // unterminated tag: emit to EOF (tolerant)
		if rel >= 0 {
			codeEnd = codeStart + rel
		}

		region := src[codeStart:codeEnd]
		if len(region) > 0 {
			// Skip empty regions (e.g. <??>): a zero-length segment can never match
			// a translation lookup, so recording one is dead weight.
			mapping = append(mapping, Segment{VirtOff: b.Len(), SrcOff: codeStart, Len: len(region)})
			b.WriteString(region)
			b.WriteByte('\n')
		}

		if rel < 0 {
			break
		}
		i = codeEnd + 2
	}

	b.WriteString(nsSuffix)
	return Document{Script: b.String(), Mapping: mapping}
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
