// Package source produces definitions, references, and namespace declarations for
// a workspace file in SOURCE coordinates, dispatching on file type: .tcl is parsed
// directly; .rvt is extracted to a stitched ::request script (package rvt), parsed,
// and each offset translated back to .rvt coordinates. Both the index and the
// resolver use this seam so neither needs to know about templates.
package source

import (
	"strings"

	"github.com/unknownbreaker/tcl-lsp/internal/rvt"
	"github.com/unknownbreaker/tcl-lsp/internal/tcl"
)

// IsRVT reports whether path is a Rivet template, by extension.
func IsRVT(path string) bool { return strings.HasSuffix(path, ".rvt") }

// Defs returns the definitions declared in content, in source coordinates. For
// .rvt, name ranges are translated from the stitched script back to the .rvt;
// wrapper-synthetic definitions (which map to -1) are dropped.
func Defs(path, content string) []tcl.Definition {
	if !IsRVT(path) {
		return tcl.FileDefs(content)
	}
	doc := rvt.Extract(content)
	var out []tcl.Definition
	for _, d := range tcl.FileDefs(doc.Script) {
		s := doc.ToSource(d.NameStart)
		if s < 0 {
			continue
		}
		d.NameStart, d.NameEnd = s, s+(d.NameEnd-d.NameStart)
		out = append(out, d)
	}
	return out
}

// Refs returns the contextual references in content, in source coordinates (see
// Defs). The synthetic `namespace eval ::request` wrapper produces a `namespace`
// command-ref at a wrapper offset that maps to -1; such refs are dropped.
func Refs(path, content string) []tcl.ContextRef {
	if !IsRVT(path) {
		return tcl.FileRefs(content)
	}
	doc := rvt.Extract(content)
	var out []tcl.ContextRef
	for _, r := range tcl.FileRefs(doc.Script) {
		s := doc.ToSource(r.Ref.Start)
		if s < 0 {
			continue
		}
		r.Ref.Start, r.Ref.End = s, s+(r.Ref.End-r.Ref.Start)
		out = append(out, r)
	}
	return out
}

// Namespaces returns per-namespace declarations for content. NamespaceInfo holds
// names only (no offsets), so no translation is required; for .rvt the stitched
// script is parsed directly.
func Namespaces(path, content string) map[string]*tcl.NamespaceInfo {
	if !IsRVT(path) {
		return tcl.FileNamespaces(content)
	}
	return tcl.FileNamespaces(rvt.Extract(content).Script)
}

// Reaching returns the local bindings that may reach the variable use at byte
// offset in content, in SOURCE coordinates. For .rvt the offset is mapped into the
// stitched ::request script and each result range is translated back to the .rvt;
// ranges that map outside a real region are dropped. ok is false when there is no
// reaching set (caller falls back).
func Reaching(path, content string, offset int) ([]tcl.Definition, bool) {
	if !IsRVT(path) {
		return tcl.ReachingAt(content, offset)
	}
	doc := rvt.Extract(content)
	vOff, ok := doc.ToVirtual(offset)
	if !ok {
		return nil, false
	}
	defs, ok := tcl.ReachingAt(doc.Script, vOff)
	if !ok {
		return nil, false
	}
	var out []tcl.Definition
	for _, d := range defs {
		s := doc.ToSource(d.NameStart)
		if s < 0 {
			continue
		}
		d.NameStart, d.NameEnd = s, s+(d.NameEnd-d.NameStart)
		out = append(out, d)
	}
	return out, len(out) > 0
}
