# Phase B — Plan 02: index integration (.rvt discovery + source-coordinate symbols)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Index `.rvt` files into the same workspace symbol table as `.tcl`, with every definition and reference stored in `.rvt` source coordinates, so goto-def/ref point into the template.

**Architecture:** A new pure `source` seam dispatches on file extension: `.tcl` passes through to `tcl.File*`; `.rvt` runs `rvt.Extract`, parses the stitched `::request` script, and translates each def/ref offset back to `.rvt` via `Document.ToSource` (dropping wrapper-synthetic symbols that map to -1). The `index` package calls the seam instead of `tcl.File*` directly, and `IndexDir` walks `*.rvt` too. Because translation happens here, all downstream code keeps working in source coordinates.

**Tech Stack:** Go 1.23+ (local 1.26.4), `testing`.

**Design basis:** `docs/plans/2026-06-08-phase-b-rvt-design.md` §4.2, §5; depends on Plan B-01 (`rvt.Extract`, `Document.ToSource`).

---

## File structure

- Create: `server/internal/source/source.go` — `IsRVT`, `Defs`, `Refs`, `Namespaces` (extension dispatch + `.rvt` offset translation).
- Create: `server/internal/source/source_test.go`
- Modify: `server/internal/index/index.go` — `IndexFile` calls the seam; `IndexDir` walks `*.rvt`.
- Modify: `server/internal/index/index_test.go`

Import graph (no cycles): `source → {tcl, rvt}`; `index → {tcl, source}`; later `resolve → {index, tcl, source}`.

All test commands assume module directory `server/` (module path `github.com/unknownbreaker/tcl-lsp`).

---

## Task 1: The `source` seam — extension dispatch + `.rvt` translation

**Files:**
- Create: `server/internal/source/source.go`
- Create: `server/internal/source/source_test.go`

- [ ] **Step 1: Write the failing test**

Create `server/internal/source/source_test.go`:

```go
package source

import (
	"strings"
	"testing"

	"github.com/unknownbreaker/tcl-lsp/internal/tcl"
)

func TestDefsTCLPassthrough(t *testing.T) {
	defs := Defs("x.tcl", "proc greet {} {}")
	if len(defs) == 0 || defs[0].Name != "::greet" {
		t.Fatalf("tcl passthrough = %#v", defs)
	}
}

func TestDefsRVTTranslatesToSource(t *testing.T) {
	src := "<? proc greet {} {} ?>"
	want := strings.Index(src, "greet")
	var found bool
	for _, d := range Defs("page.rvt", src) {
		if d.Name == "::request::greet" {
			found = true
			if d.NameStart != want {
				t.Fatalf("greet NameStart = %d, want %d (.rvt coord)", d.NameStart, want)
			}
		}
	}
	if !found {
		t.Fatalf("::request::greet not found in %#v", Defs("page.rvt", src))
	}
}

func TestRefsRVTTranslatesAndDropsWrapper(t *testing.T) {
	src := "<? proc greet {} { hello } ?>"
	want := strings.Index(src, "hello")
	refs := Refs("page.rvt", src)

	var found bool
	for _, r := range refs {
		if r.Ref.Kind == tcl.RefCommand && r.Ref.Name == "hello" {
			found = true
			if r.Ref.Start != want {
				t.Fatalf("hello ref Start = %d, want %d (.rvt coord)", r.Ref.Start, want)
			}
		}
		// The synthetic `namespace eval ::request {` wrapper must not leak through.
		if r.Ref.Name == "namespace" {
			t.Fatalf("synthetic wrapper ref leaked: %#v", r)
		}
	}
	if !found {
		t.Fatalf("hello ref not found in %#v", refs)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/source/`
Expected: FAIL — package/`Defs`/`Refs` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `server/internal/source/source.go`:

```go
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/source/ -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add server/internal/source/
git commit -m "feat(source): extension-dispatched defs/refs in source coordinates"
```

---

## Task 2: `IndexFile` uses the seam (store `.rvt` symbols)

**Files:**
- Modify: `server/internal/index/index.go`
- Modify: `server/internal/index/index_test.go`

- [ ] **Step 1: Write the failing test**

Add to `server/internal/index/index_test.go` (ensure `strings` is imported in that file):

```go
func TestIndexFileRVTStoresRequestSymbol(t *testing.T) {
	ix := New()
	src := "<h1><? proc greet {} {} ?></h1>"
	ix.IndexFile("page.rvt", src)

	locs := ix.Lookup("::request::greet")
	if len(locs) != 1 {
		t.Fatalf("expected 1 def for ::request::greet, got %#v", locs)
	}
	if locs[0].File != "page.rvt" {
		t.Fatalf("file = %q, want page.rvt", locs[0].File)
	}
	if want := strings.Index(src, "greet"); locs[0].NameStart != want {
		t.Fatalf("NameStart = %d, want %d (.rvt coord)", locs[0].NameStart, want)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/index/ -run TestIndexFileRVT`
Expected: FAIL — `.rvt` parsed as raw TCL today, so `::request::greet` is not produced.

- [ ] **Step 3: Write minimal implementation**

In `server/internal/index/index.go`, add the import (in the existing import block):

```go
	"github.com/unknownbreaker/tcl-lsp/internal/source"
```

Then replace the three `tcl.File*` calls in `IndexFile` with the seam. Change the body of `IndexFile` from:

```go
	ix.fileNS[path] = tcl.FileNamespaces(content)
	if refs := tcl.FileRefs(content); len(refs) > 0 {
		ix.fileRefs[path] = refs
	}
	for _, d := range tcl.FileDefs(content) {
```

to:

```go
	ix.fileNS[path] = source.Namespaces(path, content)
	if refs := source.Refs(path, content); len(refs) > 0 {
		ix.fileRefs[path] = refs
	}
	for _, d := range source.Defs(path, content) {
```

(The `tcl` import stays — `Location.Kind`, `tcl.DefProc`, etc. still reference it.)

- [ ] **Step 4: Run test to verify it passes**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/index/ -v`
Expected: PASS (all index tests, including the existing `.tcl` ones — `source.*` is a passthrough for `.tcl`).

- [ ] **Step 5: Commit**

```bash
git add server/internal/index/index.go server/internal/index/index_test.go
git commit -m "feat(index): index .rvt content via the source seam"
```

---

## Task 3: `IndexDir` walks `*.rvt`

**Files:**
- Modify: `server/internal/index/index.go`
- Modify: `server/internal/index/index_test.go`

- [ ] **Step 1: Write the failing test**

Add to `server/internal/index/index_test.go` (ensure `os` and `path/filepath` are imported):

```go
func TestIndexDirIncludesRVT(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "page.rvt"), []byte("<? proc onlyinrvt {} {} ?>"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "lib.tcl"), []byte("namespace eval ::lib { proc helper {} {} }"), 0o644); err != nil {
		t.Fatal(err)
	}

	ix := New()
	if err := ix.IndexDir(dir); err != nil {
		t.Fatal(err)
	}
	if len(ix.Lookup("::request::onlyinrvt")) != 1 {
		t.Fatalf("IndexDir did not index the .rvt file")
	}
	if len(ix.Lookup("::lib::helper")) != 1 {
		t.Fatalf("IndexDir regressed .tcl indexing")
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/index/ -run TestIndexDirIncludesRVT`
Expected: FAIL — `.rvt` is skipped by the `.tcl`-only suffix check.

- [ ] **Step 3: Write minimal implementation**

In `server/internal/index/index.go`, in `IndexDir`, change:

```go
		if !strings.HasSuffix(p, ".tcl") {
			return nil
		}
```

to:

```go
		if !strings.HasSuffix(p, ".tcl") && !strings.HasSuffix(p, ".rvt") {
			return nil
		}
```

Also update the `IndexDir` doc comment's first line from `walks root and indexes every *.tcl file` to `walks root and indexes every *.tcl and *.rvt file`.

- [ ] **Step 4: Run test to verify it passes**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/index/ -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add server/internal/index/index.go server/internal/index/index_test.go
git commit -m "feat(index): IndexDir discovers .rvt templates"
```

---

## Done criteria for Plan B-02

- `go -C server vet ./...` clean; `go -C server test ./internal/source/ ./internal/index/` all pass.
- `.rvt` files are indexed into the workspace symbol table; their definitions/references are stored in `.rvt` source coordinates (translated from the stitched script; wrapper-synthetic symbols dropped).
- `.tcl` indexing is unchanged (the seam is a passthrough for `.tcl`).
- `IndexDir` discovers both `*.tcl` and `*.rvt`.

**Note:** cross-file resolution from a `.rvt` to a `.tcl` namespace definition is not yet exercised here — that lands in Plan B-03 once the resolver consumes the same seam and applies the page-local rule for `::request`.

**Next:** Plan B-03 routes the resolver's live-file parse through `source.Refs`/`source.Defs` and adds the page-local restriction so `::request::*` symbols resolve within a single template.
