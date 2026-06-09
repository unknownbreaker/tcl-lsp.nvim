# Phase B — Plan 01: RVT extractor (stitched virtual TCL + position map)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A pure `rvt` package that turns `.rvt` bytes into a stitched virtual TCL script (wrapped in `namespace eval ::request { … }`) plus a bidirectional byte-offset map, so the existing TCL core can parse `.rvt` content and report positions back in `.rvt` coordinates.

**Architecture:** `rvt.Extract(src)` scans for `<? … ?>` / `<?= … ?>` regions, concatenates their *verbatim* bodies (newline-joined) inside a `::request` namespace wrapper, and records one `Segment{VirtOff, SrcOff, Len}` per region. Because regions are verbatim, the map is piecewise-linear and translation (`ToSource`/`ToVirtual`) is a binary search. No integration in this plan — the package is pure and independently tested.

**Tech Stack:** Go 1.23+ (local 1.26.4), `testing`; tests reference the existing `internal/tcl` package to confirm the stitched script parses as intended.

**Design basis:** `docs/plans/2026-06-08-phase-b-rvt-design.md` §2, §4.1, §6 build-order step 1.

---

## File structure

- Create: `server/internal/rvt/rvt.go` — `Document`, `Segment`, `ToSource`, `ToVirtual`, `Extract`.
- Create: `server/internal/rvt/rvt_test.go` — unit tests.

The package is pure string/offset work; it imports only the standard library. Test code imports `internal/tcl` to assert that the stitched script parses (no production dependency `rvt → tcl`, and `tcl` never imports `rvt`, so there is no cycle).

All test commands below assume the module directory `server/` (module path `github.com/unknownbreaker/tcl-lsp`).

---

## Task 1: `Document`/`Segment` types + offset translation

**Files:**
- Create: `server/internal/rvt/rvt.go`
- Create: `server/internal/rvt/rvt_test.go`

- [ ] **Step 1: Write the failing test**

Create `server/internal/rvt/rvt_test.go`:

```go
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/rvt/`
Expected: FAIL — build error, `Document`/`Segment` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `server/internal/rvt/rvt.go`:

```go
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/rvt/ -run TestDocumentToSourceToVirtual -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add server/internal/rvt/rvt.go server/internal/rvt/rvt_test.go
git commit -m "feat(rvt): Document/Segment with bidirectional offset mapping"
```

---

## Task 2: `Extract` — code blocks, `::request` wrapper, mapping

**Files:**
- Modify: `server/internal/rvt/rvt.go`
- Modify: `server/internal/rvt/rvt_test.go`

- [ ] **Step 1: Write the failing test**

Add to `server/internal/rvt/rvt_test.go`:

```go
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/rvt/ -run TestExtractSingleCodeBlock`
Expected: FAIL — `Extract` undefined.

- [ ] **Step 3: Write minimal implementation**

Add to `server/internal/rvt/rvt.go` (add `"strings"` to the import block, which becomes `import ( "sort"; "strings" )`):

```go
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
		mapping = append(mapping, Segment{VirtOff: b.Len(), SrcOff: codeStart, Len: len(region)})
		b.WriteString(region)
		b.WriteByte('\n')

		if rel < 0 {
			break
		}
		i = codeEnd + 2
	}

	b.WriteString(nsSuffix)
	return Document{Script: b.String(), Mapping: mapping}
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/rvt/ -run TestExtract -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add server/internal/rvt/rvt.go server/internal/rvt/rvt_test.go
git commit -m "feat(rvt): Extract code blocks into stitched ::request script"
```

---

## Task 3: `<?= … ?>` output regions carry references

**Files:**
- Modify: `server/internal/rvt/rvt_test.go`

The implementation from Task 2 already handles `<?=` (it skips the `=`). This task adds the test that pins the behavior.

- [ ] **Step 1: Write the test**

Add to `server/internal/rvt/rvt_test.go`:

```go
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
```

- [ ] **Step 2: Run test to verify it passes**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/rvt/ -run TestExtractOutputShorthand -v`
Expected: PASS (behavior already implemented in Task 2).

- [ ] **Step 3: Commit**

```bash
git add server/internal/rvt/rvt_test.go
git commit -m "test(rvt): <?= ?> output regions carry variable references"
```

---

## Task 4: Control structures spanning blocks stitch into one script

**Files:**
- Modify: `server/internal/rvt/rvt_test.go`

- [ ] **Step 1: Write the test**

Add to `server/internal/rvt/rvt_test.go`:

```go
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
```

- [ ] **Step 2: Run test to verify it passes**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/rvt/ -run TestExtractControlFlowSpansBlocks -v`
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add server/internal/rvt/rvt_test.go
git commit -m "test(rvt): control structures stitch across <? ?> blocks"
```

---

## Task 5: Tolerant edge cases (no tags, empty, unterminated, stray `?>`)

**Files:**
- Modify: `server/internal/rvt/rvt_test.go`

- [ ] **Step 1: Write the tests**

Add to `server/internal/rvt/rvt_test.go`:

```go
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
```

- [ ] **Step 2: Run test to verify it passes**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/rvt/ -v`
Expected: PASS (all `rvt` tests).

- [ ] **Step 3: Commit**

```bash
git add server/internal/rvt/rvt_test.go
git commit -m "test(rvt): tolerant handling of empty/no-tag/unterminated input"
```

---

## Done criteria for Plan B-01

- `go -C server vet ./internal/rvt/` clean; `go -C server test ./internal/rvt/` all pass.
- `rvt.Extract` produces a `::request`-wrapped stitched script from `<? ?>` / `<?= ?>` regions, dropping literals, joining regions with newlines so block-spanning control structures stay balanced.
- `Document.ToSource` / `ToVirtual` translate offsets both ways via binary search; `ToSource` returns -1 for wrapper/gap offsets, `ToVirtual` returns `ok=false` for literal regions.
- Extraction is tolerant: empty, tag-less, unterminated, and stray-`?>` inputs never panic and emit what they can.

**Documented limitations (carried to the design's §9):** a `?>` inside a TCL string literal terminates the region early (naive tag scan, matching Rivet's own first-`?>` behavior); reported positions are byte offsets (UTF-16 conversion happens in the LSP layer, Plan B-04).

**Next:** Plan B-02 wires `Extract` into the index — discover `*.rvt`, parse the stitched script, translate def/ref/namespace offsets back to `.rvt` coordinates, and store them in the workspace symbol table.
