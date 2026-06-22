# Proc-local Variable Resolution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add goto-definition and goto-references for proc-local variables in `.tcl` and `.rvt`.

**Architecture:** A proc-local is keyed by `(file, scopeID, name)` where `scopeID` is the enclosing proc body's interior byte offset. The scope is threaded through the single `childBodies` traversal and stamped on every `Definition`/`ContextRef`; resolution happens at query time in the resolve layer (locals never cross files).

**Tech Stack:** Go, standard `testing`. Tests run with `go -C server test ./internal/<pkg>/`.

## Global Constraints

- Scope stays tight to goto-def/goto-ref — no completion/hover/etc.
- `scopeID` is an opaque equality key: compared only def-to-ref, never against a cursor position.
- Run tests with `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ...` (no `cd`).
- Commit messages: conventional commits; end with the Co-Authored-By and Claude-Session trailers used in this repo.
- Arrays (`set arr(i)`) are explicitly out of scope for v1.

---

## File Structure

- `server/internal/tcl/bodies.go` — `bodyScope.Scope`, `childBodies(…, scope)`.
- `server/internal/tcl/context.go` — `ContextRef.Scope`, ref-walker threading.
- `server/internal/tcl/defs.go` — `Definition.Scope`, def-walker threading, `emitProcParams` scope arg, new loop-var/`variable`-in-proc extraction.
- `server/internal/resolve/resolve.go` — `localAt`, `isLocalBinding`, local branches in `Definition`/`References`/`Declarations`.
- Tests: `defs_test.go`, `context_test.go`, `resolve_test.go`, `corpus_test.go` + `.rvt` fixtures.

---

### Task 1: Thread scope through childBodies and both walkers

**Files:**
- Modify: `server/internal/tcl/bodies.go` (`bodyScope`, `childBodies`)
- Modify: `server/internal/tcl/context.go` (`ContextRef`, `FileRefs`, `walkScript`, `recurseBodies`)
- Modify: `server/internal/tcl/defs.go` (`Definition`, `FileDefs`, `walkDefs`, `recurseDefBodies`, `emitDefs`, `emitProcParams`)
- Test: `server/internal/tcl/defs_test.go`, `server/internal/tcl/context_test.go`

**Interfaces:**
- Produces: `Definition.Scope int`, `ContextRef.Scope int`; `childBodies(c Command, base int, ns string, frame FrameKind, scope int) []bodyScope`; `bodyScope.Scope int`; `emitProcParams(argsWord Word, base int, ns string, scope int, out *[]Definition)`.

- [ ] **Step 1: Write failing tests**

In `defs_test.go` add a helper and a test:

```go
func defsNamed(defs []Definition, name string) []Definition {
	var out []Definition
	for _, d := range defs {
		if d.Name == name {
			out = append(out, d)
		}
	}
	return out
}

func TestFileDefsLocalScopeThreading(t *testing.T) {
	// Two procs each declare local `x`; their scopes differ. A `set` inside an
	// if-body shares the enclosing proc's scope (no block scope in Tcl).
	src := "proc f {x} {\n  set y 1\n  if {1} { set z 2 }\n}\nproc g {x} {}"
	defs := FileDefs(src)

	xs := defsNamed(defs, "x")
	if len(xs) != 2 {
		t.Fatalf("want 2 defs named x, got %d: %#v", len(xs), defs)
	}
	if xs[0].Scope == 0 || xs[0].Scope == xs[1].Scope {
		t.Fatalf("param x scopes wrong (want distinct nonzero): %#v", xs)
	}
	fScope := xs[0].Scope
	for _, n := range []string{"y", "z"} {
		ds := defsNamed(defs, n)
		if len(ds) != 1 || ds[0].Scope != fScope {
			t.Fatalf("local %q = %#v, want scope %d", n, ds, fScope)
		}
	}
}
```

In `context_test.go` add:

```go
func TestFileRefsLocalScopeMatchesDef(t *testing.T) {
	src := "proc f {} {\n  set y 1\n  puts $y\n}"
	defs := FileDefs(src)
	ys := defsNamed(defs, "y")
	if len(ys) != 1 {
		t.Fatalf("want 1 def y, got %#v", defs)
	}
	vy := findVar(FileRefs(src), "y")
	if vy == nil || vy.Scope == 0 || vy.Scope != ys[0].Scope {
		t.Fatalf("$y ref scope %#v vs def scope %d", vy, ys[0].Scope)
	}
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/tcl/ -run 'LocalScope' -v`
Expected: compile error (`Scope` field undefined).

- [ ] **Step 3: Add `Scope` to `bodyScope` and thread it in `childBodies`**

In `bodies.go`, add the field:

```go
type bodyScope struct {
	Inner string
	Base  int
	NS    string
	Frame FrameKind
	Scope int // enclosing proc body's interior offset; 0 at namespace frame
}
```

Replace the `childBodies` signature and body:

```go
func childBodies(c Command, base int, ns string, frame FrameKind, scope int) []bodyScope {
	w := c.Words
	switch {
	case isCmd(w, "namespace") && len(w) >= 4 && w[1].Text == "eval" && w[len(w)-1].Kind == WordBraced:
		inner, innerBase := bracedInner(w[len(w)-1], base)
		return []bodyScope{{Inner: inner, Base: innerBase, NS: qualifyNamespace(w[2].Text, ns), Frame: FrameNamespace, Scope: 0}}
	case isCmd(w, "proc") && len(w) >= 4 && w[len(w)-1].Kind == WordBraced:
		inner, innerBase := bracedInner(w[len(w)-1], base)
		return []bodyScope{{Inner: inner, Base: innerBase, NS: ns, Frame: FrameProc, Scope: innerBase}}
	default:
		if _, _, body, ok := decoratedProcDef(w); ok {
			inner, innerBase := bracedInner(body, base)
			return []bodyScope{{Inner: inner, Base: innerBase, NS: ns, Frame: FrameProc, Scope: innerBase}}
		}
		var out []bodyScope
		for _, body := range scriptBodies(w) {
			inner, innerBase := bracedInner(body, base)
			out = append(out, bodyScope{Inner: inner, Base: innerBase, NS: ns, Frame: frame, Scope: scope})
		}
		return out
	}
}
```

- [ ] **Step 4: Thread scope in the ref walker (`context.go`)**

```go
type ContextRef struct {
	Ref       Reference
	Namespace string
	Frame     FrameKind
	Scope     int
}

func FileRefs(src string) []ContextRef {
	var out []ContextRef
	walkScript(Parse(src), 0, "::", FrameNamespace, 0, &out)
	return out
}

func walkScript(cmds []Command, base int, ns string, frame FrameKind, scope int, out *[]ContextRef) {
	for _, c := range cmds {
		for _, r := range CommandRefs(c) {
			r.Start += base
			r.End += base
			*out = append(*out, ContextRef{Ref: r, Namespace: ns, Frame: frame, Scope: scope})
		}
		recurseBodies(c, base, ns, frame, scope, out)
	}
}

func recurseBodies(c Command, base int, ns string, frame FrameKind, scope int, out *[]ContextRef) {
	for _, b := range childBodies(c, base, ns, frame, scope) {
		walkScript(Parse(b.Inner), b.Base, b.NS, b.Frame, b.Scope, out)
	}
}
```

- [ ] **Step 5: Thread scope in the def walker (`defs.go`)**

Add the field and thread the signatures:

```go
type Definition struct {
	Kind      DefKind
	Name      string
	Namespace string
	NameStart int
	NameEnd   int
	Scope     int
}

func FileDefs(src string) []Definition {
	var out []Definition
	walkDefs(Parse(src), 0, "::", FrameNamespace, 0, &out)
	return out
}

func walkDefs(cmds []Command, base int, ns string, frame FrameKind, scope int, out *[]Definition) {
	for _, c := range cmds {
		emitDefs(c, base, ns, frame, scope, out)
		recurseDefBodies(c, base, ns, frame, scope, out)
	}
}
```

Update `recurseDefBodies` so params get the **body** scope:

```go
func recurseDefBodies(c Command, base int, ns string, frame FrameKind, scope int, out *[]Definition) {
	w := c.Words
	if isCmd(w, "proc") && len(w) >= 4 && w[len(w)-1].Kind == WordBraced {
		_, bodyBase := bracedInner(w[len(w)-1], base)
		emitProcParams(w[2], base, ns, bodyBase, out)
	} else if _, args, body, ok := decoratedProcDef(w); ok {
		_, bodyBase := bracedInner(body, base)
		emitProcParams(args, base, ns, bodyBase, out)
	}
	for _, b := range childBodies(c, base, ns, frame, scope) {
		walkDefs(Parse(b.Inner), b.Base, b.NS, b.Frame, b.Scope, out)
	}
}
```

Update `emitProcParams` to take and stamp scope:

```go
func emitProcParams(argsWord Word, base int, ns string, scope int, out *[]Definition) {
	inner, innerBase := argsWord, base
	text := inner.Text
	start := innerBase + inner.Start
	if inner.Kind == WordBraced && len(text) >= 2 {
		text = text[1 : len(text)-1]
		start = innerBase + inner.Start + 1
	}
	for _, p := range scanParams(text, start) {
		*out = append(*out, Definition{
			Kind: DefLocal, Name: p.Name, Namespace: ns,
			NameStart: p.Start, NameEnd: p.End, Scope: scope,
		})
	}
}
```

- [ ] **Step 6: Stamp scope on every def in `emitDefs`**

Change the signature to `func emitDefs(c Command, base int, ns string, frame FrameKind, scope int, out *[]Definition)` and add `Scope: scope,` to **every** `Definition{...}` literal it appends (the `proc`, `variable`, namespace-`set`, proc-`set`, `global`, and `upvar` blocks). Example for the proc-`set` block:

```go
	if isCmd(w, "set") && frame == FrameProc && len(w) >= 2 && isPlainName(w[1]) {
		*out = append(*out, Definition{
			Kind: DefLocal, Name: w[1].Text, Namespace: ns,
			NameStart: base + w[1].Start, NameEnd: base + w[1].End, Scope: scope,
		})
	}
```

- [ ] **Step 7: Run the new tests + full tcl suite**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/tcl/`
Expected: PASS (existing namespace-frame equality tests still pass — scope defaults to 0 there).

- [ ] **Step 8: Commit**

```
git add server/internal/tcl/bodies.go server/internal/tcl/context.go server/internal/tcl/defs.go server/internal/tcl/defs_test.go server/internal/tcl/context_test.go
git commit -m "feat(tcl): thread proc-body scope through def/ref walkers" -m "..." -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01CTr66PbFqDEiS6DXxVy8JV"
```

---

### Task 2: Emit loop-var / lassign / dict-for / variable-in-proc locals

**Files:**
- Modify: `server/internal/tcl/defs.go` (add `emitLoopVarDefs`, `emitVarListNames`; call from `emitDefs`; extend the `variable` block)
- Test: `server/internal/tcl/defs_test.go`

**Interfaces:**
- Consumes: `Definition.Scope`, `scanParams(text string, base int) []paramName` (existing).
- Produces: `DefLocal` entries for `foreach`/`lmap` var lists, `lassign` targets, `dict for`/`dict map` key lists, and `variable` inside a proc.

- [ ] **Step 1: Write failing test**

```go
func TestFileDefsLoopAndDestructuringLocals(t *testing.T) {
	src := "proc f {} {\n" +
		"  foreach it $items { puts $it }\n" +
		"  foreach {a b} $pairs {}\n" +
		"  lassign $row x y\n" +
		"  dict for {k v} $d {}\n" +
		"  variable count\n" +
		"}"
	defs := FileDefs(src)
	procScope := defsNamed(defs, "it")[0].Scope
	if procScope == 0 {
		t.Fatalf("expected nonzero proc scope")
	}
	for _, n := range []string{"it", "a", "b", "x", "y", "k", "v"} {
		ds := defsNamed(defs, n)
		if len(ds) != 1 || ds[0].Kind != DefLocal || ds[0].Scope != procScope {
			t.Fatalf("local %q = %#v, want one DefLocal in scope %d", n, ds, procScope)
		}
		if src[ds[0].NameStart:ds[0].NameEnd] != n {
			t.Fatalf("local %q offsets slice %q", n, src[ds[0].NameStart:ds[0].NameEnd])
		}
	}
	// `variable count` inside a proc yields a DefLocal alias in addition to the
	// existing DefNamespaceVar.
	cnt := defsNamed(defs, "count")
	hasLocal := false
	for _, d := range cnt {
		if d.Kind == DefLocal && d.Scope == procScope {
			hasLocal = true
		}
	}
	if !hasLocal {
		t.Fatalf("variable-in-proc should add a DefLocal: %#v", cnt)
	}
}
```

- [ ] **Step 2: Run to verify it fails**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/tcl/ -run TestFileDefsLoopAndDestructuringLocals -v`
Expected: FAIL (missing `it`, `a`, `b`, `x`, `y`, `k`, `v`).

- [ ] **Step 3: Add extraction helpers in `defs.go`**

```go
// emitLoopVarDefs emits DefLocal bindings for loop/destructuring target variables
// that introduce proc-locals: foreach/lmap var lists, lassign targets, and
// dict for/map key lists. Called only in FrameProc.
func emitLoopVarDefs(w []Word, base int, ns string, scope int, out *[]Definition) {
	if len(w) == 0 || w[0].Kind != WordBare {
		return
	}
	switch w[0].Text {
	case "foreach", "lmap":
		// (varlist list)+ body -- varlists sit at odd indices before the body.
		for i := 1; i+1 < len(w); i += 2 {
			emitVarListNames(w[i], base, ns, scope, out)
		}
	case "lassign":
		// lassign list var ?var ...? -- targets are w[2:].
		for _, vw := range w[2:] {
			emitVarListNames(vw, base, ns, scope, out)
		}
	case "dict":
		// dict for {k v} dict body ; dict map {k v} dict body.
		if len(w) >= 5 && w[1].Kind == WordBare && (w[1].Text == "for" || w[1].Text == "map") {
			emitVarListNames(w[2], base, ns, scope, out)
		}
	}
}

// emitVarListNames emits a DefLocal for each plain name in a variable-list word: a
// brace list {a b} yields a and b; a bare word yields itself. Substituted/quoted
// specs are skipped.
func emitVarListNames(vw Word, base int, ns string, scope int, out *[]Definition) {
	text := vw.Text
	start := base + vw.Start
	if vw.Kind == WordBraced && len(text) >= 2 {
		text = text[1 : len(text)-1]
		start = base + vw.Start + 1
	} else if vw.Kind != WordBare {
		return
	}
	for _, p := range scanParams(text, start) {
		*out = append(*out, Definition{
			Kind: DefLocal, Name: p.Name, Namespace: ns,
			NameStart: p.Start, NameEnd: p.End, Scope: scope,
		})
	}
}
```

- [ ] **Step 4: Wire into `emitDefs`**

At the end of `emitDefs`, add (uses the `scope` param from Task 1):

```go
	if frame == FrameProc {
		emitLoopVarDefs(w, base, ns, scope, out)
	}
```

In the existing `variable` block, after the `DefNamespaceVar` append, add the local alias:

```go
		if frame == FrameProc {
			*out = append(*out, Definition{
				Kind: DefLocal, Name: w[1].Text, Namespace: ns,
				NameStart: base + w[1].Start, NameEnd: base + w[1].End, Scope: scope,
			})
		}
```

- [ ] **Step 5: Run tests**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/tcl/`
Expected: PASS.

- [ ] **Step 6: Commit**

```
git add server/internal/tcl/defs.go server/internal/tcl/defs_test.go
git commit -m "feat(tcl): index loop, lassign, dict-for, and variable-in-proc locals" -m "..." -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01CTr66PbFqDEiS6DXxVy8JV"
```

---

### Task 3: Resolve-layer local path — `localAt` + goto-definition

**Files:**
- Modify: `server/internal/resolve/resolve.go` (add `localAt`, `isLocalBinding`, `localDefinition`; local branch in `Definition`)
- Test: `server/internal/resolve/resolve_test.go`

**Interfaces:**
- Consumes: `source.Defs`, `source.Refs`, `tcl.DefLocal`, `tcl.DefGlobalLink`, `tcl.RefVariable`, `tcl.FrameProc`, `index.Location`.
- Produces: `(r *Resolver) localAt(file, src string, offset int) (name string, scope int, ok bool)`; `isLocalBinding(k tcl.DefKind) bool`; `(r *Resolver) localDefinition(file, src string, offset int, name string, scope int) []index.Location`.

- [ ] **Step 1: Write failing test**

```go
func TestDefinitionProcLocalNearestPreceding(t *testing.T) {
	r := New(index.New())
	src := "proc f {x} {\n  set total 0\n  incr total\n  return $total\n}"
	off := strings.Index(src, "return $total") + len("return $")
	locs := r.Definition("a.tcl", src, off)
	if len(locs) != 1 {
		t.Fatalf("want 1 def, got %#v", locs)
	}
	// nearest preceding binding is `incr total`, not `set total`.
	if got := src[locs[0].NameStart:locs[0].NameEnd]; got != "total" {
		t.Fatalf("slice %q", got)
	}
	if locs[0].NameStart != strings.Index(src, "incr total")+len("incr ") {
		t.Fatalf("expected nearest-preceding (incr total), got offset %d", locs[0].NameStart)
	}
}

func TestDefinitionProcLocalParamFallback(t *testing.T) {
	r := New(index.New())
	src := "proc f {x} {\n  return $x\n}"
	off := strings.Index(src, "$x") + 1
	locs := r.Definition("a.tcl", src, off)
	if len(locs) != 1 || src[locs[0].NameStart:locs[0].NameEnd] != "x" {
		t.Fatalf("param fallback failed: %#v", locs)
	}
	if locs[0].NameStart != strings.Index(src, "{x}")+1 {
		t.Fatalf("expected the param x, got %d", locs[0].NameStart)
	}
}

func TestDefinitionProcLocalScopeIsolation(t *testing.T) {
	r := New(index.New())
	src := "proc f {} {\n  set v 1\n  puts $v\n}\nproc g {} {\n  set v 2\n}"
	off := strings.Index(src, "puts $v") + len("puts $")
	locs := r.Definition("a.tcl", src, off)
	if len(locs) != 1 {
		t.Fatalf("want 1, got %#v", locs)
	}
	// must resolve to f's `set v`, not g's.
	if locs[0].NameStart != strings.Index(src, "set v 1")+len("set ") {
		t.Fatalf("crossed proc scope: %#v", locs)
	}
}

func TestDefinitionProcLocalUndefinedIsNil(t *testing.T) {
	r := New(index.New())
	src := "proc f {} {\n  puts $missing\n}"
	off := strings.Index(src, "$missing") + 1
	if locs := r.Definition("a.tcl", src, off); locs != nil {
		t.Fatalf("undefined local should be nil, got %#v", locs)
	}
}
```

- [ ] **Step 2: Run to verify failure**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/resolve/ -run TestDefinitionProcLocal -v`
Expected: FAIL (locals currently resolve to nil for the preceding/fallback/isolation cases).

- [ ] **Step 3: Add `localAt`, `isLocalBinding`, `localDefinition`**

```go
// isLocalBinding reports whether a definition kind binds a proc-local name.
func isLocalBinding(k tcl.DefKind) bool {
	return k == tcl.DefLocal || k == tcl.DefGlobalLink
}

// localAt reports whether offset sits on a proc-local symbol, returning its bare
// name and scope. Definition name-ranges (local bindings) are checked first, then
// FrameProc variable references ($x uses).
func (r *Resolver) localAt(file, src string, offset int) (name string, scope int, ok bool) {
	for _, d := range source.Defs(file, src) {
		if isLocalBinding(d.Kind) && offset >= d.NameStart && offset < d.NameEnd {
			return d.Name, d.Scope, true
		}
	}
	for _, ref := range source.Refs(file, src) {
		if ref.Ref.Kind == tcl.RefVariable && ref.Frame == tcl.FrameProc &&
			offset >= ref.Ref.Start && offset < ref.Ref.End {
			return ref.Ref.Name, ref.Scope, true
		}
	}
	return "", 0, false
}

// localDefinition returns the nearest preceding binding of (name, scope) at or
// before offset, falling back to the first binding when none precedes.
func (r *Resolver) localDefinition(file, src string, offset int, name string, scope int) []index.Location {
	bestStart, bestEnd, haveBest := 0, 0, false
	firstStart, firstEnd, haveFirst := 0, 0, false
	for _, d := range source.Defs(file, src) {
		if !isLocalBinding(d.Kind) || d.Name != name || d.Scope != scope {
			continue
		}
		if !haveFirst || d.NameStart < firstStart {
			firstStart, firstEnd, haveFirst = d.NameStart, d.NameEnd, true
		}
		if d.NameStart <= offset && (!haveBest || d.NameStart > bestStart) {
			bestStart, bestEnd, haveBest = d.NameStart, d.NameEnd, true
		}
	}
	s, e := bestStart, bestEnd
	if !haveBest {
		if !haveFirst {
			return nil
		}
		s, e = firstStart, firstEnd
	}
	return []index.Location{{File: file, Name: name, Kind: tcl.DefLocal, NameStart: s, NameEnd: e}}
}
```

- [ ] **Step 4: Add the local branch to `Definition`**

At the top of `Definition`, before `ref := refAt(...)`:

```go
	if name, scope, ok := r.localAt(file, src, offset); ok {
		return r.localDefinition(file, src, offset, name, scope)
	}
```

- [ ] **Step 5: Run tests (resolve package)**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/resolve/`
Expected: PASS, including the pre-existing `TestReferencesProcLocalDeferred` (find-references still nil until Task 4 — Definition does not affect it).

- [ ] **Step 6: Commit**

```
git add server/internal/resolve/resolve.go server/internal/resolve/resolve_test.go
git commit -m "feat(resolve): goto-definition for proc-local variables" -m "..." -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01CTr66PbFqDEiS6DXxVy8JV"
```

---

### Task 4: Resolve-layer local path — find-references + declarations

**Files:**
- Modify: `server/internal/resolve/resolve.go` (add `localReferences`; local branches in `References` and `Declarations`)
- Test: `server/internal/resolve/resolve_test.go` (add tests; **replace** the obsolete `TestReferencesProcLocalDeferred`)

**Interfaces:**
- Consumes: `localAt`, `isLocalBinding` (Task 3).
- Produces: `(r *Resolver) localReferences(file, src, name string, scope int) []index.Location`.

- [ ] **Step 1: Replace the deferred-behavior test and add new tests**

Delete `TestReferencesProcLocalDeferred` (its premise — locals return nil — is exactly what this task reverses) and add:

```go
func TestReferencesProcLocalAllOccurrences(t *testing.T) {
	r := New(index.New())
	src := "proc f {x} {\n  set x 1\n  incr x\n  puts $x\n}"
	off := strings.Index(src, "$x") + 1
	locs := r.References("a.tcl", src, off)
	// param x, set x, incr x, $x  => 4 occurrences, all in a.tcl.
	if len(locs) != 4 {
		t.Fatalf("want 4 occurrences, got %d: %#v", len(locs), locs)
	}
	for _, l := range locs {
		if l.File != "a.tcl" || src[l.NameStart:l.NameEnd] != "x" {
			t.Fatalf("bad occurrence %#v", l)
		}
	}
}

func TestReferencesProcLocalForeachVar(t *testing.T) {
	r := New(index.New())
	src := "proc f {} {\n  foreach it $items {\n    puts $it\n  }\n}"
	off := strings.Index(src, "$it") + 1
	locs := r.References("a.tcl", src, off)
	// foreach binding `it` + `$it` use.
	if len(locs) != 2 {
		t.Fatalf("want 2, got %#v", locs)
	}
}

func TestReferencesProcLocalCurrentFileOnly(t *testing.T) {
	ix := index.New()
	// A second file with an identically-named proc-local must not be matched.
	ix.IndexFile("other.tcl", "proc g {} {\n  set v 9\n  puts $v\n}")
	r := New(ix)
	src := "proc f {} {\n  set v 1\n  puts $v\n}"
	off := strings.Index(src, "$v") + 1
	locs := r.References("a.tcl", src, off)
	for _, l := range locs {
		if l.File != "a.tcl" {
			t.Fatalf("local references leaked to %s: %#v", l.File, locs)
		}
	}
	if len(locs) != 2 {
		t.Fatalf("want 2 (set v, $v) in a.tcl, got %#v", locs)
	}
}

func TestReferencesProcLocalGlobalLink(t *testing.T) {
	r := New(index.New())
	src := "proc f {} {\n  global config\n  puts $config\n}"
	off := strings.Index(src, "$config") + 1
	locs := r.References("a.tcl", src, off)
	// `global config` link site + `$config` use.
	if len(locs) != 2 {
		t.Fatalf("want 2, got %#v", locs)
	}
}
```

- [ ] **Step 2: Run to verify failure**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/resolve/ -run 'TestReferencesProcLocal' -v`
Expected: FAIL (References returns nil for locals).

- [ ] **Step 3: Add `localReferences` and the branches**

```go
// localReferences returns every occurrence of the proc-local (name, scope) in the
// current file: binding sites and $-use sites. Locals never cross files, so only
// the current document is scanned. Results are deduped by byte range.
func (r *Resolver) localReferences(file, src, name string, scope int) []index.Location {
	seen := map[[2]int]bool{}
	var out []index.Location
	add := func(start, end int) {
		key := [2]int{start, end}
		if seen[key] {
			return
		}
		seen[key] = true
		out = append(out, index.Location{File: file, Name: name, Kind: tcl.DefLocal, NameStart: start, NameEnd: end})
	}
	for _, d := range source.Defs(file, src) {
		if isLocalBinding(d.Kind) && d.Name == name && d.Scope == scope {
			add(d.NameStart, d.NameEnd)
		}
	}
	for _, ref := range source.Refs(file, src) {
		if ref.Ref.Kind == tcl.RefVariable && ref.Frame == tcl.FrameProc &&
			ref.Ref.Name == name && ref.Scope == scope {
			add(ref.Ref.Start, ref.Ref.End)
		}
	}
	return out
}
```

At the top of `References`, before `target := r.targetFQ(...)`:

```go
	if name, scope, ok := r.localAt(file, src, offset); ok {
		return r.localReferences(file, src, name, scope)
	}
```

At the top of `Declarations`, before `target := r.targetFQ(...)`:

```go
	if name, scope, ok := r.localAt(file, src, offset); ok {
		var out []index.Location
		for _, d := range source.Defs(file, src) {
			if isLocalBinding(d.Kind) && d.Name == name && d.Scope == scope {
				out = append(out, index.Location{File: file, Name: name, Kind: tcl.DefLocal, NameStart: d.NameStart, NameEnd: d.NameEnd})
			}
		}
		return out
	}
```

- [ ] **Step 4: Run resolve + lsp suites**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/resolve/ ./internal/lsp/`
Expected: PASS (the lsp layer merges `Declarations` into `References` for includeDeclaration; dedup keeps counts stable).

- [ ] **Step 5: Commit**

```
git add server/internal/resolve/resolve.go server/internal/resolve/resolve_test.go
git commit -m "feat(resolve): find-references and declarations for proc-local variables" -m "..." -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01CTr66PbFqDEiS6DXxVy8JV"
```

---

### Task 5: `.rvt` golden + full-suite regression

**Files:**
- Create: `server/internal/rvt/testdata/corpus/proc_local.rvt`
- Modify: `server/internal/resolve/corpus_test.go`

**Interfaces:**
- Consumes: `corpusFile`, `index.New`, `New`, `Definition`, `References` (existing test helpers).

- [ ] **Step 1: Create the fixture**

`server/internal/rvt/testdata/corpus/proc_local.rvt`:

```
<? proc summarize {rows} {
    set total 0
    foreach r $rows {
        incr total
    }
    return $total
} ?>
<p><?= summarize $data ?></p>
```

- [ ] **Step 2: Write failing golden test**

In `corpus_test.go`:

```go
// Proc-local inside an .rvt <? ?> block: goto-def on a $-use lands on the nearest
// preceding binding within the same proc, and find-refs stays within the page.
func TestCorpusProcLocalInRVT(t *testing.T) {
	page := corpusFile(t, "proc_local.rvt")
	ix := index.New()
	ix.IndexFile("proc_local.rvt", page)
	r := New(ix)

	off := strings.Index(page, "return $total") + len("return $")
	defs := r.Definition("proc_local.rvt", page, off)
	if len(defs) != 1 || defs[0].File != "proc_local.rvt" ||
		page[defs[0].NameStart:defs[0].NameEnd] != "total" {
		t.Fatalf("rvt proc-local goto-def = %#v", defs)
	}

	refs := r.References("proc_local.rvt", page, off)
	if len(refs) < 2 {
		t.Fatalf("expected >=2 occurrences of total, got %#v", refs)
	}
	for _, l := range refs {
		if l.File != "proc_local.rvt" {
			t.Fatalf("proc-local ref leaked to %s", l.File)
		}
	}
}
```

- [ ] **Step 3: Run to verify it passes (implementation already complete)**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/resolve/ -run TestCorpusProcLocalInRVT -v`
Expected: PASS. If offsets are off, the `.rvt` source-coordinate mapping is wrong — investigate `source.Defs`/`ToSource`, do not patch the test.

- [ ] **Step 4: Run the full suite + gofmt/vet**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./...`
Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server vet ./...`
Run: `gofmt -l server/internal/tcl server/internal/resolve`
Expected: all PASS; gofmt prints nothing.

- [ ] **Step 5: Rebuild + install the binary**

Run: `make -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server install`
Expected: installs to `~/.local/bin/tcl-lsp`. (User must `:LspRestart` to pick it up — disk binary ≠ running server.)

- [ ] **Step 6: Commit**

```
git add server/internal/rvt/testdata/corpus/proc_local.rvt server/internal/resolve/corpus_test.go
git commit -m "test(rvt,resolve): proc-local goto-def/refs golden in an .rvt block" -m "..." -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01CTr66PbFqDEiS6DXxVy8JV"
```

---

## Self-Review

**Spec coverage:**
- Scope model + threading → Task 1. ✅
- New binding forms (foreach/lmap/lassign/dict for/variable-in-proc) → Task 2. ✅
- `localAt` + goto-def nearest-preceding/fallback → Task 3. ✅
- find-refs all-occurrences + declarations + current-file-only → Task 4. ✅
- `.rvt` golden + opaque-scope invariant exercised → Task 5. ✅
- Arrays/`dict with`/namespace loop vars explicitly deferred → not implemented (correct). ✅

**Placeholder scan:** Commit-message `-m "..."` bodies are intentional shorthand for the implementer to expand; all code steps contain complete code.

**Type consistency:** `Scope int` used identically across `Definition`/`ContextRef`/`bodyScope`; `childBodies(…, scope int)`, `walkScript(…, scope int, …)`, `walkDefs(…, scope int, …)`, `emitDefs(…, scope int, …)`, `emitProcParams(…, scope int, …)` all gain the same trailing/penultimate `scope` param. `localAt`/`isLocalBinding`/`localDefinition`/`localReferences` signatures match between Tasks 3 and 4.
