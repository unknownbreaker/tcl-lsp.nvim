# Phase B — Plan 03: resolver routes through the source seam + page-local `::request`

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make goto-definition and find-references work in `.rvt` files: resolve the live file through the `source` seam (so `.rvt` parses), resolve cross-file `.rvt`↔`.tcl`, and scope template-top-level `::request::*` symbols to a single page.

**Architecture:** The resolver's live-file parse switches from `tcl.File*` to `source.*` (threading the file path so `.rvt` is extracted). A `lookupScoped` helper restricts `::request::*` lookups to the requesting file; find-references additionally scans only the requesting file when the target is page-local, since a per-request symbol has no references in other pages. All `.tcl` behavior is unchanged (the seam is a passthrough and `::request` never appears in `.tcl`).

**Tech Stack:** Go 1.23+ (local 1.26.4), `testing`.

**Design basis:** `docs/plans/2026-06-08-phase-b-rvt-design.md` §3, §4.3; depends on Plan B-02 (`source.Defs`/`source.Refs`, `.rvt` stored in source coords).

---

## File structure

- Modify: `server/internal/resolve/resolve.go` — `source` seam in the live path; `file` threaded into `refAt`/`refFQ`; `lookupScoped`; page-local find-references.
- Modify: `server/internal/resolve/resolve_test.go`

All test commands assume module directory `server/`.

---

## Task 1: Route the live-file parse through the `source` seam (enables `.rvt` + cross-file)

**Files:**
- Modify: `server/internal/resolve/resolve.go`
- Modify: `server/internal/resolve/resolve_test.go`

This task makes the resolver parse the live document via `source.*` (so a `.rvt` live file is extracted, not read as raw TCL) and threads the file path into the helpers that parse it. Behavior for `.tcl` is unchanged; cross-file `.rvt`→`.tcl` resolution starts working. Page-locality is added in Task 2.

- [ ] **Step 1: Write the failing test**

Add to `server/internal/resolve/resolve_test.go`:

```go
func TestRVTToTCLCrossFile(t *testing.T) {
	ix := index.New()
	ix.IndexFile("lib.tcl", "namespace eval ::lib { proc helper {} {} }")
	page := "<h1><?= [::lib::helper] ?></h1>"
	ix.IndexFile("page.rvt", page)
	r := New(ix)

	// goto-definition from the .rvt call jumps into lib.tcl.
	off := strings.Index(page, "helper")
	locs := r.Definition("page.rvt", page, off)
	if len(locs) != 1 || locs[0].File != "lib.tcl" || locs[0].Name != "::lib::helper" {
		t.Fatalf("rvt->tcl goto-def = %#v", locs)
	}

	// find-references from the lib.tcl definition includes the .rvt call site.
	libSrc := ix.Source("lib.tcl")
	defOff := strings.Index(libSrc, "helper")
	got := r.References("lib.tcl", libSrc, defOff)
	var inRVT bool
	for _, l := range got {
		if l.File == "page.rvt" {
			inRVT = true
		}
	}
	if !inRVT {
		t.Fatalf("expected page.rvt among references to ::lib::helper: %#v", got)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/resolve/ -run TestRVTToTCLCrossFile`
Expected: FAIL — `r.Definition("page.rvt", page, off)` parses the raw `.rvt` as TCL and finds no `::lib::helper` reference at the cursor.

- [ ] **Step 3: Write minimal implementation**

In `server/internal/resolve/resolve.go`:

(a) Add the import (in the existing import block, alongside `index` and `tcl`):

```go
	"github.com/unknownbreaker/tcl-lsp/internal/source"
```

(b) Replace `refAt` (free function) so it takes `file` and uses the seam:

```go
// refAt returns the innermost reference whose byte range contains offset, parsing
// src through the source seam so .rvt content is extracted to its stitched script
// and reported in source coordinates.
func refAt(file, src string, offset int) *tcl.ContextRef {
	refs := source.Refs(file, src)
	var best *tcl.ContextRef
	for i := range refs {
		rg := refs[i].Ref
		if offset >= rg.Start && offset < rg.End {
			if best == nil || (rg.End-rg.Start) < (best.Ref.End-best.Ref.Start) {
				best = &refs[i]
			}
		}
	}
	return best
}
```

(c) In `Definition`, update the `refAt` call:

```go
	ref := refAt(file, src, offset)
```

(d) Replace `refFQ` so it takes `file` (still using plain `Lookup` for now — page-locality is Task 2):

```go
// refFQ resolves a reference to the fully-qualified name it binds to, using the
// same first-match precedence as goto-definition. file is the document the ref
// lives in (used for page-local scoping in lookups). If no candidate is defined,
// the primary candidate is used so undefined references still group together.
func (r *Resolver) refFQ(ref *tcl.ContextRef, file string) string {
	cands := r.candidates(ref)
	for _, name := range cands {
		if len(r.ix.Lookup(name)) > 0 {
			return name
		}
	}
	if len(cands) > 0 {
		return cands[0]
	}
	return ""
}
```

(e) In `targetFQ`, use the seam and pass `file`:

```go
func (r *Resolver) targetFQ(file, src string, offset int) string {
	for _, d := range source.Defs(file, src) {
		if (d.Kind == tcl.DefProc || d.Kind == tcl.DefNamespaceVar) &&
			offset >= d.NameStart && offset < d.NameEnd {
			return d.Name
		}
	}
	if ref := refAt(file, src, offset); ref != nil {
		return r.refFQ(ref, file)
	}
	return ""
}
```

(f) In `References`, the current-file scan uses the seam, and the per-file scan passes `f` to `refFQ`:

```go
	scan := func(f string, refs []tcl.ContextRef) {
		for i := range refs {
			if r.refFQ(&refs[i], f) == target {
				out = append(out, index.Location{
					File: f, Name: target, Kind: targetKind,
					NameStart: refs[i].Ref.Start, NameEnd: refs[i].Ref.End,
				})
			}
		}
	}

	scan(file, source.Refs(file, src)) // current file: parse the live source via the seam
	for _, f := range r.ix.Files() {
		if f == file {
			continue
		}
		scan(f, r.ix.FileRefs(f))
	}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/resolve/ -v`
Expected: PASS — including all pre-existing `.tcl` resolver tests (`source.*` is a passthrough for `.tcl`).

- [ ] **Step 5: Commit**

```bash
git add server/internal/resolve/resolve.go server/internal/resolve/resolve_test.go
git commit -m "feat(resolve): resolve .rvt via the source seam; cross-file rvt<->tcl"
```

---

## Task 2: Page-local `::request` symbols

**Files:**
- Modify: `server/internal/resolve/resolve.go`
- Modify: `server/internal/resolve/resolve_test.go`

- [ ] **Step 1: Write the failing test**

Add to `server/internal/resolve/resolve_test.go`:

```go
func TestRVTProcPageLocalDefinition(t *testing.T) {
	ix := index.New()
	src := "<? proc greet {} {} ?>\n<? greet ?>"
	ix.IndexFile("page.rvt", src)
	r := New(ix)

	off := strings.LastIndex(src, "greet") // the call
	locs := r.Definition("page.rvt", src, off)
	if len(locs) != 1 || locs[0].Name != "::request::greet" || locs[0].File != "page.rvt" {
		t.Fatalf("page-local goto-def = %#v", locs)
	}
}

func TestRVTPageLocalNoCrossPageMatch(t *testing.T) {
	ix := index.New()
	a := "<? proc render {} {} ?>\n<? render ?>"
	b := "<? proc render {} {} ?>\n<? render ?>"
	ix.IndexFile("a.rvt", a)
	ix.IndexFile("b.rvt", b)
	r := New(ix)

	// goto-def from a.rvt's call resolves only to a.rvt's definition.
	off := strings.LastIndex(a, "render")
	locs := r.Definition("a.rvt", a, off)
	if len(locs) != 1 || locs[0].File != "a.rvt" {
		t.Fatalf("expected only a.rvt def, got %#v", locs)
	}

	// find-references from a.rvt must not include b.rvt's identically-named helper.
	refs := r.References("a.rvt", a, off)
	for _, l := range refs {
		if l.File == "b.rvt" {
			t.Fatalf("page-local references leaked into b.rvt: %#v", refs)
		}
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/resolve/ -run TestRVTPageLocal`
Expected: FAIL — `TestRVTProcPageLocalDefinition` returns both pages' `::request::greet`/`render` (plain `Lookup` is workspace-wide), and references leak across pages.

- [ ] **Step 3: Write minimal implementation**

In `server/internal/resolve/resolve.go`:

(a) Add the `lookupScoped` helper (place it just above `refFQ`):

```go
// lookupScoped returns the definition sites of a fully-qualified name. A
// page-local name (under ::request) resolves only to definitions in file, because
// the per-request namespace is recreated per page and not shared across templates.
// All other names resolve workspace-wide.
func (r *Resolver) lookupScoped(name, file string) []index.Location {
	locs := r.ix.Lookup(name)
	if !strings.HasPrefix(name, "::request::") {
		return locs
	}
	var kept []index.Location
	for _, l := range locs {
		if l.File == file {
			kept = append(kept, l)
		}
	}
	return kept
}
```

(b) In `Definition`, use `lookupScoped`:

```go
	for _, name := range r.candidates(ref) {
		if locs := r.lookupScoped(name, file); len(locs) > 0 {
			return locs
		}
	}
```

(c) In `refFQ`, use `lookupScoped`:

```go
	for _, name := range cands {
		if len(r.lookupScoped(name, file)) > 0 {
			return name
		}
	}
```

(d) In `Declarations`, use `lookupScoped`:

```go
func (r *Resolver) Declarations(file, src string, offset int) []index.Location {
	target := r.targetFQ(file, src, offset)
	if target == "" {
		return nil
	}
	return r.lookupScoped(target, file)
}
```

(e) In `References`, scope `targetKind` and skip other files when the target is page-local. Replace the `targetKind` block and the scan-loop tail:

```go
	var targetKind tcl.DefKind
	if defs := r.lookupScoped(target, file); len(defs) > 0 {
		targetKind = defs[0].Kind
	}

	// A page-local (::request) symbol has references only within its own page, so
	// scanning other files would risk matching an identically-named page-local
	// helper elsewhere (their primary candidate name collides).
	pageLocal := strings.HasPrefix(target, "::request::")

	var out []index.Location
	scan := func(f string, refs []tcl.ContextRef) {
		for i := range refs {
			if r.refFQ(&refs[i], f) == target {
				out = append(out, index.Location{
					File: f, Name: target, Kind: targetKind,
					NameStart: refs[i].Ref.Start, NameEnd: refs[i].Ref.End,
				})
			}
		}
	}

	scan(file, source.Refs(file, src))
	if !pageLocal {
		for _, f := range r.ix.Files() {
			if f == file {
				continue
			}
			scan(f, r.ix.FileRefs(f))
		}
	}
	return out
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/resolve/ -v`
Expected: PASS (page-local tests, cross-file test from Task 1, and all `.tcl` tests).

- [ ] **Step 5: Commit**

```bash
git add server/internal/resolve/resolve.go server/internal/resolve/resolve_test.go
git commit -m "feat(resolve): page-local scoping for ::request template symbols"
```

---

## Done criteria for Plan B-03

- `go -C server vet ./...` clean; `go -C server test ./...` all pass.
- goto-definition and find-references work for `.rvt`: a template-top-level proc/var resolves within its page; an unqualified or qualified reference to a `.tcl` namespace/global symbol resolves cross-file; references from a `.tcl` definition include `.rvt` call sites.
- `::request::*` symbols are page-local: identically-named helpers in different templates never cross-match in goto-def or find-references.
- `.tcl` resolution is unchanged.

**Next:** Plan B-04 verifies the whole feature end-to-end over stdio with a synthetic `.rvt` fixture (no server logic change is required — the server already works in source coordinates) and updates the docs to mark Phase B shipped.
