# Phase A — Plan 5: Context Walker (namespace + frame) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Walk a whole file's commands, tracking the current namespace and frame kind, recursing into `namespace eval` and `proc` bodies, and attach that context to every reference.

**Architecture:** First half of the parser "heart" (see `docs/plans/2026-06-06-goto-def-ref-design.md`). Plan 4 gave `CommandRefs` (refs within one command, braced bodies opaque). This plan adds `tcl.FileRefs(src) []ContextRef`, which re-parses braced bodies and records each reference's namespace + frame. The NEXT plan emits `Definition`s from scope commands. Here we only contextualize references.

**Tech Stack:** Go 1.23+ (local 1.26.4), standard `testing`, `strings`.

---

## File structure

- `server/internal/tcl/context.go` — `FrameKind`, `ContextRef`, `FileRefs`, walker + helpers.
- `server/internal/tcl/context_test.go` — table-driven tests.

Reuses `Command`/`Word`/`WordKind` (parser.go), `Reference`/`CommandRefs` (refs.go), `Parse` (parser.go).

**Known limitations (documented):** a `proc` defined with a qualified name (e.g. `proc ::other::p {} {...}`) has its body walked under the *current* namespace, not `::other` (refined when definitions are added). `namespace eval` bodies that are not a single braced word (computed scripts) are not recursed.

---

## Task 1: Types + flat walk (no body recursion)

**Files:**
- Create: `server/internal/tcl/context.go`
- Create: `server/internal/tcl/context_test.go`

- [ ] **Step 1: Write the failing test**

Create `server/internal/tcl/context_test.go`:

```go
package tcl

import (
	"reflect"
	"testing"
)

func TestFileRefsFlatGlobal(t *testing.T) {
	got := FileRefs("set x $y")
	want := []ContextRef{
		{Ref: Reference{Kind: RefCommand, Name: "set", Start: 0, End: 3}, Namespace: "::", Frame: FrameNamespace},
		{Ref: Reference{Kind: RefVariable, Name: "y", Start: 6, End: 8}, Namespace: "::", Frame: FrameNamespace},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("\n got: %#v\nwant: %#v", got, want)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `server/`): `go test ./internal/tcl/ -run TestFileRefs`
Expected: FAIL — compile error, `undefined: FileRefs`, `undefined: ContextRef`, `undefined: FrameNamespace`.

- [ ] **Step 3: Write minimal implementation**

Create `server/internal/tcl/context.go`:

```go
package tcl

// FrameKind is the kind of scope a reference appears in. Variable resolution
// differs by frame: inside a proc body a bare variable is local-only, while at
// namespace-eval top level it is the namespace's own variable.
type FrameKind int

const (
	FrameNamespace FrameKind = iota // namespace-eval top level (incl. global ::)
	FrameProc                       // inside a proc body
)

// ContextRef is a reference together with the namespace and frame at its site.
type ContextRef struct {
	Ref       Reference
	Namespace string // e.g. "::" or "::app"
	Frame     FrameKind
}

// FileRefs parses src and returns every reference with its namespace and frame
// context, recursing into namespace eval and proc bodies.
func FileRefs(src string) []ContextRef {
	var out []ContextRef
	walkScript(Parse(src), 0, "::", FrameNamespace, &out)
	return out
}

// walkScript appends contextual refs for each command. base is added to ref
// offsets so refs from a re-parsed (braced) body map back to absolute source.
func walkScript(cmds []Command, base int, ns string, frame FrameKind, out *[]ContextRef) {
	for _, c := range cmds {
		for _, r := range CommandRefs(c) {
			r.Start += base
			r.End += base
			*out = append(*out, ContextRef{Ref: r, Namespace: ns, Frame: frame})
		}
	}
}
```

- [ ] **Step 4: Run test to verify it passes**

Run (from `server/`): `go test ./internal/tcl/ -run TestFileRefs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add server/internal/tcl/context.go server/internal/tcl/context_test.go
git commit -m "feat(tcl): contextual reference walk (flat, global namespace)"
```

---

## Task 2: Recurse into `namespace eval` bodies

**Files:**
- Modify: `server/internal/tcl/context.go`
- Modify: `server/internal/tcl/context_test.go`

- [ ] **Step 1: Write the failing test**

Add to `server/internal/tcl/context_test.go`:

```go
func findVar(refs []ContextRef, name string) *ContextRef {
	for i := range refs {
		if refs[i].Ref.Kind == RefVariable && refs[i].Ref.Name == name {
			return &refs[i]
		}
	}
	return nil
}

func TestFileRefsNamespaceEval(t *testing.T) {
	src := "namespace eval ::app {\n    set v $w\n}"
	got := FileRefs(src)
	vw := findVar(got, "w")
	if vw == nil {
		t.Fatalf("did not find var w in %#v", got)
	}
	if vw.Namespace != "::app" {
		t.Fatalf("namespace = %q, want ::app", vw.Namespace)
	}
	if vw.Frame != FrameNamespace {
		t.Fatalf("frame = %d, want FrameNamespace", vw.Frame)
	}
	if src[vw.Ref.Start:vw.Ref.End] != "$w" {
		t.Fatalf("offset slice = %q, want $w", src[vw.Ref.Start:vw.Ref.End])
	}
}

func TestFileRefsNestedNamespace(t *testing.T) {
	src := "namespace eval ::a { namespace eval b { set x $y } }"
	got := FileRefs(src)
	vy := findVar(got, "y")
	if vy == nil {
		t.Fatalf("did not find var y in %#v", got)
	}
	if vy.Namespace != "::a::b" {
		t.Fatalf("namespace = %q, want ::a::b", vy.Namespace)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `server/`): `go test ./internal/tcl/ -run "TestFileRefsNamespaceEval|TestFileRefsNestedNamespace"`
Expected: FAIL — `findVar` returns nil (body refs are not yet walked).

- [ ] **Step 3: Write minimal implementation**

In `server/internal/tcl/context.go`, add `import "strings"` at the top, call `recurseBodies` from `walkScript`, and add the helpers:

```go
func walkScript(cmds []Command, base int, ns string, frame FrameKind, out *[]ContextRef) {
	for _, c := range cmds {
		for _, r := range CommandRefs(c) {
			r.Start += base
			r.End += base
			*out = append(*out, ContextRef{Ref: r, Namespace: ns, Frame: frame})
		}
		recurseBodies(c, base, ns, out)
	}
}

// recurseBodies walks the braced body of a scope-introducing command.
func recurseBodies(c Command, base int, ns string, out *[]ContextRef) {
	w := c.Words
	if isCmd(w, "namespace") && len(w) >= 4 && w[1].Text == "eval" && w[len(w)-1].Kind == WordBraced {
		child := qualifyNamespace(w[2].Text, ns)
		inner, innerBase := bracedInner(w[len(w)-1], base)
		walkScript(Parse(inner), innerBase, child, FrameNamespace, out)
	}
}

// isCmd reports whether the command's literal head equals name.
func isCmd(words []Word, name string) bool {
	return len(words) > 0 && words[0].Kind == WordBare && words[0].Text == name
}

// qualifyNamespace resolves a namespace name argument against the current
// namespace: a leading "::" is absolute, otherwise it is relative to current.
func qualifyNamespace(name, current string) string {
	if strings.HasPrefix(name, "::") {
		return name
	}
	if current == "::" {
		return "::" + name
	}
	return current + "::" + name
}

// bracedInner returns the interior of a braced word and the absolute offset of
// that interior's first byte (base + word.Start + 1).
func bracedInner(w Word, base int) (string, int) {
	t := w.Text
	if len(t) >= 2 && t[0] == '{' && t[len(t)-1] == '}' {
		return t[1 : len(t)-1], base + w.Start + 1
	}
	return "", base + w.Start
}
```

- [ ] **Step 4: Run test to verify it passes**

Run (from `server/`): `go test ./internal/tcl/`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add server/internal/tcl/context.go server/internal/tcl/context_test.go
git commit -m "feat(tcl): walk namespace eval bodies with qualified namespace"
```

---

## Task 3: Recurse into `proc` bodies (frame = proc)

**Files:**
- Modify: `server/internal/tcl/context.go`
- Modify: `server/internal/tcl/context_test.go`

- [ ] **Step 1: Write the failing test**

Add to `server/internal/tcl/context_test.go`:

```go
func TestFileRefsProcBody(t *testing.T) {
	src := "proc p {} {\n    set a $b\n}"
	got := FileRefs(src)
	vb := findVar(got, "b")
	if vb == nil {
		t.Fatalf("did not find var b in %#v", got)
	}
	if vb.Frame != FrameProc {
		t.Fatalf("frame = %d, want FrameProc", vb.Frame)
	}
	if vb.Namespace != "::" {
		t.Fatalf("namespace = %q, want ::", vb.Namespace)
	}
}

func TestFileRefsProcInNamespace(t *testing.T) {
	src := "namespace eval ::app {\n  proc f {} { set a $b }\n}"
	got := FileRefs(src)
	vb := findVar(got, "b")
	if vb == nil {
		t.Fatalf("did not find var b in %#v", got)
	}
	if vb.Frame != FrameProc {
		t.Fatalf("frame = %d, want FrameProc", vb.Frame)
	}
	if vb.Namespace != "::app" {
		t.Fatalf("namespace = %q, want ::app", vb.Namespace)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `server/`): `go test ./internal/tcl/ -run "TestFileRefsProcBody|TestFileRefsProcInNamespace"`
Expected: FAIL — `proc` bodies are not yet recursed, so var `b` is not found.

- [ ] **Step 3: Write minimal implementation**

In `server/internal/tcl/context.go`, extend `recurseBodies` to handle `proc` (add after the `namespace eval` block):

```go
	if isCmd(w, "proc") && len(w) >= 4 && w[len(w)-1].Kind == WordBraced {
		// The proc body runs in the namespace where the proc is defined. For a
		// qualified proc name the body's namespace is that of the name; this is
		// refined when definitions are added. For now, use the current namespace.
		inner, innerBase := bracedInner(w[len(w)-1], base)
		walkScript(Parse(inner), innerBase, ns, FrameProc, out)
	}
```

- [ ] **Step 4: Run test to verify it passes**

Run (from `server/`): `go test ./internal/tcl/`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add server/internal/tcl/context.go server/internal/tcl/context_test.go
git commit -m "feat(tcl): walk proc bodies as proc-frame references"
```

---

## Task 4: Integration — combined nesting + offset fidelity

**Files:**
- Modify: `server/internal/tcl/context_test.go`

- [ ] **Step 1: Write the test**

Add to `server/internal/tcl/context_test.go`:

```go
func TestFileRefsCombinedAndOffsets(t *testing.T) {
	src := "namespace eval ::app {\n  variable base 10\n  proc scale {n} {\n    return [expr {$n * $base}]\n  }\n}"
	got := FileRefs(src)

	// $n is used inside proc scale's body, in namespace ::app, proc frame.
	// (It appears outside the braced expr arg? No: it is inside {$n * $base},
	// which is braced, so per the expr-braced limitation it is NOT found.)
	// Instead, assert the command refs we DO expect, and offset fidelity for one.

	// The `expr` command ref is inside proc scale's body (namespace ::app, proc frame).
	var exprRef *ContextRef
	for i := range got {
		if got[i].Ref.Kind == RefCommand && got[i].Ref.Name == "expr" {
			exprRef = &got[i]
		}
	}
	if exprRef == nil {
		t.Fatalf("did not find expr command in %#v", got)
	}
	if exprRef.Namespace != "::app" || exprRef.Frame != FrameProc {
		t.Fatalf("expr context = (%q, %d), want (::app, FrameProc)", exprRef.Namespace, exprRef.Frame)
	}
	if src[exprRef.Ref.Start:exprRef.Ref.End] != "expr" {
		t.Fatalf("expr offset slice = %q", src[exprRef.Ref.Start:exprRef.Ref.End])
	}
}
```

- [ ] **Step 2: Run the full suite**

Run (from `server/`): `go vet ./...`
Then: `go test ./...`
Expected: clean vet; all tests PASS (Plans 1–5).

- [ ] **Step 3: Commit**

```bash
git add server/internal/tcl/context_test.go
git commit -m "test(tcl): context walker combined nesting and offset fidelity"
```

---

## Done criteria for Plan 5

- `go vet ./...` clean; `go test ./...` all pass.
- `tcl.FileRefs(src)` returns every reference as a `ContextRef` carrying the current namespace and frame kind, recursing into `namespace eval` (child namespace, namespace frame) and `proc` (current namespace, proc frame) bodies, with absolute offsets preserved through body re-parsing.

**Next:** Plan 6 — definition emission: recognize scope commands (`proc`/`set`/`variable`/`global`/`upvar`/`namespace export`/`import`/`path`) during the same walk and emit `Definition`s with fully-qualified names and name ranges; refine qualified-proc-body namespaces. Together with this plan that completes the resolver contract.
