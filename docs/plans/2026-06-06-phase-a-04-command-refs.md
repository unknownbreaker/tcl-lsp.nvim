# Phase A — Plan 4: Command Reference Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** From a parsed `Command`, produce a flat list of classified `Reference`s — the command-position name plus variable references in arguments, recursing into `[command substitution]` spans — with correct absolute byte offsets.

**Architecture:** Part of the parser layer (see `docs/plans/2026-06-06-goto-def-ref-design.md`). Plans 1–3 gave tokens, commands/words, and `$var` extraction. This plan adds `tcl.CommandRefs(c Command) []Reference`. It does NOT yet track namespace/frame context or recognize definitions — that is the next plan (context walker). It supersedes Plan 3's bracket-skipping by recursing into `[...]`.

**Tech Stack:** Go 1.23+ (local 1.26.4), standard `testing`.

---

## File structure

- `server/internal/tcl/refs.go` — `RefKind`, `Reference`, `CommandRefs`, helpers.
- `server/internal/tcl/refs_test.go` — table-driven tests.

Reuses `Command`/`Word`/`WordKind` (parser.go) and `parseVarRef`/`skipBracketSpan`/`isNameByte` (varref.go). `WordVarRefs` (Plan 3) stays as the flat var-only helper; `CommandRefs` is the recursive command+variable extractor.

**Known limitation (documented, tested):** variables inside a braced `expr` argument (e.g. `[expr {$x}]`) are not found — braces suppress substitution structurally and we do not model `expr`'s special re-evaluation. This matches research OQ8 (expr is a special position).

---

## Task 1: Reference model + command head + variable args (no bracket recursion yet)

**Files:**
- Create: `server/internal/tcl/refs.go`
- Create: `server/internal/tcl/refs_test.go`

- [ ] **Step 1: Write the failing test**

Create `server/internal/tcl/refs_test.go`:

```go
package tcl

import (
	"reflect"
	"testing"
)

func TestCommandRefsSimple(t *testing.T) {
	// "set x $y": head `set`, arg `x` is a literal bareword (no ref at this
	// layer — it is a definition target handled later), arg `$y` is a var ref.
	cmds := Parse("set x $y")
	got := CommandRefs(cmds[0])
	want := []Reference{
		{Kind: RefCommand, Name: "set", Start: 0, End: 3},
		{Kind: RefVariable, Name: "y", Start: 6, End: 8},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("\n got: %#v\nwant: %#v", got, want)
	}
}

func TestCommandRefsBareCommandOnly(t *testing.T) {
	cmds := Parse("exit")
	got := CommandRefs(cmds[0])
	want := []Reference{{Kind: RefCommand, Name: "exit", Start: 0, End: 4}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("\n got: %#v\nwant: %#v", got, want)
	}
}

func TestCommandRefsDynamicHead(t *testing.T) {
	// First word `$handler` is dynamic (contains $): not a command-name ref,
	// but the variable `handler` is a reference. Arg `arg` yields nothing.
	cmds := Parse("$handler arg")
	got := CommandRefs(cmds[0])
	want := []Reference{{Kind: RefVariable, Name: "handler", Start: 0, End: 8}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("\n got: %#v\nwant: %#v", got, want)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `server/`): `go test ./internal/tcl/ -run TestCommandRefs`
Expected: FAIL — compile error, `undefined: CommandRefs`, `undefined: Reference`, `undefined: RefCommand`/`RefVariable`.

- [ ] **Step 3: Write minimal implementation**

Create `server/internal/tcl/refs.go`:

```go
package tcl

// RefKind classifies a reference by its syntactic position.
type RefKind int

const (
	RefCommand  RefKind = iota // command-position name (a command being invoked)
	RefVariable                // a $-substituted variable
)

// Reference is one classified identifier occurrence with an absolute byte range.
type Reference struct {
	Kind  RefKind
	Name  string
	Start int
	End   int
}

// CommandRefs returns the references in a single command: the command-position
// name (when the first word is a literal name) plus the variable references in
// every word. Offsets are absolute when the command's word offsets are absolute
// (as produced by Parse on source text). [command substitution] recursion is
// added in a later task.
func CommandRefs(c Command) []Reference {
	var refs []Reference
	for idx, w := range c.Words {
		if idx == 0 && isLiteralName(w) {
			refs = append(refs, Reference{Kind: RefCommand, Name: w.Text, Start: w.Start, End: w.End})
			continue
		}
		refs = append(refs, wordRefs(w)...)
	}
	return refs
}

// isLiteralName reports whether a word is a static command name: a bareword with
// no substitution ($ or [). Dynamic heads ($cmd, [get]) are not command names.
func isLiteralName(w Word) bool {
	if w.Kind != WordBare || w.Text == "" {
		return false
	}
	for i := 0; i < len(w.Text); i++ {
		if w.Text[i] == '$' || w.Text[i] == '[' {
			return false
		}
	}
	return true
}

// wordRefs scans one word for variable references. Braced words undergo no
// substitution and yield none. (Bracket recursion is added in a later task.)
func wordRefs(w Word) []Reference {
	if w.Kind == WordBraced {
		return nil
	}
	return scanRefs(w.Text, w.Start)
}

func scanRefs(text string, base int) []Reference {
	var refs []Reference
	i := 0
	for i < len(text) {
		c := text[i]
		switch {
		case c == '\\' && i+1 < len(text):
			i += 2
		case c == '$':
			ref, next, ok := parseVarRef(text, i, base)
			if ok {
				refs = append(refs, Reference{Kind: RefVariable, Name: ref.Name, Start: ref.Start, End: ref.End})
			}
			i = next
		default:
			i++
		}
	}
	return refs
}
```

- [ ] **Step 4: Run test to verify it passes**

Run (from `server/`): `go test ./internal/tcl/ -run TestCommandRefs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add server/internal/tcl/refs.go server/internal/tcl/refs_test.go
git commit -m "feat(tcl): classified command/variable reference extraction"
```

---

## Task 2: Recurse into `[command substitution]` spans

**Files:**
- Modify: `server/internal/tcl/refs.go`
- Modify: `server/internal/tcl/refs_test.go`

- [ ] **Step 1: Write the failing test**

Add to `server/internal/tcl/refs_test.go`:

```go
func TestCommandRefsBracketRecursion(t *testing.T) {
	// "set y [foo $x]": head set, nested command foo, nested var x.
	cmds := Parse("set y [foo $x]")
	got := CommandRefs(cmds[0])
	want := []Reference{
		{Kind: RefCommand, Name: "set", Start: 0, End: 3},
		{Kind: RefCommand, Name: "foo", Start: 7, End: 10},
		{Kind: RefVariable, Name: "x", Start: 11, End: 13},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("\n got: %#v\nwant: %#v", got, want)
	}
}

func TestCommandRefsNestedBrackets(t *testing.T) {
	cmds := Parse("puts [a [b $x]]")
	got := CommandRefs(cmds[0])
	want := []Reference{
		{Kind: RefCommand, Name: "puts", Start: 0, End: 4},
		{Kind: RefCommand, Name: "a", Start: 6, End: 7},
		{Kind: RefCommand, Name: "b", Start: 9, End: 10},
		{Kind: RefVariable, Name: "x", Start: 11, End: 13},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("\n got: %#v\nwant: %#v", got, want)
	}
}

func TestCommandRefsBracketHead(t *testing.T) {
	// Dynamic head via command substitution: "[get] a" -> command `get`.
	cmds := Parse("[get] a")
	got := CommandRefs(cmds[0])
	want := []Reference{{Kind: RefCommand, Name: "get", Start: 1, End: 4}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("\n got: %#v\nwant: %#v", got, want)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `server/`): `go test ./internal/tcl/ -run "TestCommandRefsBracket|TestCommandRefsNested"`
Expected: FAIL — bracket spans are currently skipped (default case), so `foo`/`x`/`a`/`b`/`get` are not found.

- [ ] **Step 3: Write minimal implementation**

In `server/internal/tcl/refs.go`, replace `scanRefs` with the bracket-recursing version and add `substRefs`:

```go
func scanRefs(text string, base int) []Reference {
	var refs []Reference
	i := 0
	for i < len(text) {
		c := text[i]
		switch {
		case c == '\\' && i+1 < len(text):
			i += 2
		case c == '$':
			ref, next, ok := parseVarRef(text, i, base)
			if ok {
				refs = append(refs, Reference{Kind: RefVariable, Name: ref.Name, Start: ref.Start, End: ref.End})
			}
			i = next
		case c == '[':
			end := skipBracketSpan(text, i) // index just past the matching ']'
			innerEnd := end
			if end > i+1 && text[end-1] == ']' {
				innerEnd = end - 1
			}
			refs = append(refs, substRefs(text[i+1:innerEnd], base+i+1)...)
			i = end
		default:
			i++
		}
	}
	return refs
}

// substRefs extracts references from the interior of a [command substitution].
// innerBase is the absolute offset of the interior's first byte. The interior is
// itself a script, so it is parsed and each command recursed into; offsets are
// shifted from interior-relative to absolute.
func substRefs(inner string, innerBase int) []Reference {
	var refs []Reference
	for _, c := range Parse(inner) {
		for _, r := range CommandRefs(c) {
			r.Start += innerBase
			r.End += innerBase
			refs = append(refs, r)
		}
	}
	return refs
}
```

- [ ] **Step 4: Run test to verify it passes**

Run (from `server/`): `go test ./internal/tcl/`
Expected: PASS (all tests, including nested-bracket absolute offsets).

- [ ] **Step 5: Commit**

```bash
git add server/internal/tcl/refs.go server/internal/tcl/refs_test.go
git commit -m "feat(tcl): recurse into command-substitution spans for references"
```

---

## Task 3: Integration, absolute offsets, and the expr-braced limitation

**Files:**
- Modify: `server/internal/tcl/refs_test.go`

- [ ] **Step 1: Write the tests**

Add to `server/internal/tcl/refs_test.go`:

```go
func TestCommandRefsAbsoluteOffsets(t *testing.T) {
	src := "lappend ::items $x"
	cmds := Parse(src)
	got := CommandRefs(cmds[0])
	want := []Reference{
		{Kind: RefCommand, Name: "lappend", Start: 0, End: 7},
		{Kind: RefVariable, Name: "x", Start: 16, End: 18},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("\n got: %#v\nwant: %#v", got, want)
	}
	if src[got[0].Start:got[0].End] != "lappend" {
		t.Fatalf("command offset slice = %q", src[got[0].Start:got[0].End])
	}
	if src[got[1].Start:got[1].End] != "$x" {
		t.Fatalf("var offset slice = %q", src[got[1].Start:got[1].End])
	}
}

func TestCommandRefsExprBracedLimitation(t *testing.T) {
	// KNOWN LIMITATION: a variable inside a braced expr argument is not found
	// (braces suppress substitution structurally; we do not model expr's
	// re-evaluation of its argument). We still find `set` and `expr`.
	cmds := Parse("set y [expr {$x + 1}]")
	got := CommandRefs(cmds[0])
	for _, r := range got {
		if r.Kind == RefVariable && r.Name == "x" {
			t.Fatalf("did not expect $x inside braced expr arg (known limitation): %#v", got)
		}
	}
	foundExpr := false
	for _, r := range got {
		if r.Kind == RefCommand && r.Name == "expr" {
			foundExpr = true
		}
	}
	if !foundExpr {
		t.Fatalf("expected expr command in: %#v", got)
	}
}
```

- [ ] **Step 2: Run the full suite**

Run (from `server/`): `go vet ./...`
Then: `go test ./...`
Expected: clean vet; all tests PASS (Plans 1–4).

- [ ] **Step 3: Commit**

```bash
git add server/internal/tcl/refs_test.go
git commit -m "test(tcl): command-ref absolute offsets and expr-braced limitation"
```

---

## Done criteria for Plan 4

- `go vet ./...` clean; `go test ./...` all pass.
- `tcl.CommandRefs(c)` returns classified `[]Reference` (`RefCommand`/`RefVariable`) with absolute offsets: the literal command head, variable refs in args, and references nested inside `[command substitution]` spans (with correctly composed offsets). Dynamic heads (`$cmd`, `[get]`) are handled. The expr-braced-variable gap is documented and locked by a test.

**Next:** Plan 5 — context walker: track current namespace and frame kind, recurse into `proc`/`namespace eval` braced bodies (re-parsing body text), attach context to each `Reference`, and recognize scope commands (`proc`/`set`/`variable`/`global`/`upvar`/`namespace path`/`export`/`import`) to emit `Definition`s with fully-qualified names — the complete resolver contract.
