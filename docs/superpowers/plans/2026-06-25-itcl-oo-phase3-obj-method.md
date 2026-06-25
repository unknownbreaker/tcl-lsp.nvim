# Itcl OO — Phase 3 (`$obj method` Type-Tracking) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Interface dependency:** This plan consumes interfaces produced by **Phase 2**
> (`Index.Class`, `ClassInfo`, `methodInClass`, `ContextRef.Class`) and the
> reaching engine (`tcl.ReachingAt` / `source.Reaching`). Confirm those exact
> signatures against the code after Phase 2 lands — adjust the test offsets /
> helper names here if Phase 2's names differ.

**Goal:** Resolve the dominant idiom `$display field` — a method call on an object variable — by tracking the variable's Itcl class from its local instantiation and resolving the method on that class.

**Architecture:** A `classOf` query layers on the reaching engine: get the reaching definition(s) of the receiver variable, pattern-match Itcl instantiation on the right-hand side (`set v [::C #auto]`), and return the class set. The resolver recognizes the `$var <method>` command shape and resolves `<method>` on each class via Phase 2's `methodInClass` (+ MRO).

**Tech Stack:** Go (server/), standard library. Tests via `go test -C server ./...`.

## Global Constraints

- Go module rooted at `server/`; tests via `go test -C server ./...`.
- Bash: ONE command per call — no `&&`, `|`, `;`, `>>`, `$(...)`.
- Commit trailers (both lines, end of every commit message):
  - `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
  - `Claude-Session: https://claude.ai/code/session_01CTr66PbFqDEiS6DXxVy8JV`
- May-reach: union across reaching defs (a receiver assigned `::A` in one branch and `::B` in another resolves to methods on both); NEVER a wrong jump — when no class is known, resolve nothing.
- Heuristic boundary (documented): only LOCALLY-instantiated receivers get a type. Params, cross-method ivars, and factory returns stay unresolved.

## Instantiation forms `classOf` must recognize (RHS of `set v …`)

- `set v [::C #auto]`, `set v [::C #auto -opt val …]`
- `set v [::C new …]` / `set v [::C create name …]` (also valid in Itcl 4)
- `set v [::C objName …]`
- The bracketless command form is rare for capture; focus on the `[…]` command-substitution RHS whose first word is a known/qualified class name.

## File Structure

- **Modify** `server/internal/tcl/reaching.go` (or new `server/internal/tcl/classof.go`) — `ClassOf` over the reaching results.
- **Modify** `server/internal/source/source.go` — `.rvt` pass-through (`ClassOf`).
- **Modify** `server/internal/resolve/resolve.go` — `$var <method>` shape detection + resolution via `methodInClass`.
- Tests alongside.

---

### Task 1: `ClassOf` — instantiation type-tracking over reaching

**Files:**
- Create: `server/internal/tcl/classof.go`
- Test: `server/internal/tcl/classof_test.go`

**Interfaces:**
- Consumes: the reaching engine (`ReachingAt`/the proc-locating + reaching-def machinery in `reaching.go`), `Parse`, `Command`, instantiation-shape detection.
- Produces: `ClassOf(src string, receiverUseOff int) []string` — the set of FQ Itcl class names the receiver variable may hold at that use, or nil. For each reaching definition of the receiver var, inspect its `set v <RHS>` command; if `<RHS>` is a command substitution whose head word is a qualified class name, collect that class. Union, deduped.

- [ ] **Step 1: Write the failing test**

```go
func TestClassOfLocalInstantiation(t *testing.T) {
	src := "proc f {} {\n  set d [::STDisplay #auto]\n  $d field isbn\n}"
	off := strings.LastIndex(src, "$d") + 1 // the receiver use in `$d field`
	got := ClassOf(src, off)
	if len(got) != 1 || got[0] != "::STDisplay" {
		t.Fatalf("ClassOf = %#v, want [::STDisplay]", got)
	}
}

func TestClassOfUnknownIsNil(t *testing.T) {
	// receiver is a parameter -> no local instantiation -> no type
	src := "proc f {obj} {\n  $obj field\n}"
	off := strings.LastIndex(src, "$obj") + 1
	if got := ClassOf(src, off); got != nil {
		t.Fatalf("ClassOf on a param should be nil, got %#v", got)
	}
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `go test -C server ./internal/tcl/ -run TestClassOf -v`
Expected: FAIL — `ClassOf` undefined.

- [ ] **Step 3: Implement**

In `classof.go`: reuse the reaching machinery to get the reaching definition name-ranges of the variable used at `receiverUseOff` (the same proc-locating + reaching path `ReachingAt` uses). For each reaching def, locate the command whose binding token covers that range (re-walk the enclosing proc's commands; a binding is `set NAME VALUE` / `incr` / etc.), and for a `set` whose value word is a `[ … ]` command substitution, parse the inner command and take its head word; if that head is a qualified class name (contains `::` or resolves to a class — for Phase 3, accept a leading-`::` qualified head, and let the resolver confirm it's a class), collect it. Return the deduped union, or nil if none matched.

Implementation note: factor a small helper from `reaching.go` (or call `ReachingAt` and then map each returned `NameStart/NameEnd` back to its command by re-parsing the proc). Keep `ClassOf` in its own file; it is a *consumer* of reaching, not a change to it.

- [ ] **Step 4: Run + no regressions**

Run: `go test -C server ./internal/tcl/ -run TestClassOf -v`
Then: `go test -C server ./...`
Expected: PASS.

- [ ] **Step 5: Commit**

```
git add server/internal/tcl/classof.go server/internal/tcl/classof_test.go
git commit -m "feat(tcl): ClassOf itcl type-tracking over reaching defs"
```
(Append the two required trailers.)

---

### Task 2: `.rvt` seam for `ClassOf`

**Files:**
- Modify: `server/internal/source/source.go`
- Test: `server/internal/source/classof_test.go`

**Interfaces:**
- Produces: `source.ClassOf(path, content string, offset int) []string` — `.tcl` passes through to `tcl.ClassOf`; `.rvt` maps the offset into the stitched script via `rvt.Extract`/`ToVirtual`, runs `tcl.ClassOf`, returns the class set (class names need no coordinate translation — they are plain strings).

- [ ] **Step 1: Write the failing test**

```go
func TestClassOfRVT(t *testing.T) {
	content := "<?\nset d [::STDisplay #auto]\n$d field\n?>"
	off := strings.LastIndex(content, "$d") + 1
	got := ClassOf("page.rvt", content, off)
	if len(got) != 1 || got[0] != "::STDisplay" {
		t.Fatalf("rvt ClassOf = %#v, want [::STDisplay]", got)
	}
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `go test -C server ./internal/source/ -run TestClassOfRVT -v`
Expected: FAIL — `source.ClassOf` undefined.

- [ ] **Step 3: Implement**

Mirror `source.Reaching`: non-`.rvt` calls `tcl.ClassOf(content, offset)`; `.rvt` does `doc := rvt.Extract(content); vOff, ok := doc.ToVirtual(offset); if !ok { return nil }; return tcl.ClassOf(doc.Script, vOff)`.

- [ ] **Step 4: Run + no regressions**

Run: `go test -C server ./internal/source/ -run TestClassOfRVT -v`
Then: `go test -C server ./...`
Expected: PASS.

- [ ] **Step 5: Commit**

```
git add server/internal/source/source.go server/internal/source/classof_test.go
git commit -m "feat(source): .rvt seam for ClassOf"
```
(Append the two required trailers.)

---

### Task 3: Resolve `$obj method` (shape detection + resolution)

**Files:**
- Modify: `server/internal/resolve/resolve.go`
- Test: `server/internal/resolve/resolve_test.go`

**Interfaces:**
- Consumes: `source.ClassOf`, Phase 2's `methodInClass(classFQ, name)`, the command-shape info from the parser.
- Produces: goto-definition on the method word of a `$var <method> …` command (and inside `[$var <method> …]`) resolves to `methodInClass` on each class in `ClassOf(file, src, receiverOffset)` (+ MRO), unioned. Cursor on the method word (second word) is the trigger. When `ClassOf` is empty, return nothing (no wrong jump).

- [ ] **Step 1: Write the failing test**

```go
func TestDefinitionObjMethod(t *testing.T) {
	ix := index.New()
	ix.IndexFile("disp.tcl", "itcl::class ::STDisplay {\n  method field {name} {}\n}")
	r := New(ix)
	src := "proc f {} {\n  set d [::STDisplay #auto]\n  $d field isbn\n}"
	off := strings.Index(src, "field isbn") // cursor on the method word
	locs := r.Definition("use.tcl", src, off)
	if len(locs) != 1 || locs[0].File != "disp.tcl" || locs[0].Name != "field" {
		t.Fatalf("$obj method goto-def = %#v", locs)
	}
}

func TestDefinitionObjMethodUnknownReceiver(t *testing.T) {
	ix := index.New()
	ix.IndexFile("disp.tcl", "itcl::class ::STDisplay { method field {} {} }")
	r := New(ix)
	src := "proc f {obj} {\n  $obj field\n}" // obj is a param -> unknown type
	off := strings.Index(src, "field")
	if locs := r.Definition("use.tcl", src, off); len(locs) != 0 {
		t.Fatalf("unknown receiver should not resolve: %#v", locs)
	}
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `go test -C server ./internal/resolve/ -run TestDefinitionObjMethod -v`
Expected: FAIL — the method word of `$d field` is an unresolved bareword today.

- [ ] **Step 3: Implement**

In `Definition`, add a step: detect when `offset` falls on the SECOND word of a command whose FIRST word is a lone variable substitution (`$var`) — i.e. the `$var <method>` shape (also when nested in a `[ … ]` substitution). Recover the receiver variable's use offset (the `$var` head). Call `source.ClassOf(file, src, receiverOff)`; for each class, `methodInClass(classFQ, methodWord)`; return the deduped union. If empty, return nil (no fallback that could mis-jump). Implement shape detection from the parsed command words (head word is a single `$var` with no other text; the cursor word is the next bareword) — reuse the parser's word ranges rather than re-scanning bytes.

- [ ] **Step 4: Run + no regressions**

Run: `go test -C server ./internal/resolve/ -run TestDefinitionObjMethod -v`
Then: `go test -C server ./...`
Expected: PASS.

- [ ] **Step 5: Commit**

```
git add server/internal/resolve/resolve.go server/internal/resolve/resolve_test.go
git commit -m "feat(resolve): resolve \$obj method via ClassOf type-tracking"
```
(Append the two required trailers.)

---

## Self-Review (completed by author)

**Spec coverage (Phase 3 / Tier 3 slice):** `ClassOf` type-tracking over reaching (Task 1) with the `.rvt` seam (Task 2); `$obj method` shape detection + resolution via `methodInClass` (Task 3). The heuristic boundary (param/cross-method/factory receivers stay unresolved) is pinned by the `…UnknownReceiver` tests.

**Placeholder scan:** none — concrete tests and approach for each task. The one soft spot is Task 1's "locate the command for a reaching def-site," which depends on the reaching module's internals as they exist after the reaching feature shipped; the implementer wires it against the real `reaching.go` (the interface-dependency note at the top calls this out).

**Type consistency:** `ClassOf(src, off) []string` (tcl) and `source.ClassOf(path, content, off) []string` are used consistently; `methodInClass` is consumed exactly as Phase 2 produces it. `[]string` of FQ class names is the single currency between `ClassOf` and the resolver.

**Carried risk:** the `$var <method>` shape must not misfire on `$cmd arg` where `$cmd` holds a proc name — handled by returning nothing when `ClassOf` finds no class (no wrong jump), per the spec's stated risk.

**find-references for methods (best-effort):** deferred — once `$obj method` resolution exists, method find-references can scan `$var <method>` sites whose `ClassOf` matches the target class; worth a follow-up task or a Phase-3 addendum, noted in `docs/BACKLOG.md` rather than forced here.
