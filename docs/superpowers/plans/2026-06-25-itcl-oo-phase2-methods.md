# Itcl OO — Phase 2 (Methods, Ivars, Inheritance) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve Itcl methods and instance variables *within a class* — goto-definition/references for a bare/`$this` method call and a `$ivar` use inside a method body, across inline `method` definitions, external `itcl::body`, and `inherit`-ed base classes.

**Architecture:** Introduce a `FrameClass` frame and a `currentClass` context threaded through the shared walkers (so an `itcl::class` body is a member-declaration scope and a `method` body is a proc-frame that knows its class). Index methods/ivars/`inherit` into a new per-class `ClassInfo` table. The resolver gains a class-member step (local → class member, walking `inherit` order → global).

**Tech Stack:** Go (server/), standard library. Tests via `go test -C server ./...`.

## Global Constraints

- Go module rooted at `server/`; run tests with `go test -C server ./...`.
- Bash: ONE command per call — no `&&`, `|`, `;`, `>>`, `$(...)`.
- Commit trailers (end every commit message with both lines):
  - `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
  - `Claude-Session: https://claude.ai/code/session_01CTr66PbFqDEiS6DXxVy8JV`
- Itcl only. May-reach / best-effort: never produce a *wrong* jump; under-resolution (returning nothing) is acceptable for dynamic cases.
- Precedence inside a method: proc-local (unchanged) → class member (current class, then `inherit` order) → existing namespace/global path. Locals shadow ivars/methods.
- MRO is simple `inherit`-order depth-first traversal (NOT C3).
- Builds on Phase 1: `DefClass` exists and is indexed; `itcl::class` emits a `DefClass` (do not change that).

## Background (post-Phase-1 code)

- `tcl/context.go`: `FrameKind { FrameNamespace, FrameProc }`; `ContextRef { Ref Reference; Namespace string; Frame FrameKind; Scope int }`.
- `tcl/bodies.go`: `childBodies(c Command, base int, ns string, frame FrameKind, scope int) []bodyScope`; `bodyScope { Inner string; Base int; NS string; Frame FrameKind; Scope int }`. Today `itcl::class … {body}` is recursed via the default trailing-braced heuristic (so a class `variable` is wrongly emitted as a `DefNamespaceVar` — this phase fixes that).
- `tcl/defs.go`: `Definition { Kind DefKind; Name, Namespace string; NameStart, NameEnd, Scope int; Origin string }`; `emitDefs` emits `DefClass` for `itcl::class`.
- `index/index.go`: `defsByName map[string][]Location`; `ClassInfo` does not exist yet.
- `resolve/resolve.go`: `commandCandidates`, `variableCandidates`, `localAt`, `Definition`, `References`.

## File Structure

- **Modify** `server/internal/tcl/context.go` — add `FrameClass`; add `Class string` to `ContextRef`.
- **Modify** `server/internal/tcl/bodies.go` — add `Class string` to `bodyScope`; recognize `itcl::class` (FrameClass scope) and `method`/`constructor`/`destructor` (proc-frame carrying the class); thread `class` through `childBodies`.
- **Modify** `server/internal/tcl/defs.go` — add `Class string` to `Definition`; add `DefMethod`/`DefIvar` kinds; emit them in `FrameClass`; thread `class` through `walkDefs`/`emitDefs`/`recurseDefBodies`; emit external `itcl::body` methods.
- **Modify** `server/internal/tcl/refs.go` — thread `class` through `walkScript`/`recurseBodies` onto `ContextRef.Class`.
- **Modify** `server/internal/tcl/nsdecl.go` — record `inherit` per class (or add a small `FileClasses` analog).
- **Modify** `server/internal/source/source.go` — pass-through for the new class-aware outputs (`.rvt` already routed through here).
- **Modify** `server/internal/index/index.go` — build a `ClassInfo` class table.
- **Modify** `server/internal/resolve/resolve.go` — class-member resolution + MRO for methods and ivars.
- Tests alongside each (`*_test.go`).

---

### Task 1: `FrameClass` + `currentClass` plumbing (no member emission yet)

**Files:**
- Modify: `server/internal/tcl/context.go`, `server/internal/tcl/bodies.go`, `server/internal/tcl/defs.go`, `server/internal/tcl/refs.go`
- Test: `server/internal/tcl/bodies_test.go` (or `defs_test.go`)

**Interfaces:**
- Produces: `FrameClass FrameKind`; `bodyScope.Class string`; `Definition.Class string`; `ContextRef.Class string`. `childBodies` returns a `FrameClass` body (with `Class = <class FQ>`) for `itcl::class NAME {body}`, and a `FrameProc` body with `Class = <class FQ>` for `method`/`constructor`/`destructor` inside a class. `Class` is `""` everywhere else (no behavior change for non-class code).

**Why one task:** this is the cohesive context-plumbing change; it emits no members yet (Task 2 does), so it must be behavior-neutral for existing code — the gate is "existing tests still pass AND a class body now reports `FrameClass`."

- [ ] **Step 1: Write the failing test**

```go
func TestChildBodiesItclClassFrame(t *testing.T) {
	src := "itcl::class ::C {\n  method m {} { puts hi }\n}"
	cmds := Parse(src)
	var classBody *bodyScope
	for _, c := range cmds {
		for _, b := range childBodies(c, 0, "::", FrameNamespace, 0, "") {
			bb := b
			classBody = &bb
		}
	}
	if classBody == nil || classBody.Frame != FrameClass || classBody.Class != "::C" {
		t.Fatalf("itcl::class body should be FrameClass with Class ::C, got %#v", classBody)
	}
}
```

(Note: `childBodies` gains a trailing `class string` parameter — the test passes `""` at the top level.)

- [ ] **Step 2: Run to verify it fails**

Run: `go test -C server ./internal/tcl/ -run TestChildBodiesItclClassFrame -v`
Expected: FAIL — `FrameClass` undefined / `childBodies` arity / `bodyScope.Class` missing.

- [ ] **Step 3: Implement the plumbing**

`context.go`: add `FrameClass` to the `FrameKind` const block (append last) and `Class string` to `ContextRef`.

```go
const (
	FrameNamespace FrameKind = iota
	FrameProc
	FrameClass // an itcl::class body (member-declaration scope)
)
```

`bodies.go`: add `Class string` to `bodyScope`; add a `class string` parameter to `childBodies` (thread it as the enclosing class). Add cases BEFORE the default:

```go
	case (isCmd(w, "itcl::class") || isCmd(w, "::itcl::class")) && len(w) >= 3 && w[len(w)-1].Kind == WordBraced:
		inner, innerBase := bracedInner(w[len(w)-1], base)
		return []bodyScope{{Inner: inner, Base: innerBase, NS: ns, Frame: FrameClass, Scope: 0, Class: qualifyName(w[1].Text, ns)}}
	case frame == FrameClass && (isCmd(w, "method") || isCmd(w, "constructor") || isCmd(w, "destructor")) && w[len(w)-1].Kind == WordBraced:
		inner, innerBase := bracedInner(w[len(w)-1], base)
		return []bodyScope{{Inner: inner, Base: innerBase, NS: ns, Frame: FrameProc, Scope: innerBase, Class: class}}
```

Every existing `childBodies` return must set `Class: class` (carry the enclosing class through control-flow/proc/namespace bodies unchanged). Update the two callers (`recurseDefBodies` in defs.go, `recurseBodies` in refs.go) to pass and propagate `b.Class`.

`defs.go`: add `Class string` to `Definition`; thread `class` through `walkDefs`/`emitDefs`/`recurseDefBodies` (every emitted `Definition` sets `Class: class`; top-level calls pass `""`). `FileDefs` calls `walkDefs(Parse(src), 0, "::", FrameNamespace, 0, "", &out)`.

`refs.go`: thread `class` through `walkScript`/`recurseBodies`, setting `ContextRef.Class = class`.

- [ ] **Step 4: Run to verify it passes + no regressions**

Run: `go test -C server ./internal/tcl/ -run TestChildBodiesItclClassFrame -v`
Then: `go test -C server ./...`
Expected: PASS (new test) and ALL packages still green (plumbing is behavior-neutral; `Class` defaults to `""`).

- [ ] **Step 5: Commit**

```
git add server/internal/tcl/
git commit -m "feat(tcl): FrameClass + currentClass plumbing for itcl"
```
(Append the two required trailers.)

---

### Task 2: Emit `DefMethod` / `DefIvar` for class members

**Files:**
- Modify: `server/internal/tcl/defs.go`
- Test: `server/internal/tcl/defs_test.go`

**Interfaces:**
- Consumes: `FrameClass`, `Definition.Class`.
- Produces: `DefMethod`, `DefIvar` kinds. In a `FrameClass` body, `method`/`constructor`/`destructor NAME …` → `DefMethod{Name: NAME, Class: <classFQ>}`; `variable`/`common NAME …` → `DefIvar{Name: NAME, Class: <classFQ>}`. The class-body `variable` must NOT also emit `DefNamespaceVar` (fixes the Phase-1 carry-forward).

- [ ] **Step 1: Write the failing test**

```go
func TestFileDefsItclMembers(t *testing.T) {
	src := "itcl::class ::C {\n  variable count 0\n  method field {name} { return $name }\n}"
	var method, ivar *Definition
	for _, d := range FileDefs(src) {
		dd := d
		if d.Kind == DefMethod && d.Name == "field" {
			method = &dd
		}
		if d.Kind == DefIvar && d.Name == "count" {
			ivar = &dd
		}
		if d.Kind == DefNamespaceVar && d.Name == "::C::count" {
			t.Fatalf("class variable must not be a DefNamespaceVar: %#v", d)
		}
	}
	if method == nil || method.Class != "::C" {
		t.Fatalf("want DefMethod field on ::C, got %#v", FileDefs(src))
	}
	if ivar == nil || ivar.Class != "::C" {
		t.Fatalf("want DefIvar count on ::C, got %#v", FileDefs(src))
	}
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `go test -C server ./internal/tcl/ -run TestFileDefsItclMembers -v`
Expected: FAIL — `DefMethod`/`DefIvar` undefined; class `variable` currently mis-emits.

- [ ] **Step 3: Implement**

`defs.go`: add `DefMethod`, `DefIvar` to the `DefKind` const block (append last). In `emitDefs`, add a branch for `frame == FrameClass` that handles members, and GUARD the existing `variable`/`set`/`namespace-var` rules so they do not fire in `FrameClass`:

```go
	if frame == FrameClass {
		switch {
		case (isCmd(w, "method") || isCmd(w, "constructor") || isCmd(w, "destructor") || isCmd(w, "proc")) && len(w) >= 2 && isPlainName(w[1]):
			*out = append(*out, Definition{Kind: DefMethod, Name: w[1].Text, Class: class,
				Namespace: ns, NameStart: base + w[1].Start, NameEnd: base + w[1].End, Scope: scope})
		case (isCmd(w, "variable") || isCmd(w, "common")) && len(w) >= 2 && isPlainName(w[1]):
			*out = append(*out, Definition{Kind: DefIvar, Name: w[1].Text, Class: class,
				Namespace: ns, NameStart: base + w[1].Start, NameEnd: base + w[1].End, Scope: scope})
		}
		return // class-body declarations handled; skip the namespace/proc rules below
	}
```

Place this `if frame == FrameClass { … return }` near the top of `emitDefs` (after computing `w`), so the existing `variable`→DefNamespaceVar and other rules never run for class bodies. (`constructor`/`destructor` have no name word — emit them with a synthetic name from `w[0].Text`: handle them as `Name: w[0].Text` when `w[1]` is the args list. Refine: for `constructor`/`destructor`, use `w[0].Text` as the method name and the name range as `w[0]`.)

- [ ] **Step 4: Run to verify it passes + no regressions**

Run: `go test -C server ./internal/tcl/ -run TestFileDefsItcl -v`
Then: `go test -C server ./...`
Expected: PASS. Existing namespace-var tests unaffected (the guard only changes `FrameClass`).

- [ ] **Step 5: Commit**

```
git add server/internal/tcl/defs.go server/internal/tcl/defs_test.go
git commit -m "feat(tcl): emit DefMethod/DefIvar for itcl class members"
```
(Append the two required trailers.)

---

### Task 3: External `itcl::body` method definitions

**Files:**
- Modify: `server/internal/tcl/defs.go`
- Test: `server/internal/tcl/defs_test.go`

**Interfaces:**
- Produces: a top-level `itcl::body ::C::m {args} {body}` (or `::itcl::body`) emits `DefMethod{Name: "m", Class: "::C"}`, with the name range on the `m` segment of `::C::m`.

- [ ] **Step 1: Write the failing test**

```go
func TestFileDefsItclBody(t *testing.T) {
	src := "itcl::body ::C::field {name} { return $name }"
	var m *Definition
	for _, d := range FileDefs(src) {
		dd := d
		if d.Kind == DefMethod && d.Name == "field" {
			m = &dd
		}
	}
	if m == nil || m.Class != "::C" {
		t.Fatalf("want external DefMethod field on ::C, got %#v", FileDefs(src))
	}
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `go test -C server ./internal/tcl/ -run TestFileDefsItclBody -v`
Expected: FAIL — `itcl::body` unrecognized.

- [ ] **Step 3: Implement**

In `emitDefs` (at namespace frame), add: recognize `itcl::body`/`::itcl::body` with a qualified `Class::method` second word, split on the last `::`, emit a `DefMethod` whose `Class` is the prefix (qualified to FQ) and `Name`/range is the last segment. Reuse `splitLastSegment`-style logic (or `strings.LastIndex(text, "::")`); set the name range to cover just the method segment within `w[1]`.

```go
	if (isCmd(w, "itcl::body") || isCmd(w, "::itcl::body")) && len(w) >= 2 && isPlainName(w[1]) {
		full := w[1].Text
		if i := strings.LastIndex(full, "::"); i > 0 {
			classFQ := qualifyName(full[:i], ns)
			methodSeg := full[i+2:]
			segStart := w[1].Start + i + 2
			*out = append(*out, Definition{Kind: DefMethod, Name: methodSeg, Class: classFQ,
				Namespace: ns, NameStart: base + segStart, NameEnd: base + w[1].End, Scope: scope})
		}
	}
```

(The `itcl::body` *body* is recursed as a method frame via a `childBodies` case mirroring Task 1's `method` case — add `itcl::body` to a body-recursion case so calls/locals inside it resolve with `Class = classFQ`. Test that separately if needed; the def emission above is the gated deliverable.)

- [ ] **Step 4: Run to verify it passes + no regressions**

Run: `go test -C server ./internal/tcl/ -run TestFileDefsItcl -v`
Then: `go test -C server ./...`
Expected: PASS.

- [ ] **Step 5: Commit**

```
git add server/internal/tcl/defs.go server/internal/tcl/defs_test.go
git commit -m "feat(tcl): index external itcl::body method definitions"
```
(Append the two required trailers.)

---

### Task 4: Build the `ClassInfo` class table (members + inherit)

**Files:**
- Create: `server/internal/tcl/classdecl.go` (a `FileClasses` analog to `nsdecl.go`'s `FileNamespaces`, returning `inherit` edges per class)
- Modify: `server/internal/source/source.go` (pass-through `Classes(path, content)` like `Namespaces`), `server/internal/index/index.go`
- Test: `server/internal/tcl/classdecl_test.go`, `server/internal/index/index_test.go`

**Interfaces:**
- Produces:
  - `tcl.FileClasses(src) map[string][]string` — classFQ → list of FQ base classes (from `inherit Base1 Base2`, qualified via `qualifyName`), mirroring how `FileNamespaces` records `namespace path`.
  - `source.Classes(path, content) map[string][]string` — `.tcl` passes through; `.rvt` runs on the stitched script.
  - `index.ClassInfo { DefSites, Methods map[string][]Location, Ivars map[string][]Location, Inherit []string }` and `Index.Class(fq string) *ClassInfo`. Built in `IndexFile` by collecting `DefClass`/`DefMethod`/`DefIvar` (keyed by their `Class` field, merging inline + external sites) and `FileClasses` inherit edges. Stored per-class, merged across files; dropped on `RemoveFile` like `defsByName`.

- [ ] **Step 1: Write the failing test**

```go
// index_test.go
func TestIndexClassTable(t *testing.T) {
	ix := New()
	ix.IndexFile("c.tcl",
		"itcl::class ::Base { method common {} {} }\n"+
			"itcl::class ::Derived {\n  inherit ::Base\n  method field {} {}\n}")
	ci := ix.Class("::Derived")
	if ci == nil {
		t.Fatal("::Derived not in class table")
	}
	if len(ci.Methods["field"]) != 1 {
		t.Fatalf("Derived.field method site missing: %#v", ci.Methods)
	}
	if len(ci.Inherit) != 1 || ci.Inherit[0] != "::Base" {
		t.Fatalf("Derived inherit = %#v, want [::Base]", ci.Inherit)
	}
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `go test -C server ./internal/index/ -run TestIndexClassTable -v`
Expected: FAIL — `Class`/`ClassInfo` undefined.

- [ ] **Step 3: Implement**

`classdecl.go`: walk like `nsdecl.go`, recording in a `FrameClass` body any `inherit` command's bare base names (qualified) into `map[currentClass][]baseFQ`. Reuse `childBodies` recursion (threading `class`), so a class declared anywhere is found.

`source.go`: add `Classes(path, content)` mirroring `Namespaces`.

`index.go`: add `classes map[string]*ClassInfo` to `Index`; in `IndexFile`, after collecting defs, for each `DefClass`/`DefMethod`/`DefIvar` (which now carry `Class`/FQ), populate the class entry — `DefClass.Name` is the class FQ (DefSites), `DefMethod`/`DefIvar` go under `classes[d.Class].Methods[d.Name]`/`.Ivars[d.Name]`. Merge `source.Classes` inherit edges. Track per-file class keys for `RemoveFile`. Add `func (ix *Index) Class(fq string) *ClassInfo`.

- [ ] **Step 4: Run + no regressions**

Run: `go test -C server ./internal/index/ -run TestIndexClassTable -v`
Then: `go test -C server ./...`
Expected: PASS.

- [ ] **Step 5: Commit**

```
git add server/internal/tcl/classdecl.go server/internal/tcl/classdecl_test.go server/internal/source/source.go server/internal/index/index.go server/internal/index/index_test.go
git commit -m "feat(index): itcl class table with members and inherit edges"
```
(Append the two required trailers.)

---

### Task 5: Resolve intra-class method calls (+ MRO)

**Files:**
- Modify: `server/internal/resolve/resolve.go`
- Test: `server/internal/resolve/resolve_test.go`

**Interfaces:**
- Consumes: `Index.Class`, `ContextRef.Class`, the existing `Definition`/`References` flow.
- Produces: `methodInClass(classFQ, name) []Location` — looks up `name` in `Class(classFQ).Methods`, else walks `Inherit` depth-first (first match wins, guard against cycles with a visited set). goto-definition for a bare command (or `$this method`) inside a method body (`ref.Frame == FrameProc && ref.Class != ""`) resolves to `methodInClass(ref.Class, name)` BEFORE the global command path; proc-locals still win first.

- [ ] **Step 1: Write the failing test**

```go
func TestDefinitionIntraClassMethod(t *testing.T) {
	ix := index.New()
	ix.IndexFile("c.tcl",
		"itcl::class ::Base { method helper {} {} }\n"+
			"itcl::class ::Derived {\n  inherit ::Base\n"+
			"  method run {} {\n    helper\n    field\n  }\n"+
			"  method field {} {}\n}")
	r := New(ix)
	src := ix.Source("c.tcl")
	// bare `field` call inside run() -> Derived's own method
	offField := strings.Index(src, "    field") + len("    ")
	if locs := r.Definition("c.tcl", src, offField); len(locs) != 1 || locs[0].Name != "field" {
		t.Fatalf("intra-class method `field` = %#v", locs)
	}
	// bare `helper` call -> inherited from ::Base (MRO)
	offHelper := strings.Index(src, "    helper") + len("    ")
	if locs := r.Definition("c.tcl", src, offHelper); len(locs) != 1 || locs[0].Name != "helper" {
		t.Fatalf("inherited method `helper` = %#v", locs)
	}
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `go test -C server ./internal/resolve/ -run TestDefinitionIntraClassMethod -v`
Expected: FAIL — bare method calls currently resolve via the global command path (no class member step), returning nothing.

- [ ] **Step 3: Implement**

Add `methodInClass(classFQ, name string) []index.Location` (recursive MRO over `Inherit`, visited-set guarded). In `Definition`, after the `localAt` check and before the existing command-candidate loop, if the ref at the offset is a command with `ref.Class != "" && ref.Frame == tcl.FrameProc`, try `methodInClass(ref.Class, name)`; if non-empty, return it. Handle `$this method` by recognizing the `$this <method>` shape (head is `$this`) and resolving `<method>` the same way. (Threading `ref.Class` requires `refAt` to return the `ContextRef` including `Class`, which Task 1 populated.)

- [ ] **Step 4: Run + no regressions**

Run: `go test -C server ./internal/resolve/ -run TestDefinitionIntraClassMethod -v`
Then: `go test -C server ./...`
Expected: PASS.

- [ ] **Step 5: Commit**

```
git add server/internal/resolve/resolve.go server/internal/resolve/resolve_test.go
git commit -m "feat(resolve): intra-class itcl method resolution with MRO"
```
(Append the two required trailers.)

---

### Task 6: Resolve instance-variable uses (+ MRO)

**Files:**
- Modify: `server/internal/resolve/resolve.go`
- Test: `server/internal/resolve/resolve_test.go`

**Interfaces:**
- Consumes: `Index.Class`, `ContextRef.Class`, `methodInClass`'s MRO pattern.
- Produces: `ivarInClass(classFQ, name) []Location` (same MRO walk over `Ivars`). A bare variable use `$v` inside a method body that is NOT a proc-local resolves to `ivarInClass(ref.Class, name)`.

- [ ] **Step 1: Write the failing test**

```go
func TestDefinitionIvar(t *testing.T) {
	ix := index.New()
	ix.IndexFile("c.tcl",
		"itcl::class ::Base { variable shared 0 }\n"+
			"itcl::class ::Derived {\n  inherit ::Base\n  variable count 0\n"+
			"  method run {} {\n    return [list $count $shared]\n  }\n}")
	r := New(ix)
	src := ix.Source("c.tcl")
	offCount := strings.Index(src, "$count") + 1
	if locs := r.Definition("c.tcl", src, offCount); len(locs) != 1 || locs[0].Name != "count" {
		t.Fatalf("ivar $count = %#v", locs)
	}
	offShared := strings.Index(src, "$shared") + 1
	if locs := r.Definition("c.tcl", src, offShared); len(locs) != 1 || locs[0].Name != "shared" {
		t.Fatalf("inherited ivar $shared = %#v", locs)
	}
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `go test -C server ./internal/resolve/ -run TestDefinitionIvar -v`
Expected: FAIL — ivar uses currently fall through proc-local (none) to nothing.

- [ ] **Step 3: Implement**

Add `ivarInClass`. In the variable-resolution path of `Definition` (the `localDefinition`/`variableCandidates` area), when the use is a bare variable inside a method body (`ref.Frame == tcl.FrameProc && ref.Class != ""`) and the proc-local reaching/first-binding lookup yields nothing, try `ivarInClass(ref.Class, name)`. Keep precedence: proc-local first, then ivar.

- [ ] **Step 4: Run + no regressions**

Run: `go test -C server ./internal/resolve/ -run TestDefinitionIvar -v`
Then: `go test -C server ./...`
Expected: PASS.

- [ ] **Step 5: Commit**

```
git add server/internal/resolve/resolve.go server/internal/resolve/resolve_test.go
git commit -m "feat(resolve): itcl instance-variable resolution with MRO"
```
(Append the two required trailers.)

---

## Self-Review (completed by author)

**Spec coverage (Phase 2 / Tier 2 slice):** `FrameClass`/`currentClass` plumbing (Task 1); `DefMethod`/`DefIvar` from inline class bodies (Task 2) and external `itcl::body` (Task 3); the `ClassInfo` table with `inherit` edges (Task 4); intra-class method resolution + MRO (Task 5) and ivar resolution + MRO (Task 6). Find-references for methods/ivars rides the same `targetFQ`/scan machinery once a member resolves, but its best-effort cross-receiver completeness is Phase 3 (`$obj method`) territory; basic in-class member find-refs follows from the resolution path.

**Placeholder scan:** none — each task carries a concrete failing test and key implementation code. Task 1 and Task 4 are the larger cross-cutting tasks (threading + index table); their gate is a concrete test plus a full-suite no-regression run.

**Type consistency:** `Class string` is added uniformly to `bodyScope`/`Definition`/`ContextRef`; `DefMethod`/`DefIvar`/`FrameClass` are referenced identically across tasks; `ClassInfo`/`Index.Class`/`methodInClass`/`ivarInClass` names are used consistently between the index and resolve tasks.

**Known scope notes:** `constructor`/`destructor` lack a name word — emitted under their keyword as the method name (Task 2). `inherit`-order MRO (not C3) and best-effort find-refs are per the spec's non-goals. The Phase-1 carry-forward (class `variable` mis-emitted as `DefNamespaceVar`) is fixed by Task 2's `FrameClass` guard.

