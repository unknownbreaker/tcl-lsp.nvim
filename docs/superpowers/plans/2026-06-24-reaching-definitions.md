# Reaching-Definitions for Proc-Local goto-definition — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the positional "first/nearest binding" answer for proc-local variable goto-definition with intraprocedural reaching-definitions, so a `$x` use jumps to the assignment(s) that can actually reach it (possibly several at a control-flow merge).

**Architecture:** A pure structured-dataflow analyzer lives in package `tcl` (file `reaching.go`) — *not* a separate `internal/dataflow` package, because it needs `tcl`'s unexported internals (`Command`, `scriptBodies`, `ifBodies`, the binding rules). It analyzes one proc body on demand and returns the reaching bindings for a given use offset. A thin `source` wrapper handles `.rvt` coordinate translation. `resolve.localDefinition` consumes it and falls back to today's behavior when it returns nothing.

**Tech Stack:** Go (server/), standard library only. Tests are Go table tests. Build/test via `go test -C server ./...`.

## Global Constraints

- Go module rooted at `server/`; run tests with `go test -C server ./...` (the repo has no top-level Go module).
- Bash tool rule: ONE command per call — no `&&`, `|`, `;`, `>>`, `$(...)`. Use separate calls.
- Commit message trailers (end every commit message with these two lines):
  - `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`
  - `Claude-Session: https://claude.ai/code/session_01CTr66PbFqDEiS6DXxVy8JV`
- Analysis is **intraprocedural** and **may-reach** (over-approximate; never drop a real reaching def).
- find-references and global/upvar origin-chasing behavior must remain unchanged.
- No index/workspace changes — the analyzer is request-time, single-proc.

## File Structure

- **Create** `server/internal/tcl/reaching.go` — the analyzer: locate enclosing proc, structured reaching-defs, public `ReachingAt`.
- **Create** `server/internal/tcl/reaching_test.go` — analyzer unit tests (control-flow fixtures).
- **Modify** `server/internal/source/source.go` — add `Reaching(path, content, offset)` wrapper for `.rvt` coordinate translation.
- **Create** `server/internal/source/reaching_test.go` — `.rvt` translation test.
- **Modify** `server/internal/resolve/resolve.go` — thread the cursor offset into `localDefinition`; consume reaching set; fall back.
- **Modify** `server/internal/resolve/resolve_test.go` — integration cases for context-sensitive goto-def.

---

### Task 1: Analyzer foundation — locate the proc + straight-line reaching

**Files:**
- Create: `server/internal/tcl/reaching.go`
- Test: `server/internal/tcl/reaching_test.go`

**Interfaces:**
- Consumes: `Parse`, `Command`, `Word`, `childBodies`, `bodyScope`, `CommandRefs`, `Reference`, `RefVariable`, `FrameKind`/`FrameProc`/`FrameNamespace`, `Definition`/`DefLocal`, `arrayBaseName`, `isCmd`, `emitVarListNames`-style logic — all in package `tcl`.
- Produces: `ReachingAt(src string, useOff int) (defs []Definition, ok bool)`; helper `localBindings(c Command, base int) []Definition`; types `reachSet` and `analyzer`. Later tasks extend `analyzer.command` with control-flow rules.

- [ ] **Step 1: Write the failing test**

```go
package tcl

import "testing"

// reach is a test helper: returns the reaching-def name ranges (as "start-end"
// strings) for the variable use whose text starts at marker `mark` in src.
func reachAtMarker(t *testing.T, src, mark string) []Definition {
	t.Helper()
	off := indexOf(t, src, mark) + 1 // +1 to land inside `$x` on the name
	defs, ok := ReachingAt(src, off)
	if !ok {
		t.Fatalf("ReachingAt(%q) ok=false", mark)
	}
	return defs
}

func indexOf(t *testing.T, src, sub string) int {
	t.Helper()
	i := indexLast(src, sub)
	if i < 0 {
		t.Fatalf("substring %q not found", sub)
	}
	return i
}

func TestReachingStraightLineLatestAssignment(t *testing.T) {
	src := "proc f {} {\n  set x 1\n  set x 2\n  puts $x\n}"
	defs := reachAtMarker(t, src, "$x")
	if len(defs) != 1 {
		t.Fatalf("want 1 reaching def, got %d: %#v", len(defs), defs)
	}
	// It must be the SECOND `set x`, not the first.
	wantStart := indexLast(src, "set x 2") + len("set ")
	if defs[0].NameStart != wantStart {
		t.Fatalf("reaching def at %d, want the `set x 2` binding at %d", defs[0].NameStart, wantStart)
	}
}

func TestReachingParamReaches(t *testing.T) {
	src := "proc f {a} {\n  puts $a\n}"
	defs := reachAtMarker(t, src, "$a")
	if len(defs) != 1 || defs[0].Name != "a" {
		t.Fatalf("param should reach: %#v", defs)
	}
}
```

Add a tiny `indexLast(s, sub string) int` helper in the test file (returns `strings.LastIndex`).

- [ ] **Step 2: Run test to verify it fails**

Run: `go test -C server ./internal/tcl/ -run TestReaching -v`
Expected: FAIL — `ReachingAt` undefined.

- [ ] **Step 3: Write minimal implementation**

```go
package tcl

// ReachingAt returns the local-variable bindings that may reach the use at byte
// offset useOff in src, as Definition values (Kind DefLocal/DefGlobalLink, with
// NameStart/NameEnd on the binding's name token and Origin for links). ok is
// false when useOff is not on a proc-local variable use or no in-proc binding
// reaches it. Intraprocedural and may-reach (over-approximate, never drops a real
// reaching def). Later tasks add control-flow precision; this task handles a
// straight-line proc body.
func ReachingAt(src string, useOff int) (defs []Definition, ok bool) {
	inner, base, found := enclosingProc(Parse(src), 0, "::", FrameNamespace, 0, useOff)
	if !found {
		return nil, false
	}
	a := &analyzer{useOff: useOff}
	entry := reachSet{}
	addParamDefs(inner, base, entry) // proc params reach from entry
	a.seq(Parse(inner), base, entry)
	if !a.found {
		return nil, false
	}
	return a.answer, true
}

// enclosingProc returns the interior text and absolute base of the innermost proc
// body containing useOff. A proc-introducing body is FrameProc with Scope==Base
// (childBodies sets a proc body's Scope to its own interior offset; control-flow
// bodies keep the enclosing scope).
func enclosingProc(cmds []Command, base int, ns string, frame FrameKind, scope, useOff int) (string, int, bool) {
	for _, c := range cmds {
		for _, b := range childBodies(c, base, ns, frame, scope) {
			if useOff < b.Base || useOff >= b.Base+len(b.Inner) {
				continue
			}
			if in2, base2, ok2 := enclosingProc(Parse(b.Inner), b.Base, b.NS, b.Frame, b.Scope, useOff); ok2 {
				return in2, base2, true
			}
			if b.Frame == FrameProc && b.Scope == b.Base {
				return b.Inner, b.Base, true
			}
		}
	}
	return "", 0, false
}

// reachSet maps a local variable name to the bindings that may currently reach
// this program point.
type reachSet map[string][]Definition

func (s reachSet) clone() reachSet {
	out := make(reachSet, len(s))
	for k, v := range s {
		cp := make([]Definition, len(v))
		copy(cp, v)
		out[k] = cp
	}
	return out
}

type analyzer struct {
	useOff int
	answer []Definition
	found  bool
}

// seq threads the reaching set left-to-right through a command sequence and
// returns the set at its end. (Control-flow live/stop handling is added in a
// later task; here every command continues.)
func (a *analyzer) seq(cmds []Command, base int, in reachSet) reachSet {
	cur := in
	for _, c := range cmds {
		cur = a.command(c, base, cur)
	}
	return cur
}

// command applies one command: record any variable use at useOff against the
// incoming set, then apply this command's bindings (kill prior, gen new).
func (a *analyzer) command(c Command, base int, in reachSet) reachSet {
	a.recordUses(c, base, in)
	binds := localBindings(c, base)
	if len(binds) == 0 {
		return in
	}
	out := in.clone()
	for _, d := range binds {
		out[d.Name] = []Definition{d} // straight-line: reassign kills+gens
	}
	return out
}

// recordUses snapshots the reaching set for the variable used at useOff (a
// $-substituted RefVariable in this command's own words).
func (a *analyzer) recordUses(c Command, base int, in reachSet) {
	if a.found {
		return
	}
	for _, r := range CommandRefs(c) {
		if r.Kind != RefVariable {
			continue
		}
		s, e := r.Start+base, r.End+base
		if a.useOff >= s && a.useOff < e {
			a.answer = append([]Definition(nil), in[r.Name]...)
			a.found = true
			return
		}
	}
}
```

Plus `localBindings(c Command, base int) []Definition` — a single-command version of the binding rules in `emitDefs`, returning `DefLocal`/`DefGlobalLink` for `set`/`incr`/`append`/`lappend` (via `arrayBaseName`), `variable`, `global` (with `globalOrigin`), `upvar` (with `upvarOrigin`), and `foreach`/`lmap`/`lassign`/`dict for` var lists. Reuse the exact helpers `emitDefs` uses; set `NameStart/NameEnd = base + word offset`, `Kind = DefLocal` (or `DefGlobalLink` for `global`), `Name = bare name`. And `addParamDefs(inner string, base int, into reachSet)` — parse the enclosing `proc`'s arg list is not available here, so params are seeded by the caller: instead, have `ReachingAt` find the proc command and call `emitProcParams`-style scanning. *Simplest:* in `enclosingProc`, also return the proc's args `Word`; seed params from it. Thread an extra return value (args `Word`, found via the `proc`/decorated-proc head) and feed `scanParams` into `entry` as `DefLocal`s at the entry set.

- [ ] **Step 4: Run test to verify it passes**

Run: `go test -C server ./internal/tcl/ -run TestReaching -v`
Expected: PASS (both cases).

- [ ] **Step 5: Commit**

```
git add server/internal/tcl/reaching.go server/internal/tcl/reaching_test.go
git commit -m "feat(tcl): reaching-defs foundation (locate proc + straight-line)"
```
(Append the two required trailers to the commit message.)

---

### Task 2: `if`/`elseif`/`else` join

**Files:**
- Modify: `server/internal/tcl/reaching.go`
- Test: `server/internal/tcl/reaching_test.go`

**Interfaces:**
- Consumes: `ifBodies`, `bracedInner`, `isCmd` (package `tcl`).
- Produces: `analyzer.analyzeIf`; helpers `joinAll([]reachSet) reachSet`, `hasElse([]Word) bool`. `command` now dispatches `if` to `analyzeIf`.

- [ ] **Step 1: Write the failing test**

```go
func TestReachingIfElseJoin(t *testing.T) {
	src := "proc f {} {\n  set x 1\n  if {$c} {\n    set x 2\n  } else {\n    set x 3\n  }\n  puts $x\n}"
	defs := reachAtMarker(t, src, "$x")
	if len(defs) != 2 { // both branches reassign; set x 1 is dead
		t.Fatalf("want 2 reaching defs (x2, x3), got %d: %#v", len(defs), defs)
	}
}

func TestReachingIfNoElseKeepsPrior(t *testing.T) {
	src := "proc f {} {\n  set x 1\n  if {$c} {\n    set x 2\n  }\n  puts $x\n}"
	defs := reachAtMarker(t, src, "$x")
	if len(defs) != 2 { // fall-through keeps x1; if-branch adds x2
		t.Fatalf("want 2 (x1 fall-through + x2), got %d: %#v", len(defs), defs)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test -C server ./internal/tcl/ -run TestReachingIf -v`
Expected: FAIL — `if` is currently treated as an opaque command (no body recursion), so the inner `set`s aren't seen and the join is wrong.

- [ ] **Step 3: Write minimal implementation**

In `command`, dispatch before the binding step:

```go
func (a *analyzer) command(c Command, base int, in reachSet) reachSet {
	a.recordUses(c, base, in)
	if isCmd(c.Words, "if") {
		return a.analyzeIf(c, base, in)
	}
	binds := localBindings(c, base)
	if len(binds) == 0 {
		return in
	}
	out := in.clone()
	for _, d := range binds {
		out[d.Name] = []Definition{d}
	}
	return out
}

func (a *analyzer) analyzeIf(c Command, base int, in reachSet) reachSet {
	var outs []reachSet
	for _, b := range ifBodies(c.Words) {
		inner, ibase := bracedInner(b, base)
		outs = append(outs, a.seq(Parse(inner), ibase, in.clone()))
	}
	if !hasElse(c.Words) {
		outs = append(outs, in) // no branch taken
	}
	return joinAll(outs)
}

func hasElse(w []Word) bool {
	for _, x := range w {
		if x.Kind == WordBare && x.Text == "else" {
			return true
		}
	}
	return false
}

// joinAll unions reaching sets per variable, deduping bindings by name-range.
func joinAll(sets []reachSet) reachSet {
	out := reachSet{}
	type key struct{ s, e int }
	seen := map[string]map[key]bool{}
	for _, s := range sets {
		for name, defs := range s {
			if seen[name] == nil {
				seen[name] = map[key]bool{}
			}
			for _, d := range defs {
				k := key{d.NameStart, d.NameEnd}
				if seen[name][k] {
					continue
				}
				seen[name][k] = true
				out[name] = append(out[name], d)
			}
		}
	}
	return out
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test -C server ./internal/tcl/ -run TestReaching -v`
Expected: PASS (all reaching tests, including Task 1's).

- [ ] **Step 5: Commit**

```
git add server/internal/tcl/reaching.go server/internal/tcl/reaching_test.go
git commit -m "feat(tcl): reaching-defs join across if/elseif/else branches"
```
(Append the two required trailers.)

---

### Task 3: Loops (`while`/`for`/`foreach`/`lmap`/`dict for`) with fixpoint

**Files:**
- Modify: `server/internal/tcl/reaching.go`
- Test: `server/internal/tcl/reaching_test.go`

**Interfaces:**
- Consumes: `scriptBodies`, `bracedInner`, `localBindings` (foreach/lmap/dict-for vars).
- Produces: `analyzer.analyzeLoop`; helper `reachEqual(a, b reachSet) bool`; const `maxLoopIters = 200`; `loopHead(c Command) bool`. `command` dispatches loop heads to `analyzeLoop`.

- [ ] **Step 1: Write the failing test**

```go
func TestReachingLoopCarried(t *testing.T) {
	src := "proc f {} {\n  set x 0\n  while {$c} {\n    set y $x\n    set x 9\n  }\n  puts $x\n}"
	defs := reachAtMarker(t, src, "$x") // the `puts $x` after the loop
	if len(defs) != 2 {                 // x0 (zero iterations) or x9 (ran)
		t.Fatalf("want 2 reaching defs (x0, x9), got %d: %#v", len(defs), defs)
	}
}

func TestReachingForeachVar(t *testing.T) {
	src := "proc f {items} {\n  foreach it $items {\n    puts $it\n  }\n}"
	defs := reachAtMarker(t, src, "$it")
	if len(defs) != 1 || defs[0].Name != "it" {
		t.Fatalf("foreach var should reach its use: %#v", defs)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test -C server ./internal/tcl/ -run "TestReachingLoop|TestReachingForeach" -v`
Expected: FAIL — loops not yet modeled (bodies unanalyzed; loop var unseen).

- [ ] **Step 3: Write minimal implementation**

```go
const maxLoopIters = 200

func loopHead(c Command) bool {
	w := c.Words
	if len(w) == 0 || w[0].Kind != WordBare {
		return false
	}
	switch w[0].Text {
	case "while", "for", "foreach", "lmap":
		return true
	case "dict":
		return len(w) >= 2 && w[1].Kind == WordBare && (w[1].Text == "for" || w[1].Text == "map")
	}
	return false
}

// analyzeLoop iterates the loop body to a fixpoint so a value assigned in one
// iteration reaches later iterations' uses, then joins with the entry set (the
// loop may run zero times). Loop variables (foreach/lmap/dict-for) are gen'd at
// body entry. `for`'s start/next scripts are folded into the iterated block; for
// may-reach soundness, treating start as possibly-repeated only over-approximates.
func (a *analyzer) analyzeLoop(c Command, base int, in reachSet) reachSet {
	bodyIn := in.clone()
	for _, d := range localBindings(c, base) {
		bodyIn[d.Name] = []Definition{d}
	}
	bodies := scriptBodies(c.Words)
	cur := bodyIn
	for iter := 0; iter < maxLoopIters; iter++ {
		next := cur.clone()
		for _, b := range bodies {
			inner, ibase := bracedInner(b, base)
			next = a.seq(Parse(inner), ibase, next)
		}
		merged := joinAll([]reachSet{cur, next})
		if reachEqual(merged, cur) {
			break
		}
		cur = merged
	}
	return joinAll([]reachSet{in, cur})
}

func reachEqual(a, b reachSet) bool {
	if len(a) != len(b) {
		return false
	}
	for name, da := range a {
		db, ok := b[name]
		if !ok || len(da) != len(db) {
			return false
		}
		seen := map[[2]int]bool{}
		for _, d := range da {
			seen[[2]int{d.NameStart, d.NameEnd}] = true
		}
		for _, d := range db {
			if !seen[[2]int{d.NameStart, d.NameEnd}] {
				return false
			}
		}
	}
	return true
}
```

Add to `command` (after the `if` dispatch):

```go
	if loopHead(c) {
		return a.analyzeLoop(c, base, in)
	}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test -C server ./internal/tcl/ -run TestReaching -v`
Expected: PASS (all reaching tests).

- [ ] **Step 5: Commit**

```
git add server/internal/tcl/reaching.go server/internal/tcl/reaching_test.go
git commit -m "feat(tcl): reaching-defs loop fixpoint + loop variables"
```
(Append the two required trailers.)

---

### Task 4: Non-local exits — `break` / `continue` / `return` + liveness

**Files:**
- Modify: `server/internal/tcl/reaching.go`
- Test: `server/internal/tcl/reaching_test.go`

**Interfaces:**
- Produces: `analyzer` gains `loopStack []*frameAcc` and `ret reachSet`; `frameAcc{brk, cont reachSet}`. `command`, `seq`, `analyzeIf`, `analyzeLoop` now return `(reachSet, bool live)`. A non-live path contributes nothing to joins.

This is one coherent capability (liveness threading), so it touches all four functions together.

- [ ] **Step 1: Write the failing test**

```go
func TestReachingEarlyReturnBranch(t *testing.T) {
	src := "proc f {} {\n  set x 1\n  if {$c} {\n    return\n  } else {\n    set x 2\n  }\n  puts $x\n}"
	defs := reachAtMarker(t, src, "$x") // return branch dead; else assigns x2; has else → x2 only
	if len(defs) != 1 {
		t.Fatalf("want 1 reaching def (x2), got %d: %#v", len(defs), defs)
	}
}

func TestReachingBreakExit(t *testing.T) {
	src := "proc f {} {\n  set x 0\n  while {$c} {\n    set x 1\n    if {$d} { break }\n    set x 2\n  }\n  puts $x\n}"
	defs := reachAtMarker(t, src, "$x") // x0 (0 iters), x1 (broke), x2 (end of iter)
	if len(defs) != 3 {
		t.Fatalf("want 3 reaching defs (x0,x1,x2), got %d: %#v", len(defs), defs)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test -C server ./internal/tcl/ -run "TestReachingEarlyReturn|TestReachingBreak" -v`
Expected: FAIL — return/break currently treated as plain commands; dead paths still contribute.

- [ ] **Step 3: Write minimal implementation**

```go
type frameAcc struct{ brk, cont reachSet }

// add to analyzer: loopStack []*frameAcc ; ret reachSet (lazily created)

func (a *analyzer) seq(cmds []Command, base int, in reachSet) (reachSet, bool) {
	cur := in
	for _, c := range cmds {
		var live bool
		cur, live = a.command(c, base, cur)
		if !live {
			return cur, false
		}
	}
	return cur, true
}

func (a *analyzer) command(c Command, base int, in reachSet) (reachSet, bool) {
	a.recordUses(c, base, in)
	switch {
	case isCmd(c.Words, "if"):
		return a.analyzeIf(c, base, in)
	case loopHead(c):
		return a.analyzeLoop(c, base, in)
	case isCmd(c.Words, "return"):
		a.ret = joinAll([]reachSet{nonNil(a.ret), in})
		return in, false
	case isCmd(c.Words, "break"):
		if n := len(a.loopStack); n > 0 {
			top := a.loopStack[n-1]
			top.brk = joinAll([]reachSet{nonNil(top.brk), in})
		}
		return in, false
	case isCmd(c.Words, "continue"):
		if n := len(a.loopStack); n > 0 {
			top := a.loopStack[n-1]
			top.cont = joinAll([]reachSet{nonNil(top.cont), in})
		}
		return in, false
	}
	binds := localBindings(c, base)
	if len(binds) == 0 {
		return in, true
	}
	out := in.clone()
	for _, d := range binds {
		out[d.Name] = []Definition{d}
	}
	return out, true
}

func nonNil(s reachSet) reachSet {
	if s == nil {
		return reachSet{}
	}
	return s
}

func (a *analyzer) analyzeIf(c Command, base int, in reachSet) (reachSet, bool) {
	var liveOuts []reachSet
	anyLive := false
	for _, b := range ifBodies(c.Words) {
		inner, ibase := bracedInner(b, base)
		out, live := a.seq(Parse(inner), ibase, in.clone())
		if live {
			liveOuts = append(liveOuts, out)
			anyLive = true
		}
	}
	if !hasElse(c.Words) {
		liveOuts = append(liveOuts, in)
		anyLive = true
	}
	return joinAll(liveOuts), anyLive
}

func (a *analyzer) analyzeLoop(c Command, base int, in reachSet) (reachSet, bool) {
	acc := &frameAcc{brk: reachSet{}, cont: reachSet{}}
	a.loopStack = append(a.loopStack, acc)
	defer func() { a.loopStack = a.loopStack[:len(a.loopStack)-1] }()

	bodyEntry := in.clone()
	for _, d := range localBindings(c, base) {
		bodyEntry[d.Name] = []Definition{d}
	}
	bodies := scriptBodies(c.Words)
	cur := bodyEntry
	normalEnd := reachSet{}
	for iter := 0; iter < maxLoopIters; iter++ {
		next := cur.clone()
		live := true
		for _, b := range bodies {
			inner, ibase := bracedInner(b, base)
			next, live = a.seq(Parse(inner), ibase, next)
			if !live {
				break
			}
		}
		if live {
			normalEnd = next
		} else {
			normalEnd = reachSet{}
		}
		backEdge := joinAll([]reachSet{normalEnd, acc.cont})
		merged := joinAll([]reachSet{cur, backEdge})
		if reachEqual(merged, cur) {
			break
		}
		cur = merged
	}
	exit := joinAll([]reachSet{in, normalEnd, acc.brk})
	return exit, true
}
```

Update `ReachingAt`'s call: `a.seq(Parse(inner), base, entry)` now returns two values — ignore them (`a.seq(...)`) since `a.found`/`a.answer` carry the result.

- [ ] **Step 4: Run test to verify it passes**

Run: `go test -C server ./internal/tcl/ -run TestReaching -v`
Expected: PASS (all reaching tests).

- [ ] **Step 5: Commit**

```
git add server/internal/tcl/reaching.go server/internal/tcl/reaching_test.go
git commit -m "feat(tcl): reaching-defs break/continue/return liveness"
```
(Append the two required trailers.)

---

### Task 5: Conservative `catch` / `try` / `switch`

**Files:**
- Modify: `server/internal/tcl/reaching.go`
- Test: `server/internal/tcl/reaching_test.go`

**Interfaces:**
- Consumes: `scriptBodies`, `childBodies`, `bracedInner`, `localBindings`.
- Produces: `analyzer.analyzeConservative`; helpers `collectBindings(cmds []Command, base int, into reachSet)`, `appendDedup([]Definition, Definition) []Definition`. `command` dispatches `catch`/`try`/`switch` here. Rationale: `switch` arms are *alternatives* (not a sequence), and `catch`/`try` can exit mid-body — a may-reach join over all body-generated defs is sound and simpler than precise arm/exception modeling (see spec: conservative now, refine later).

- [ ] **Step 1: Write the failing test**

```go
func TestReachingCatchConservative(t *testing.T) {
	src := "proc f {} {\n  set x 1\n  catch {\n    set x 2\n  }\n  puts $x\n}"
	defs := reachAtMarker(t, src, "$x") // x1 (error before set) OR x2
	if len(defs) != 2 {
		t.Fatalf("want 2 reaching defs (x1,x2), got %d: %#v", len(defs), defs)
	}
}

func TestReachingSwitchArms(t *testing.T) {
	src := "proc f {} {\n  set x 0\n  switch $k {\n    a { set x 1 }\n    b { set x 2 }\n  }\n  puts $x\n}"
	defs := reachAtMarker(t, src, "$x") // x0 + x1 + x2 (conservative join)
	if len(defs) != 3 {
		t.Fatalf("want 3 reaching defs (x0,x1,x2), got %d: %#v", len(defs), defs)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test -C server ./internal/tcl/ -run "TestReachingCatch|TestReachingSwitch" -v`
Expected: FAIL — these currently fall through to the default/sequence handling and mis-model the flow.

- [ ] **Step 3: Write minimal implementation**

```go
func conservativeHead(c Command) bool {
	return isCmd(c.Words, "catch") || isCmd(c.Words, "try") || isCmd(c.Words, "switch")
}

// analyzeConservative over-approximates: the bodies may or may not run and may
// exit at any point, so the result joins the entry set with every binding
// generated anywhere in the bodies (and the construct's own bindings, e.g. a
// catch result variable). Sound for may-reach; never drops a real reaching def.
func (a *analyzer) analyzeConservative(c Command, base int, in reachSet) (reachSet, bool) {
	gens := reachSet{}
	for _, b := range scriptBodies(c.Words) {
		inner, ibase := bracedInner(b, base)
		collectBindings(Parse(inner), ibase, gens)
	}
	bodyView := joinAll([]reachSet{in, gens})
	// Record any use at useOff inside the bodies against the conservative view.
	for _, b := range scriptBodies(c.Words) {
		inner, ibase := bracedInner(b, base)
		a.seq(Parse(inner), ibase, bodyView.clone())
	}
	out := bodyView.clone()
	for _, d := range localBindings(c, base) { // catch resultVar / optionsVar
		out[d.Name] = appendDedup(out[d.Name], d)
	}
	return out, true
}

// collectBindings unions every local binding made anywhere in cmds (recursing all
// child script bodies) into `into`.
func collectBindings(cmds []Command, base int, into reachSet) {
	for _, c := range cmds {
		for _, d := range localBindings(c, base) {
			into[d.Name] = appendDedup(into[d.Name], d)
		}
		for _, b := range childBodies(c, base, "::", FrameProc, base) {
			collectBindings(Parse(b.Inner), b.Base, into)
		}
	}
}

func appendDedup(list []Definition, d Definition) []Definition {
	for _, x := range list {
		if x.NameStart == d.NameStart && x.NameEnd == d.NameEnd {
			return list
		}
	}
	return append(list, d)
}
```

Add to `command`'s switch, before `loopHead`:

```go
	case conservativeHead(c):
		return a.analyzeConservative(c, base, in)
```

(Place this case before the generic binding handling; `catch`/`switch` are not in `loopHead`/`if`, so ordering only needs to precede the binding fallthrough.)

- [ ] **Step 4: Run test to verify it passes**

Run: `go test -C server ./internal/tcl/ -run TestReaching -v`
Expected: PASS (all reaching tests).

- [ ] **Step 5: Commit**

```
git add server/internal/tcl/reaching.go server/internal/tcl/reaching_test.go
git commit -m "feat(tcl): conservative reaching-defs for catch/try/switch"
```
(Append the two required trailers.)

---

### Task 6: Size guardrail

**Files:**
- Modify: `server/internal/tcl/reaching.go`
- Test: `server/internal/tcl/reaching_test.go`

**Interfaces:**
- Produces: const `maxReachingBytes = 200000`; `ReachingAt` returns `ok=false` when the enclosing proc body exceeds it, so the resolver falls back to first-binding. Never hang.

- [ ] **Step 1: Write the failing test**

```go
func TestReachingSizeCapFallsBack(t *testing.T) {
	var b strings.Builder
	b.WriteString("proc f {} {\n")
	for i := 0; i < 40000; i++ { // ~ > 200 KB of body
		b.WriteString("  set x 1\n")
	}
	b.WriteString("  puts $x\n}")
	src := b.String()
	off := indexLast(src, "$x") + 1
	if _, ok := ReachingAt(src, off); ok {
		t.Fatalf("expected ok=false (fallback) for oversized proc body")
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test -C server ./internal/tcl/ -run TestReachingSizeCap -v`
Expected: FAIL — currently analyzes regardless of size, returns ok=true.

- [ ] **Step 3: Write minimal implementation**

In `ReachingAt`, immediately after locating the proc body:

```go
	const maxReachingBytes = 200000
	if len(inner) > maxReachingBytes {
		return nil, false // oversized: caller falls back to first-binding
	}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test -C server ./internal/tcl/ -run TestReaching -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```
git add server/internal/tcl/reaching.go server/internal/tcl/reaching_test.go
git commit -m "feat(tcl): size cap for reaching-defs, fall back when exceeded"
```
(Append the two required trailers.)

---

### Task 7: `source` seam for `.rvt` coordinate translation

**Files:**
- Modify: `server/internal/source/source.go`
- Test: `server/internal/source/reaching_test.go`

**Interfaces:**
- Consumes: `tcl.ReachingAt`, `rvt.Extract`, `Document.ToVirtual`, `Document.ToSource`, `IsRVT`.
- Produces: `func Reaching(path, content string, offset int) ([]tcl.Definition, bool)` — `.tcl` passes through; `.rvt` translates the use offset into the stitched script and each result range back to `.rvt` source coordinates.

- [ ] **Step 1: Write the failing test**

```go
package source

import (
	"strings"
	"testing"
)

func TestReachingRVTTranslatesCoords(t *testing.T) {
	content := "<?\nproc f {} {\n  set x 1\n  set x 2\n  puts $x\n}\n?>"
	off := strings.LastIndex(content, "$x") + 1
	defs, ok := Reaching("page.rvt", content, off)
	if !ok || len(defs) != 1 {
		t.Fatalf("rvt reaching: ok=%v defs=%#v", ok, defs)
	}
	want := strings.LastIndex(content, "set x 2") + len("set ")
	if defs[0].NameStart != want {
		t.Fatalf("range %d, want the `set x 2` binding at %d (source coords)", defs[0].NameStart, want)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test -C server ./internal/source/ -run TestReachingRVT -v`
Expected: FAIL — `Reaching` undefined.

- [ ] **Step 3: Write minimal implementation**

```go
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
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go test -C server ./internal/source/ -run TestReachingRVT -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```
git add server/internal/source/source.go server/internal/source/reaching_test.go
git commit -m "feat(source): .rvt coordinate translation for reaching-defs"
```
(Append the two required trailers.)

---

### Task 8: Read-modify-write target counts as a use

**Files:**
- Modify: `server/internal/tcl/reaching.go`
- Test: `server/internal/tcl/reaching_test.go`

**Interfaces:**
- Produces: `isRMW(c Command) bool`; `command` snapshots the reaching set when `useOff` is on an `incr`/`append`/`lappend` *target* (a bareword, so it is not a `$`-use that `recordUses` would catch). Implements the spec default: cursor on `incr x` returns the value feeding it.

- [ ] **Step 1: Write the failing test**

```go
func TestReachingRMWTargetIsUse(t *testing.T) {
	src := "proc f {} {\n  set x 1\n  incr x\n}"
	off := strings.Index(src, "incr x") + len("incr ") // the `x` of `incr x`
	defs, ok := ReachingAt(src, off)
	if !ok || len(defs) != 1 {
		t.Fatalf("rmw target should be a use: ok=%v defs=%#v", ok, defs)
	}
	if defs[0].NameStart != strings.Index(src, "set x 1")+len("set ") {
		t.Fatalf("want the prior `set x 1`, got %#v", defs)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go test -C server ./internal/tcl/ -run TestReachingRMW -v`
Expected: FAIL — `incr x`'s target is a bareword, not caught by `recordUses`, so `ok=false`.

- [ ] **Step 3: Write minimal implementation**

In `command`, after `recordUses` and before applying bindings:

```go
	binds := localBindings(c, base)
	if isRMW(c) && !a.found {
		for _, d := range binds {
			if a.useOff >= d.NameStart && a.useOff < d.NameEnd {
				a.answer = append([]Definition(nil), in[d.Name]...)
				a.found = true
			}
		}
	}
```

```go
func isRMW(c Command) bool {
	return isCmd(c.Words, "incr") || isCmd(c.Words, "append") || isCmd(c.Words, "lappend")
}
```

(The existing kill+gen on `binds` still runs afterward, unchanged.)

- [ ] **Step 4: Run test to verify it passes**

Run: `go test -C server ./internal/tcl/ -run TestReaching -v`
Expected: PASS (all reaching tests).

- [ ] **Step 5: Commit**

```
git add server/internal/tcl/reaching.go server/internal/tcl/reaching_test.go
git commit -m "feat(tcl): treat incr/append/lappend target as a reaching-defs use"
```
(Append the two required trailers.)

---

### Task 9: Resolver integration + reconcile existing tests

**Files:**
- Modify: `server/internal/resolve/resolve.go` (`Definition`, `localDefinition`)
- Test: `server/internal/resolve/resolve_test.go`

**Interfaces:**
- Consumes: `source.Reaching`.
- Produces: `localDefinition` now takes `offset int` and returns the reaching set (origin-chasing each link), falling back to first-binding when there is no reaching answer.

- [ ] **Step 1: Establish the baseline**

Run: `go test -C server ./...`
Expected: PASS (record current green state before changing behavior).

- [ ] **Step 2: Write the failing test (new behavior)**

```go
func TestDefinitionLocalReachingBranch(t *testing.T) {
	r := New(index.New())
	src := "proc f {} {\n  set x 1\n  if {$c} { set x 2 } else { set x 3 }\n  puts $x\n}"
	off := strings.LastIndex(src, "$x") + 1
	defs := r.Definition("a.tcl", src, off)
	if len(defs) != 2 { // reaches set x 2 and set x 3, not set x 1
		t.Fatalf("reaching goto-def: want 2, got %#v", defs)
	}
}

func TestDefinitionLocalReachingLatestStraightLine(t *testing.T) {
	r := New(index.New())
	src := "proc f {} {\n  set x 1\n  set x 2\n  puts $x\n}"
	off := strings.LastIndex(src, "$x") + 1
	defs := r.Definition("a.tcl", src, off)
	if len(defs) != 1 || defs[0].NameStart != strings.LastIndex(src, "set x 2")+len("set ") {
		t.Fatalf("want the latest binding (set x 2), got %#v", defs)
	}
}
```

- [ ] **Step 3: Run to verify it fails**

Run: `go test -C server ./internal/resolve/ -run TestDefinitionLocalReaching -v`
Expected: FAIL — still returns first-binding (one location, the first `set x`).

- [ ] **Step 4: Implement the integration**

In `Definition`, thread the offset:

```go
	if name, scope, ok := r.localAt(file, src, offset); ok {
		return r.localDefinition(file, src, name, scope, offset)
	}
```

Rewrite `localDefinition`:

```go
func (r *Resolver) localDefinition(file, src, name string, scope, offset int) []index.Location {
	// Precise reaching definitions for the use at offset. Each reaching binding
	// origin-chases when it is a global/upvar link (preserving prior behavior).
	if defs, ok := source.Reaching(file, src, offset); ok && len(defs) > 0 {
		var out []index.Location
		for _, d := range defs {
			if d.Origin != "" {
				if locs := r.lookupScoped(d.Origin, file); len(locs) > 0 {
					out = append(out, locs...)
					continue
				}
			}
			out = append(out, index.Location{File: file, Name: d.Name, Kind: tcl.DefLocal, NameStart: d.NameStart, NameEnd: d.NameEnd})
		}
		if len(out) > 0 {
			return out
		}
	}

	// Fallback: earliest binding (used when reaching-defs is unavailable —
	// oversized proc, or a use with no in-proc reaching def such as a bare
	// global/upvar link before any local assignment).
	firstStart, firstEnd, firstOrigin, have := 0, 0, "", false
	for _, d := range source.Defs(file, src) {
		if !isLocalBinding(d.Kind) || d.Name != name || d.Scope != scope {
			continue
		}
		if !have || d.NameStart < firstStart {
			firstStart, firstEnd, firstOrigin, have = d.NameStart, d.NameEnd, d.Origin, true
		}
	}
	if !have {
		return nil
	}
	if firstOrigin != "" {
		if locs := r.lookupScoped(firstOrigin, file); len(locs) > 0 {
			return locs
		}
	}
	return []index.Location{{File: file, Name: name, Kind: tcl.DefLocal, NameStart: firstStart, NameEnd: firstEnd}}
}
```

- [ ] **Step 5: Run the new tests**

Run: `go test -C server ./internal/resolve/ -run TestDefinitionLocalReaching -v`
Expected: PASS.

- [ ] **Step 6: Reconcile existing tests (regression guard)**

Run: `go test -C server ./internal/resolve/ -v`

Existing proc-local goto-def tests that assert the OLD "first/nearest binding" semantics will now legitimately fail because the behavior changed by design. Inspect each failure and update the expectation to the reaching-defs answer. Known candidates (verify against current file):
- `TestDefinitionProcLocalJumpsToDeclarationNotMutation` — directly asserts first-binding-not-mutation; update to expect the reaching def (or delete if fully superseded by the new tests).
- `TestDefinitionProcLocalDeclaration`, `TestDefinitionProcLocalParamFallback` — re-verify expected ranges under reaching semantics.

Do NOT change tests that assert global/upvar origin-chasing, array resolution, `.rvt`, command, or namespace-var behavior — those must still pass unchanged. If any of those fail, it is a real regression to fix in the code, not the test.

- [ ] **Step 7: Run the full suite**

Run: `go test -C server ./...`
Expected: PASS (all packages).

- [ ] **Step 8: Commit**

```
git add server/internal/resolve/resolve.go server/internal/resolve/resolve_test.go
git commit -m "feat(resolve): context-sensitive proc-local goto-def via reaching-defs"
```
(Append the two required trailers.)

---

## Self-Review (completed by author)

**Spec coverage:** intraprocedural reaching engine (Tasks 1–6), `.rvt` (Task 7), reaching-set goto-def replacing first-binding (Task 9), RMW-as-use default (Task 8), conservative catch/try + switch (Task 5), size guardrail + graceful fallback (Task 6), find-references unchanged (never modified), global/upvar origin-chase preserved (Task 9 per-def chase + fallback). OO type-tracking intentionally absent (future spec).

**Placeholder scan:** the only deferred detail is `localBindings`'s full body in Task 1, described as "reuse the exact helpers `emitDefs` uses" with explicit rules — acceptable as it mirrors existing code the implementer can read; all other steps carry concrete code.

**Type consistency:** `reachSet`, `analyzer`, `Definition`, `ReachingAt(src, useOff)→([]Definition,bool)`, `source.Reaching(path,content,offset)→([]tcl.Definition,bool)`, `localDefinition(file,src,name,scope,offset)` are used consistently across tasks. `command`/`seq`/`analyzeIf`/`analyzeLoop` switch to `(reachSet, bool)` in Task 4 and stay there.

**Known risk carried from spec:** no runtime oracle for reaching-defs; fixture correctness is manual (stated in spec §Testing).
