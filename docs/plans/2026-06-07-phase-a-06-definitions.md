# Phase A — Plan 6: Definition Emission Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** During the file walk, recognize scope commands and emit `Definition`s with fully-qualified names and name ranges.

**Architecture:** Second half of the parser "heart" (see `docs/plans/2026-06-06-goto-def-ref-design.md`). Plan 5 produced `ContextRef`s. This plan adds `tcl.FileDefs(src) []Definition` using the same walk, recognizing `proc`, `set`, `variable`, `global`, `upvar`. (`namespace export`/`import`/`path` are a later, smaller plan.) Together these complete the contract the resolver consumes.

**Tech Stack:** Go 1.23+ (local 1.26.4), standard `testing`, `strings`.

---

## File structure

- `server/internal/tcl/defs.go` — `DefKind`, `Definition`, `FileDefs`, walker + helpers.
- `server/internal/tcl/defs_test.go` — table-driven tests.

Reuses `Command`/`Word` (parser.go), `Parse`, and `qualifyNamespace`/`bracedInner`/`isCmd` (context.go). The walk mirrors `context.go`'s structure but emits definitions instead of references.

**Scope of this plan:** `proc`, `set`, `variable`, `global`, `upvar` definitions. Deferred to a later plan: `namespace export`/`import`/`path`. Known limitation (carried): qualified-proc-name body namespace uses current ns.

---

## Task 1: Definition type + `proc` definitions

A `proc` defines a command whose FQ name is `qualifyName(NAME, currentNs)`. The name range points at the `proc`'s NAME word.

**Files:**
- Create: `server/internal/tcl/defs.go`
- Create: `server/internal/tcl/defs_test.go`

- [ ] **Step 1: Write the failing test**

Create `server/internal/tcl/defs_test.go`:

```go
package tcl

import (
	"reflect"
	"testing"
)

func findDef(defs []Definition, name string) *Definition {
	for i := range defs {
		if defs[i].Name == name {
			return &defs[i]
		}
	}
	return nil
}

func TestFileDefsProcGlobal(t *testing.T) {
	got := FileDefs("proc greet {} {}")
	want := []Definition{
		{Kind: DefProc, Name: "::greet", Namespace: "::", NameStart: 5, NameEnd: 10},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("\n got: %#v\nwant: %#v", got, want)
	}
}

func TestFileDefsProcInNamespace(t *testing.T) {
	src := "namespace eval ::app {\n  proc f {} {}\n}"
	got := FileDefs(src)
	d := findDef(got, "::app::f")
	if d == nil {
		t.Fatalf("did not find ::app::f in %#v", got)
	}
	if d.Kind != DefProc {
		t.Fatalf("kind = %d, want DefProc", d.Kind)
	}
	if src[d.NameStart:d.NameEnd] != "f" {
		t.Fatalf("name slice = %q, want f", src[d.NameStart:d.NameEnd])
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `server/`): `go test ./internal/tcl/ -run TestFileDefs`
Expected: FAIL — compile error, `undefined: FileDefs`, `undefined: Definition`, `undefined: DefProc`.

- [ ] **Step 3: Write minimal implementation**

Create `server/internal/tcl/defs.go`:

```go
package tcl

// DefKind classifies a definition.
type DefKind int

const (
	DefProc        DefKind = iota // a proc (command) definition
	DefNamespaceVar               // a namespace variable (variable / qualified set / ns-top set)
	DefLocal                      // a proc-local variable (param, set, upvar alias)
	DefGlobalLink                 // a `global name` link to ::name
)

// Definition is a declaration site. Name is fully qualified for proc and
// namespace-variable kinds; for locals it is the bare local name. NameStart and
// NameEnd are the absolute byte range of the declared name token.
type Definition struct {
	Kind      DefKind
	Name      string
	Namespace string // the namespace the definition lives in ("::" for locals' enclosing)
	NameStart int
	NameEnd   int
}

// FileDefs parses src and returns the definitions it declares, recursing into
// namespace eval and proc bodies.
func FileDefs(src string) []Definition {
	var out []Definition
	walkDefs(Parse(src), 0, "::", FrameNamespace, &out)
	return out
}

func walkDefs(cmds []Command, base int, ns string, frame FrameKind, out *[]Definition) {
	for _, c := range cmds {
		emitDefs(c, base, ns, frame, out)
		recurseDefBodies(c, base, ns, out)
	}
}

func emitDefs(c Command, base int, ns string, frame FrameKind, out *[]Definition) {
	w := c.Words
	if isCmd(w, "proc") && len(w) >= 2 && isPlainName(w[1]) {
		name := qualifyName(w[1].Text, ns)
		*out = append(*out, Definition{
			Kind:      DefProc,
			Name:      name,
			Namespace: ns,
			NameStart: base + w[1].Start,
			NameEnd:   base + w[1].End,
		})
	}
}

func recurseDefBodies(c Command, base int, ns string, out *[]Definition) {
	w := c.Words
	if isCmd(w, "namespace") && len(w) >= 4 && w[1].Text == "eval" && w[len(w)-1].Kind == WordBraced {
		child := qualifyNamespace(w[2].Text, ns)
		inner, innerBase := bracedInner(w[len(w)-1], base)
		walkDefs(Parse(inner), innerBase, child, FrameNamespace, out)
	}
	if isCmd(w, "proc") && len(w) >= 4 && w[len(w)-1].Kind == WordBraced {
		inner, innerBase := bracedInner(w[len(w)-1], base)
		walkDefs(Parse(inner), innerBase, ns, FrameProc, out)
	}
}

// isPlainName reports whether a word is a bareword usable as a declared name
// (no substitution). Used for proc/variable/set targets.
func isPlainName(w Word) bool {
	return isLiteralName(w)
}

// qualifyName resolves a command/variable name against the current namespace:
// a leading "::" is absolute, otherwise it is qualified into current.
func qualifyName(name, current string) string {
	if len(name) >= 2 && name[0] == ':' && name[1] == ':' {
		return name
	}
	if current == "::" {
		return "::" + name
	}
	return current + "::" + name
}
```

- [ ] **Step 4: Run test to verify it passes**

Run (from `server/`): `go test ./internal/tcl/ -run TestFileDefs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add server/internal/tcl/defs.go server/internal/tcl/defs_test.go
git commit -m "feat(tcl): emit proc definitions with fully-qualified names"
```

---

## Task 2: `variable` and namespace-top `set` definitions

`variable NAME ...` defines a namespace variable `currentNs::NAME`. At namespace-eval top level (FrameNamespace), `set NAME ...` also defines a namespace variable. The name range points at the NAME word.

**Files:**
- Modify: `server/internal/tcl/defs.go`
- Modify: `server/internal/tcl/defs_test.go`

- [ ] **Step 1: Write the failing test**

Add to `server/internal/tcl/defs_test.go`:

```go
func TestFileDefsVariable(t *testing.T) {
	src := "namespace eval ::app {\n  variable count 0\n}"
	got := FileDefs(src)
	d := findDef(got, "::app::count")
	if d == nil {
		t.Fatalf("did not find ::app::count in %#v", got)
	}
	if d.Kind != DefNamespaceVar {
		t.Fatalf("kind = %d, want DefNamespaceVar", d.Kind)
	}
	if src[d.NameStart:d.NameEnd] != "count" {
		t.Fatalf("name slice = %q", src[d.NameStart:d.NameEnd])
	}
}

func TestFileDefsNamespaceTopSet(t *testing.T) {
	src := "namespace eval ::app {\n  set total 5\n}"
	got := FileDefs(src)
	d := findDef(got, "::app::total")
	if d == nil {
		t.Fatalf("did not find ::app::total in %#v", got)
	}
	if d.Kind != DefNamespaceVar {
		t.Fatalf("kind = %d, want DefNamespaceVar", d.Kind)
	}
}

func TestFileDefsGlobalTopSet(t *testing.T) {
	// A bare `set` at global top level defines a global (::) variable.
	got := FileDefs("set g 1")
	d := findDef(got, "::g")
	if d == nil {
		t.Fatalf("did not find ::g in %#v", got)
	}
	if d.Kind != DefNamespaceVar {
		t.Fatalf("kind = %d, want DefNamespaceVar", d.Kind)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `server/`): `go test ./internal/tcl/ -run "TestFileDefsVariable|TestFileDefsNamespaceTopSet|TestFileDefsGlobalTopSet"`
Expected: FAIL — only `proc` is recognized so far.

- [ ] **Step 3: Write minimal implementation**

In `server/internal/tcl/defs.go`, extend `emitDefs` (add after the `proc` block):

```go
	if isCmd(w, "variable") && len(w) >= 2 && isPlainName(w[1]) {
		*out = append(*out, Definition{
			Kind:      DefNamespaceVar,
			Name:      qualifyName(w[1].Text, ns),
			Namespace: ns,
			NameStart: base + w[1].Start,
			NameEnd:   base + w[1].End,
		})
	}
	if isCmd(w, "set") && frame == FrameNamespace && len(w) >= 2 && isPlainName(w[1]) {
		*out = append(*out, Definition{
			Kind:      DefNamespaceVar,
			Name:      qualifyName(w[1].Text, ns),
			Namespace: ns,
			NameStart: base + w[1].Start,
			NameEnd:   base + w[1].End,
		})
	}
```

- [ ] **Step 4: Run test to verify it passes**

Run (from `server/`): `go test ./internal/tcl/`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add server/internal/tcl/defs.go server/internal/tcl/defs_test.go
git commit -m "feat(tcl): emit namespace-variable definitions (variable, ns-top set)"
```

---

## Task 3: proc-local definitions (params, `set`, `global`, `upvar`)

Inside a proc body (FrameProc): proc parameters, a `set NAME`, and `upvar ... ALIAS` declare locals; `global NAME` is a link to `::NAME`. Parameters come from the proc's args word.

**Files:**
- Modify: `server/internal/tcl/defs.go`
- Modify: `server/internal/tcl/defs_test.go`

- [ ] **Step 1: Write the failing test**

Add to `server/internal/tcl/defs_test.go`:

```go
func TestFileDefsProcParamsAndLocals(t *testing.T) {
	src := "proc add {a b} {\n  set sum 0\n  global cfg\n}"
	got := FileDefs(src)
	// params a, b are locals
	for _, n := range []string{"a", "b", "sum"} {
		d := findDef(got, n)
		if d == nil || d.Kind != DefLocal {
			t.Fatalf("expected local %q, got %#v", n, got)
		}
	}
	// global cfg is a link to ::cfg
	g := findDef(got, "cfg")
	if g == nil || g.Kind != DefGlobalLink {
		t.Fatalf("expected DefGlobalLink cfg, got %#v", got)
	}
}

func TestFileDefsUpvarAlias(t *testing.T) {
	src := "proc bump {varname} {\n  upvar 1 $varname c\n}"
	got := FileDefs(src)
	// `c` is a local alias introduced by upvar
	d := findDef(got, "c")
	if d == nil || d.Kind != DefLocal {
		t.Fatalf("expected local alias c, got %#v", got)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `server/`): `go test ./internal/tcl/ -run "TestFileDefsProcParamsAndLocals|TestFileDefsUpvarAlias"`
Expected: FAIL — locals/params/global/upvar not yet emitted.

- [ ] **Step 3: Write minimal implementation**

In `server/internal/tcl/defs.go`:

(a) Emit parameters when recursing a proc body. Replace the `proc` block in `recurseDefBodies` with:

```go
	if isCmd(w, "proc") && len(w) >= 4 && w[len(w)-1].Kind == WordBraced {
		emitProcParams(w[2], base, out)
		inner, innerBase := bracedInner(w[len(w)-1], base)
		walkDefs(Parse(inner), innerBase, ns, FrameProc, out)
	}
```

(b) Add local/global emission to `emitDefs` (after the `set` namespace block — note the frame guards so `set` is only a namespace var at ns-top and a local in a proc):

```go
	if isCmd(w, "set") && frame == FrameProc && len(w) >= 2 && isPlainName(w[1]) {
		*out = append(*out, Definition{
			Kind: DefLocal, Name: w[1].Text, Namespace: ns,
			NameStart: base + w[1].Start, NameEnd: base + w[1].End,
		})
	}
	if isCmd(w, "global") {
		for _, gw := range w[1:] {
			if isPlainName(gw) {
				*out = append(*out, Definition{
					Kind: DefGlobalLink, Name: gw.Text, Namespace: ns,
					NameStart: base + gw.Start, NameEnd: base + gw.End,
				})
			}
		}
	}
	if isCmd(w, "upvar") && len(w) >= 2 {
		// The alias is the last word; intermediate words are level + target name
		// pairs whose targets are often dynamic. Record the final alias as a local.
		alias := w[len(w)-1]
		if isPlainName(alias) {
			*out = append(*out, Definition{
				Kind: DefLocal, Name: alias.Text, Namespace: ns,
				NameStart: base + alias.Start, NameEnd: base + alias.End,
			})
		}
	}
```

(c) Add `emitProcParams`, which parses the args word (a braced or bare list of params; each param may be `name` or `{name default}`):

```go
// emitProcParams emits a DefLocal for each parameter name in a proc args word.
func emitProcParams(argsWord Word, base int, out *[]Definition) {
	inner, innerBase := argsWord, base
	text := inner.Text
	start := innerBase + inner.Start
	if inner.Kind == WordBraced && len(text) >= 2 {
		text = text[1 : len(text)-1]
		start = innerBase + inner.Start + 1
	}
	for _, p := range scanParams(text, start) {
		*out = append(*out, Definition{
			Kind: DefLocal, Name: p.Name, Namespace: "",
			NameStart: p.Start, NameEnd: p.End,
		})
	}
}
```

(d) Add a tiny parameter scanner. A params word is a TCL list; each element is either a bareword `name` or a braced `{name default}`. Reuse `Parse` on the params text: each "command" line's first word is a param (params are whitespace-separated; there are no newlines/semicolons inside a normal args list, so `Parse` yields one command whose words are the params). For `{name default}` elements, the param name is the first word inside the braces.

```go
type paramName struct {
	Name       string
	Start, End int
}

func scanParams(text string, base int) []paramName {
	var ps []paramName
	cmds := Parse(text)
	for _, c := range cmds {
		for _, word := range c.Words {
			name, s, e := paramFromWord(word, base)
			if name != "" {
				ps = append(ps, paramName{Name: name, Start: s, End: e})
			}
		}
	}
	return ps
}

// paramFromWord extracts the parameter name and its absolute range from one
// args-list element: a bareword `name`, or a braced `{name default}` (first
// inner word). base is the absolute offset of the params text's first byte.
func paramFromWord(w Word, base int) (string, int, int) {
	if w.Kind == WordBraced && len(w.Text) >= 2 {
		inner := w.Text[1 : len(w.Text)-1]
		innerBase := base + w.Start + 1
		for _, c := range Parse(inner) {
			if len(c.Words) > 0 {
				fw := c.Words[0]
				return fw.Text, innerBase + fw.Start, innerBase + fw.End
			}
		}
		return "", 0, 0
	}
	if w.Kind == WordBare && w.Text != "" {
		return w.Text, base + w.Start, base + w.End
	}
	return "", 0, 0
}
```

- [ ] **Step 4: Run test to verify it passes**

Run (from `server/`): `go test ./internal/tcl/`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add server/internal/tcl/defs.go server/internal/tcl/defs_test.go
git commit -m "feat(tcl): emit proc-local defs (params, set, global, upvar)"
```

---

## Task 4: Integration — combined definitions + offset fidelity

**Files:**
- Modify: `server/internal/tcl/defs_test.go`

- [ ] **Step 1: Write the test**

Add to `server/internal/tcl/defs_test.go`:

```go
func TestFileDefsCombined(t *testing.T) {
	src := "namespace eval ::math {\n  variable e 2.7\n  proc square {x} {\n    set r [expr {$x * $x}]\n  }\n}"
	got := FileDefs(src)

	if d := findDef(got, "::math::e"); d == nil || d.Kind != DefNamespaceVar {
		t.Fatalf("missing ::math::e namespace var: %#v", got)
	}
	if d := findDef(got, "::math::square"); d == nil || d.Kind != DefProc {
		t.Fatalf("missing ::math::square proc: %#v", got)
	}
	// param x and local r are locals
	if d := findDef(got, "x"); d == nil || d.Kind != DefLocal {
		t.Fatalf("missing local x: %#v", got)
	}
	if d := findDef(got, "r"); d == nil || d.Kind != DefLocal {
		t.Fatalf("missing local r: %#v", got)
	}
	// name ranges slice back to the source
	sq := findDef(got, "::math::square")
	if src[sq.NameStart:sq.NameEnd] != "square" {
		t.Fatalf("square name slice = %q", src[sq.NameStart:sq.NameEnd])
	}
}
```

- [ ] **Step 2: Run the full suite**

Run (from `server/`): `go vet ./...`
Then: `go test ./...`
Expected: clean vet; all tests PASS (Plans 1–6).

- [ ] **Step 3: Commit**

```bash
git add server/internal/tcl/defs_test.go
git commit -m "test(tcl): combined definition emission and offset fidelity"
```

---

## Done criteria for Plan 6

- `go vet ./...` clean; `go test ./...` all pass.
- `tcl.FileDefs(src)` returns `Definition`s for `proc` (FQ command), `variable` and namespace-top `set` (FQ namespace var), proc params / proc-body `set` / `upvar` alias (locals), and `global` (link to `::name`), each with the declared name's absolute range; recursing into namespace eval and proc bodies.

**Next:** Plan 7 — `namespace export`/`import`/`path` (small), then the workspace indexer (FQ symbol table over `FileDefs`/`FileRefs`), then the resolver + goto-def/ref core, then the LSP shell + clients.
