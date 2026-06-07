# Phase A — Plan 3: Intra-Word Variable References Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extract `$`-substitution variable references from a single word (`$x`, `${name}`, `$ns::name`, `$::g`, `$arr(idx)`) with absolute byte ranges.

**Architecture:** Third piece of the Go LSP server (see `docs/plans/2026-06-06-goto-def-ref-design.md`). Plan 2 produced `[]Command` of `[]Word`. This plan adds `tcl.WordVarRefs(w Word) []VarRef`. Braced words yield none (no substitution inside `{}`). `[command substitution]` interiors are intentionally skipped here and handled in a later plan together with the command walker.

**Tech Stack:** Go 1.23+ (local 1.26.4), standard `testing`.

---

## File structure

- `server/internal/tcl/varref.go` — `VarRef`, `WordVarRefs`, and helpers.
- `server/internal/tcl/varref_test.go` — table-driven tests.

Reuses `Word`/`WordKind` (`WordBraced`/`WordBare`/`WordQuoted`) from Plan 2 (`parser.go`).

---

## Task 1: VarRef type + simple `$name`

**Files:**
- Create: `server/internal/tcl/varref.go`
- Create: `server/internal/tcl/varref_test.go`

- [ ] **Step 1: Write the failing test**

Create `server/internal/tcl/varref_test.go`:

```go
package tcl

import (
	"reflect"
	"testing"
)

func TestWordVarRefsBracedNone(t *testing.T) {
	w := Word{Kind: WordBraced, Text: "{a $x b}", Start: 0, End: 8}
	if got := WordVarRefs(w); len(got) != 0 {
		t.Fatalf("braced word should yield no refs, got %#v", got)
	}
}

func TestWordVarRefsSimple(t *testing.T) {
	w := Word{Kind: WordBare, Text: "$x", Start: 4, End: 6}
	got := WordVarRefs(w)
	want := []VarRef{{Name: "x", Start: 4, End: 6}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("\n got: %#v\nwant: %#v", got, want)
	}
}

func TestWordVarRefsLoneDollar(t *testing.T) {
	w := Word{Kind: WordBare, Text: "price$", Start: 0, End: 6}
	if got := WordVarRefs(w); len(got) != 0 {
		t.Fatalf("lone $ is not a ref, got %#v", got)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `server/`): `go test ./internal/tcl/ -run TestWordVarRefs`
Expected: FAIL — compile error, `undefined: WordVarRefs`, `undefined: VarRef`.

- [ ] **Step 3: Write minimal implementation**

Create `server/internal/tcl/varref.go`:

```go
package tcl

// VarRef is a $-substitution occurrence within a word, with an absolute byte
// range [Start,End) covering the reference token (e.g. "$x").
type VarRef struct {
	Name  string
	Start int
	End   int
}

// WordVarRefs returns the variable references substituted inside a single word.
// Braced words undergo no substitution and yield none. Bare and quoted words are
// scanned for $name forms. Interiors of [command substitution] spans are NOT
// descended here (handled later with the command walker).
func WordVarRefs(w Word) []VarRef {
	if w.Kind == WordBraced {
		return nil
	}
	return scanVarRefs(w.Text, w.Start)
}

func scanVarRefs(text string, base int) []VarRef {
	var refs []VarRef
	i := 0
	for i < len(text) {
		if text[i] == '$' {
			ref, next, ok := parseVarRef(text, i, base)
			if ok {
				refs = append(refs, ref)
			}
			i = next
		} else {
			i++
		}
	}
	return refs
}

// parseVarRef parses a reference whose '$' is at index `dollar`. It returns the
// ref, the index to resume scanning from, and whether a ref was found.
func parseVarRef(text string, dollar, base int) (VarRef, int, bool) {
	i := dollar + 1
	if i >= len(text) || !isNameByte(text[i]) {
		return VarRef{}, dollar + 1, false
	}
	j := i
	for j < len(text) && isNameByte(text[j]) {
		j++
	}
	return VarRef{Name: text[i:j], Start: base + dollar, End: base + j}, j, true
}

func isNameByte(b byte) bool {
	return b == '_' ||
		(b >= 'a' && b <= 'z') ||
		(b >= 'A' && b <= 'Z') ||
		(b >= '0' && b <= '9')
}
```

- [ ] **Step 4: Run test to verify it passes**

Run (from `server/`): `go test ./internal/tcl/ -run TestWordVarRefs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add server/internal/tcl/varref.go server/internal/tcl/varref_test.go
git commit -m "feat(tcl): extract simple \$name variable references"
```

---

## Task 2: `${name}` braced variable names

**Files:**
- Modify: `server/internal/tcl/varref.go`
- Modify: `server/internal/tcl/varref_test.go`

- [ ] **Step 1: Write the failing test**

Add to `server/internal/tcl/varref_test.go`:

```go
func TestWordVarRefsBracedName(t *testing.T) {
	// ${...} allows any characters (including spaces) in the name.
	w := Word{Kind: WordBare, Text: "${my var}", Start: 0, End: 9}
	got := WordVarRefs(w)
	want := []VarRef{{Name: "my var", Start: 0, End: 9}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("\n got: %#v\nwant: %#v", got, want)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `server/`): `go test ./internal/tcl/ -run TestWordVarRefsBracedName`
Expected: FAIL — `${my var}` currently yields no ref (`{` is not a name byte).

- [ ] **Step 3: Write minimal implementation**

In `server/internal/tcl/varref.go`, replace `parseVarRef` with:

```go
func parseVarRef(text string, dollar, base int) (VarRef, int, bool) {
	i := dollar + 1
	if i >= len(text) {
		return VarRef{}, dollar + 1, false
	}
	if text[i] == '{' {
		j := i + 1
		for j < len(text) && text[j] != '}' {
			j++
		}
		if j >= len(text) {
			return VarRef{}, len(text), false // unterminated ${ : tolerant
		}
		return VarRef{Name: text[i+1 : j], Start: base + dollar, End: base + j + 1}, j + 1, true
	}
	if !isNameByte(text[i]) {
		return VarRef{}, dollar + 1, false
	}
	j := i
	for j < len(text) && isNameByte(text[j]) {
		j++
	}
	return VarRef{Name: text[i:j], Start: base + dollar, End: base + j}, j, true
}
```

- [ ] **Step 4: Run test to verify it passes**

Run (from `server/`): `go test ./internal/tcl/`
Expected: PASS (all var-ref tests).

- [ ] **Step 5: Commit**

```bash
git add server/internal/tcl/varref.go server/internal/tcl/varref_test.go
git commit -m "feat(tcl): support \${name} braced variable references"
```

---

## Task 3: Namespace-qualified names (`$ns::name`, `$::g`)

**Files:**
- Modify: `server/internal/tcl/varref.go`
- Modify: `server/internal/tcl/varref_test.go`

- [ ] **Step 1: Write the failing test**

Add to `server/internal/tcl/varref_test.go`:

```go
func TestWordVarRefsNamespaceQualified(t *testing.T) {
	w := Word{Kind: WordBare, Text: "$ns::name", Start: 0, End: 9}
	got := WordVarRefs(w)
	want := []VarRef{{Name: "ns::name", Start: 0, End: 9}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("\n got: %#v\nwant: %#v", got, want)
	}
}

func TestWordVarRefsGlobalQualified(t *testing.T) {
	w := Word{Kind: WordBare, Text: "$::g", Start: 0, End: 4}
	got := WordVarRefs(w)
	want := []VarRef{{Name: "::g", Start: 0, End: 4}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("\n got: %#v\nwant: %#v", got, want)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `server/`): `go test ./internal/tcl/ -run "TestWordVarRefsNamespaceQualified|TestWordVarRefsGlobalQualified"`
Expected: FAIL — `$ns::name` stops at `ns` (gives Name "ns"); `$::g` yields no ref (`:` is not a name byte).

- [ ] **Step 3: Write minimal implementation**

In `server/internal/tcl/varref.go`, replace the bareword-name portion of `parseVarRef` (everything after the `${...}` block) with the namespace-aware scan:

```go
	// Bareword name: optional leading "::", then ::-joined [A-Za-z0-9_] segments.
	nameStart := i
	j := i
	if j+1 < len(text) && text[j] == ':' && text[j+1] == ':' {
		j += 2
	}
	if j >= len(text) || !isNameByte(text[j]) {
		return VarRef{}, dollar + 1, false
	}
	for j < len(text) && isNameByte(text[j]) {
		j++
	}
	for j+1 < len(text) && text[j] == ':' && text[j+1] == ':' {
		j += 2
		for j < len(text) && isNameByte(text[j]) {
			j++
		}
	}
	return VarRef{Name: text[nameStart:j], Start: base + dollar, End: base + j}, j, true
```

For reference, `parseVarRef` now reads in full:

```go
func parseVarRef(text string, dollar, base int) (VarRef, int, bool) {
	i := dollar + 1
	if i >= len(text) {
		return VarRef{}, dollar + 1, false
	}
	if text[i] == '{' {
		j := i + 1
		for j < len(text) && text[j] != '}' {
			j++
		}
		if j >= len(text) {
			return VarRef{}, len(text), false // unterminated ${ : tolerant
		}
		return VarRef{Name: text[i+1 : j], Start: base + dollar, End: base + j + 1}, j + 1, true
	}
	// Bareword name: optional leading "::", then ::-joined [A-Za-z0-9_] segments.
	nameStart := i
	j := i
	if j+1 < len(text) && text[j] == ':' && text[j+1] == ':' {
		j += 2
	}
	if j >= len(text) || !isNameByte(text[j]) {
		return VarRef{}, dollar + 1, false
	}
	for j < len(text) && isNameByte(text[j]) {
		j++
	}
	for j+1 < len(text) && text[j] == ':' && text[j+1] == ':' {
		j += 2
		for j < len(text) && isNameByte(text[j]) {
			j++
		}
	}
	return VarRef{Name: text[nameStart:j], Start: base + dollar, End: base + j}, j, true
}
```

- [ ] **Step 4: Run test to verify it passes**

Run (from `server/`): `go test ./internal/tcl/`
Expected: PASS (all var-ref tests).

- [ ] **Step 5: Commit**

```bash
git add server/internal/tcl/varref.go server/internal/tcl/varref_test.go
git commit -m "feat(tcl): support namespace-qualified variable references"
```

---

## Task 4: Array elements resolve to the array name (verification)

The namespace-aware name scan from Task 3 already stops at `(`, so `$arr(...)` yields the **array name** as the reference (range `$arr`), and scanning then continues into the index — so a variable used inside the index (e.g. `$arr($idx)`) is **also** found. This task is verification-only: no implementation change; the tests lock the behavior.

**Files:**
- Modify: `server/internal/tcl/varref_test.go`

- [ ] **Step 1: Write the tests**

Add to `server/internal/tcl/varref_test.go`:

```go
func TestWordVarRefsArrayName(t *testing.T) {
	w := Word{Kind: WordBare, Text: "$arr(key)", Start: 0, End: 9}
	got := WordVarRefs(w)
	want := []VarRef{{Name: "arr", Start: 0, End: 4}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("\n got: %#v\nwant: %#v", got, want)
	}
}

func TestWordVarRefsArrayIndexVarAlsoFound(t *testing.T) {
	// The array name AND a variable used in the index are both references.
	w := Word{Kind: WordBare, Text: "$arr($idx)", Start: 0, End: 10}
	got := WordVarRefs(w)
	want := []VarRef{
		{Name: "arr", Start: 0, End: 4},
		{Name: "idx", Start: 5, End: 9},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("\n got: %#v\nwant: %#v", got, want)
	}
}
```

- [ ] **Step 2: Run test to verify it passes**

Run (from `server/`): `go test ./internal/tcl/ -run TestWordVarRefsArray`
Expected: PASS (Task 3's name scan already produces this; the index `$idx` is found by normal continued scanning).

- [ ] **Step 3: Commit**

```bash
git add server/internal/tcl/varref_test.go
git commit -m "test(tcl): array refs resolve to the array name; index vars still found"
```

---

## Task 5: Skip `[...]` spans and backslash escapes; quoted words

`[command substitution]` interiors are deferred (handled later with the command walker), and `\$` is a literal dollar. Quoted words are scanned like barewords (their `$`/`[` are active).

**Files:**
- Modify: `server/internal/tcl/varref.go`
- Modify: `server/internal/tcl/varref_test.go`

- [ ] **Step 1: Write the failing test**

Add to `server/internal/tcl/varref_test.go`:

```go
func TestWordVarRefsSkipsBracketSpan(t *testing.T) {
	// Command-substitution interiors are deferred: no refs extracted from inside.
	w := Word{Kind: WordBare, Text: "[expr {$x}]", Start: 0, End: 11}
	if got := WordVarRefs(w); len(got) != 0 {
		t.Fatalf("bracket interior should be skipped, got %#v", got)
	}
}

func TestWordVarRefsEscapedDollar(t *testing.T) {
	w := Word{Kind: WordBare, Text: `\$x`, Start: 0, End: 3}
	if got := WordVarRefs(w); len(got) != 0 {
		t.Fatalf("escaped dollar is literal, got %#v", got)
	}
}

func TestWordVarRefsQuotedMultiple(t *testing.T) {
	w := Word{Kind: WordQuoted, Text: `"$a and $b"`, Start: 0, End: 11}
	got := WordVarRefs(w)
	want := []VarRef{
		{Name: "a", Start: 1, End: 3},
		{Name: "b", Start: 8, End: 10},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("\n got: %#v\nwant: %#v", got, want)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `server/`): `go test ./internal/tcl/ -run "TestWordVarRefsSkipsBracketSpan|TestWordVarRefsEscapedDollar"`
Expected: FAIL — `[expr {$x}]` currently extracts `$x`; `\$x` currently extracts `$x`.

- [ ] **Step 3: Write minimal implementation**

In `server/internal/tcl/varref.go`, replace `scanVarRefs` and add `skipBracketSpan`:

```go
func scanVarRefs(text string, base int) []VarRef {
	var refs []VarRef
	i := 0
	for i < len(text) {
		c := text[i]
		switch {
		case c == '\\' && i+1 < len(text):
			i += 2 // escaped char is literal
		case c == '[':
			i = skipBracketSpan(text, i) // command-substitution interior deferred
		case c == '$':
			ref, next, ok := parseVarRef(text, i, base)
			if ok {
				refs = append(refs, ref)
			}
			i = next
		default:
			i++
		}
	}
	return refs
}

// skipBracketSpan returns the index just past a balanced [..] span starting at i.
// Backslash-aware; tolerant of unterminated input (returns len(text)).
func skipBracketSpan(text string, i int) int {
	depth := 0
	for i < len(text) {
		c := text[i]
		if c == '\\' && i+1 < len(text) {
			i += 2
			continue
		}
		if c == '[' {
			depth++
		} else if c == ']' {
			depth--
			if depth == 0 {
				return i + 1
			}
		}
		i++
	}
	return i
}
```

- [ ] **Step 4: Run test to verify it passes**

Run (from `server/`): `go test ./internal/tcl/`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add server/internal/tcl/varref.go server/internal/tcl/varref_test.go
git commit -m "feat(tcl): skip bracket spans and escaped dollars in var-ref scan"
```

---

## Task 6: Absolute-offset integration with the parser

**Files:**
- Modify: `server/internal/tcl/varref_test.go`

- [ ] **Step 1: Write the test**

Add to `server/internal/tcl/varref_test.go`:

```go
func TestWordVarRefsAbsoluteOffsets(t *testing.T) {
	src := "puts $count"
	cmds := Parse(src)
	if len(cmds) != 1 || len(cmds[0].Words) != 2 {
		t.Fatalf("unexpected parse: %#v", cmds)
	}
	got := WordVarRefs(cmds[0].Words[1])
	want := []VarRef{{Name: "count", Start: 5, End: 11}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("\n got: %#v\nwant: %#v", got, want)
	}
	// The range slices back to the exact source text.
	if src[got[0].Start:got[0].End] != "$count" {
		t.Fatalf("offset slice = %q, want %q", src[got[0].Start:got[0].End], "$count")
	}
}
```

- [ ] **Step 2: Run the full suite**

Run (from `server/`): `go vet ./...`
Then: `go test ./...`
Expected: clean vet; all tests PASS (Plans 1–3).

- [ ] **Step 3: Commit**

```bash
git add server/internal/tcl/varref_test.go
git commit -m "test(tcl): var-ref absolute offsets via parser integration"
```

---

## Done criteria for Plan 3

- `go vet ./...` clean; `go test ./...` all pass.
- `tcl.WordVarRefs(w)` returns `[]VarRef` (name + absolute byte range) for `$name`, `${name}`, `$ns::name`, `$::g`, and `$arr(idx)` (→ array name) in bare and quoted words; returns none for braced words; skips `[...]` interiors and `\$` escapes.

**Deferred (next plans):** `[command substitution]` recursion (command head + nested refs inside `[...]`), handled with the command/context walker. (Simple variable refs in an array index — e.g. `$arr($idx)` — are already found; only `[...]` inside an index is skipped.) Then Plan 4 — context walker (namespace + frame kind) + scope-command recognition + the resolver contract.

