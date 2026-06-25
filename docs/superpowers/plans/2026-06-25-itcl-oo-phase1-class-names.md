# Itcl OO — Phase 1 (Class Names) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Itcl class names resolvable — goto-definition and find-references on an `itcl::class` name and its instantiation sites (`[::STDisplay #auto]`, `::STDisplay obj`).

**Architecture:** Add a `DefClass` definition kind emitted for `itcl::class NAME { … }`, index it in the existing fully-qualified symbol table (so the current command-resolution path finds it), and accept it as a goto-def/references target. Deliberately does NOT touch `childBodies` or class-member handling — class bodies keep their current (pre-existing) recursion; members (methods/ivars) and the `FrameClass` context arrive in Phase 2.

**Tech Stack:** Go (server/), standard library. Tests are Go table tests via `go test -C server ./...`.

## Global Constraints

- Go module rooted at `server/`; run tests with `go test -C server ./...` (no top-level Go module).
- Bash tool rule: ONE command per call — no `&&`, `|`, `;`, `>>`, `$(...)`.
- Commit message trailers (end every commit message with these two lines):
  - `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
  - `Claude-Session: https://claude.ai/code/session_01CTr66PbFqDEiS6DXxVy8JV`
- Itcl only (no TclOO this phase). Additive — must not change resolution of existing procs/namespace-vars/locals/references.
- Phase 1 is class NAMES only: do not index methods/ivars, do not add `FrameClass`, do not modify `bodies.go`.

## File Structure

- **Modify** `server/internal/tcl/defs.go` — add `DefClass` kind; emit it in `emitDefs` for `itcl::class`/`::itcl::class`.
- **Test** `server/internal/tcl/defs_test.go` — `DefClass` emission.
- **Modify** `server/internal/index/index.go` — index `DefClass` in the FQ table (one line in `IndexFile`).
- **Test** `server/internal/index/index_test.go` — class is looked up.
- **Modify** `server/internal/resolve/resolve.go` — accept `DefClass` in `targetFQ` (find-refs / cursor-on-definition).
- **Test** `server/internal/resolve/resolve_test.go` — goto-def to class + find-references.

---

### Task 1: `DefClass` kind + emit for `itcl::class`

**Files:**
- Modify: `server/internal/tcl/defs.go`
- Test: `server/internal/tcl/defs_test.go`

**Interfaces:**
- Produces: `DefClass tcl.DefKind`; `FileDefs` now emits a `Definition{Kind: DefClass, Name: <FQ class name>, NameStart/NameEnd: <class-name token>}` for `itcl::class NAME { … }` and `::itcl::class NAME { … }`.

- [ ] **Step 1: Write the failing test**

```go
func TestFileDefsItclClass(t *testing.T) {
	src := "itcl::class ::STDisplay {\n  method field {} {}\n}"
	var got *Definition
	for _, d := range FileDefs(src) {
		if d.Kind == DefClass {
			dd := d
			got = &dd
		}
	}
	if got == nil || got.Name != "::STDisplay" {
		t.Fatalf("want DefClass ::STDisplay, got %#v", FileDefs(src))
	}
	if src[got.NameStart:got.NameEnd] != "::STDisplay" {
		t.Fatalf("name range slices %q, want ::STDisplay", src[got.NameStart:got.NameEnd])
	}
}

func TestFileDefsItclClassQualifiedHead(t *testing.T) {
	// `::itcl::class` (leading ::) must also be recognized.
	defs := FileDefs("::itcl::class ::Foo {}")
	found := false
	for _, d := range defs {
		if d.Kind == DefClass && d.Name == "::Foo" {
			found = true
		}
	}
	if !found {
		t.Fatalf("::itcl::class not recognized: %#v", defs)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test -C server ./internal/tcl/ -run TestFileDefsItclClass -v`
Expected: FAIL — `DefClass` undefined.

- [ ] **Step 3: Write minimal implementation**

In `defs.go`, add `DefClass` to the `DefKind` const block (append after `DefGlobalLink` to avoid renumbering existing kinds):

```go
const (
	DefProc         DefKind = iota // a proc (command) definition
	DefNamespaceVar                // a namespace variable
	DefLocal                       // a proc-local variable
	DefGlobalLink                  // a `global name` link
	DefClass                       // an itcl::class definition
)
```

In `emitDefs`, add (alongside the other `isCmd` rules):

```go
	if (isCmd(w, "itcl::class") || isCmd(w, "::itcl::class")) && len(w) >= 3 && isPlainName(w[1]) {
		*out = append(*out, Definition{
			Kind:      DefClass,
			Name:      qualifyName(w[1].Text, ns),
			Namespace: ns,
			NameStart: base + w[1].Start,
			NameEnd:   base + w[1].End,
			Scope:     scope,
		})
	}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test -C server ./internal/tcl/ -run TestFileDefsItclClass -v`
Expected: PASS (both).

- [ ] **Step 5: Commit**

```
git add server/internal/tcl/defs.go server/internal/tcl/defs_test.go
git commit -m "feat(tcl): emit DefClass for itcl::class definitions"
```
(Append the two required trailers.)

---

### Task 2: Index `DefClass` in the FQ table

**Files:**
- Modify: `server/internal/index/index.go`
- Test: `server/internal/index/index_test.go`

**Interfaces:**
- Consumes: `tcl.DefClass`.
- Produces: `Index.Lookup("::STDisplay")` returns the class's `Location` (Kind `DefClass`).

- [ ] **Step 1: Write the failing test**

```go
func TestIndexClassLookup(t *testing.T) {
	ix := New()
	ix.IndexFile("disp.tcl", "itcl::class ::STDisplay {\n  method field {} {}\n}")
	locs := ix.Lookup("::STDisplay")
	if len(locs) != 1 || locs[0].Kind != tcl.DefClass || locs[0].File != "disp.tcl" {
		t.Fatalf("want DefClass ::STDisplay indexed, got %#v", locs)
	}
}
```

(Ensure `index_test.go` imports `github.com/unknownbreaker/tcl-lsp/internal/tcl`.)

- [ ] **Step 2: Run test to verify it fails**

Run: `go test -C server ./internal/index/ -run TestIndexClassLookup -v`
Expected: FAIL — `Lookup` returns nil (DefClass not indexed).

- [ ] **Step 3: Write minimal implementation**

In `index.go`, in `IndexFile`, the loop currently skips everything except procs and namespace vars. Add `DefClass`:

```go
	for _, d := range source.Defs(path, content) {
		if d.Kind != tcl.DefProc && d.Kind != tcl.DefNamespaceVar && d.Kind != tcl.DefClass {
			continue
		}
		ix.defsByName[d.Name] = append(ix.defsByName[d.Name], Location{
			File: path, Name: d.Name, Kind: d.Kind, NameStart: d.NameStart, NameEnd: d.NameEnd,
		})
		ix.fileDefs[path] = append(ix.fileDefs[path], d.Name)
	}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test -C server ./internal/index/ -run TestIndexClassLookup -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```
git add server/internal/index/index.go server/internal/index/index_test.go
git commit -m "feat(index): index itcl class definitions in the FQ table"
```
(Append the two required trailers.)

---

### Task 3: Resolve class names — goto-definition + find-references

**Files:**
- Modify: `server/internal/resolve/resolve.go`
- Test: `server/internal/resolve/resolve_test.go`

**Interfaces:**
- Consumes: `tcl.DefClass`, `Index.Lookup`, the existing command-candidate resolution.
- Produces: goto-definition on a class instantiation resolves to the class; find-references from the class definition includes instantiation sites. `targetFQ` recognizes a `DefClass` name range.

- [ ] **Step 1: Write the failing test**

```go
func TestDefinitionItclClassInstantiation(t *testing.T) {
	ix := index.New()
	ix.IndexFile("disp.tcl", "itcl::class ::STDisplay {\n  method field {} {}\n}")
	r := New(ix)
	src := "set d [::STDisplay #auto]"
	off := strings.Index(src, "::STDisplay") // cursor on the class in the instantiation
	locs := r.Definition("use.tcl", src, off)
	if len(locs) != 1 || locs[0].File != "disp.tcl" || locs[0].Name != "::STDisplay" {
		t.Fatalf("instantiation goto-def = %#v", locs)
	}
}

func TestReferencesItclClass(t *testing.T) {
	ix := index.New()
	ix.IndexFile("disp.tcl", "itcl::class ::STDisplay {\n  method field {} {}\n}")
	ix.IndexFile("a.tcl", "set d [::STDisplay #auto]")
	r := New(ix)
	defSrc := ix.Source("disp.tcl")
	defOff := strings.Index(defSrc, "::STDisplay") // cursor on the class name at its definition
	refs := r.References("disp.tcl", defSrc, defOff)
	var inA bool
	for _, l := range refs {
		if l.File == "a.tcl" {
			inA = true
		}
	}
	if !inA {
		t.Fatalf("class references should include the a.tcl instantiation: %#v", refs)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test -C server ./internal/resolve/ -run "TestDefinitionItclClass|TestReferencesItclClass" -v`
Expected: `TestReferencesItclClass` FAILS — `targetFQ` doesn't recognize the `DefClass` name range, so find-references from the definition returns nothing. (`TestDefinitionItclClassInstantiation` may already PASS via the command path once Task 2 indexed the class — that's fine; it pins the behavior.)

- [ ] **Step 3: Write minimal implementation**

In `resolve.go`, `targetFQ` currently matches `DefProc`/`DefNamespaceVar` name ranges. Add `DefClass`:

```go
	for _, d := range source.Defs(file, src) {
		if (d.Kind == tcl.DefProc || d.Kind == tcl.DefNamespaceVar || d.Kind == tcl.DefClass) &&
			offset >= d.NameStart && offset < d.NameEnd {
			return d.Name
		}
	}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test -C server ./internal/resolve/ -run "TestDefinitionItclClass|TestReferencesItclClass" -v`
Expected: PASS (both).

- [ ] **Step 5: Run the full suite (no regressions)**

Run: `go test -C server ./...`
Expected: PASS (all packages). The change is additive; existing proc/namespace/local/reference tests must be unaffected.

- [ ] **Step 6: Commit**

```
git add server/internal/resolve/resolve.go server/internal/resolve/resolve_test.go
git commit -m "feat(resolve): goto-def and references for itcl class names"
```
(Append the two required trailers.)

---

## Self-Review (completed by author)

**Spec coverage (Phase 1 / Tier 1 slice):** `DefClass` emitted (Task 1) and indexed in the FQ table so the existing command path resolves it (Task 2); goto-def to a class and find-references on a class name (Task 3). Deliberately excludes methods/ivars/`inherit`, `FrameClass`, and `$obj method` — those are Phase 2/3 per the spec's phasing.

**Placeholder scan:** none — every step carries concrete code and exact commands.

**Type consistency:** `DefClass` is referenced identically across tasks (`tcl.DefClass`); the `IndexFile` filter, `targetFQ` condition, and `Definition` fields (`Kind`/`Name`/`NameStart`/`NameEnd`) match the existing structs read from the current code.

**Known carried-forward (Phase 2, not this plan):** class-body member declarations still flow through the existing default body recursion — e.g. a class `variable` is still emitted as a `DefNamespaceVar` (a pre-existing quirk, not a regression). Phase 2 introduces `FrameClass` and fixes member handling. Phase 1 must not regress existing behavior, which the full-suite run in Task 3 verifies.
