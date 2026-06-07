# Phase A — Plan 2: Command & Word Parser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Group the tokenizer's output into a structured list of commands, each a list of words with their subtype (bare/braced/quoted) and byte range, skipping comments and respecting command separators.

**Architecture:** Second piece of the standalone Go LSP server (see `docs/plans/2026-06-06-goto-def-ref-design.md`). Plan 1 built `tcl.Scan` (tokens). This plan adds `tcl.Parse`, which consumes those tokens into `[]Command`. Braced/quoted words are kept **opaque** here (one `Word` each); recursing into braced *bodies* (e.g. `namespace eval`/`proc` bodies) and intra-word `$var`/`[cmd]` analysis are later plans, done once context tells us a braced word is a body.

**Tech Stack:** Go 1.23+ (local toolchain 1.26.4), standard `testing`.

---

## File structure

- `server/internal/tcl/parser.go` — `Word`, `WordKind`, `Command`, and `Parse`.
- `server/internal/tcl/parser_test.go` — table-driven tests.

Reuses `Scan`, `Token`, `Kind`, `KindWord`/`KindNewline`/`KindSemicolon`/`KindComment`/`KindEOF` from Plan 1 (`scanner.go`).

---

## Task 1: Types and empty-input parse

**Files:**
- Create: `server/internal/tcl/parser.go`
- Create: `server/internal/tcl/parser_test.go`

- [ ] **Step 1: Write the failing test**

Create `server/internal/tcl/parser_test.go`:

```go
package tcl

import (
	"reflect"
	"testing"
)

func TestParseEmpty(t *testing.T) {
	got := Parse("")
	if len(got) != 0 {
		t.Fatalf("Parse(\"\") = %#v, want no commands", got)
	}
}

func TestParseWhitespaceOnly(t *testing.T) {
	got := Parse("   \n\t\n")
	if len(got) != 0 {
		t.Fatalf("Parse(whitespace) = %#v, want no commands", got)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `server/`): `go test ./internal/tcl/ -run TestParse`
Expected: FAIL — compile error, `undefined: Parse`.

- [ ] **Step 3: Write minimal implementation**

Create `server/internal/tcl/parser.go`:

```go
package tcl

// WordKind classifies a word by its delimiter.
type WordKind int

const (
	WordBare   WordKind = iota // bareword (may contain $var and [cmd] spans)
	WordBraced                 // {braced} word — opaque literal at this layer
	WordQuoted                 // "quoted" word
)

// Word is one word of a command, with its raw text and byte range [Start,End).
type Word struct {
	Kind  WordKind
	Text  string
	Start int
	End   int
}

// Command is a single TCL command: an ordered list of words.
type Command struct {
	Words []Word
}

// Parse tokenizes src and groups the tokens into commands. Comments are
// discarded; newline and semicolon separate commands; empty commands (from
// blank lines or runs of separators) are omitted.
func Parse(src string) []Command {
	toks := Scan(src)
	var cmds []Command
	var cur []Word
	flush := func() {
		if len(cur) > 0 {
			cmds = append(cmds, Command{Words: cur})
			cur = nil
		}
	}
	for _, tk := range toks {
		switch tk.Kind {
		case KindWord:
			cur = append(cur, wordFromToken(tk))
		case KindNewline, KindSemicolon, KindEOF:
			flush()
		case KindComment:
			// not part of any command
		}
	}
	return cmds
}

func wordFromToken(tk Token) Word {
	k := WordBare
	if len(tk.Text) > 0 {
		switch tk.Text[0] {
		case '{':
			k = WordBraced
		case '"':
			k = WordQuoted
		}
	}
	return Word{Kind: k, Text: tk.Text, Start: tk.Start, End: tk.End}
}
```

- [ ] **Step 4: Run test to verify it passes**

Run (from `server/`): `go test ./internal/tcl/ -run TestParse`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add server/internal/tcl/parser.go server/internal/tcl/parser_test.go
git commit -m "feat(tcl): parse tokens into commands (types + empty input)"
```

---

## Task 2: A single command of barewords

**Files:**
- Modify: `server/internal/tcl/parser_test.go`

- [ ] **Step 1: Write the test**

Add to `server/internal/tcl/parser_test.go`:

```go
func TestParseSingleCommand(t *testing.T) {
	got := Parse("set x 1")
	want := []Command{
		{Words: []Word{
			{Kind: WordBare, Text: "set", Start: 0, End: 3},
			{Kind: WordBare, Text: "x", Start: 4, End: 5},
			{Kind: WordBare, Text: "1", Start: 6, End: 7},
		}},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("\n got: %#v\nwant: %#v", got, want)
	}
}
```

- [ ] **Step 2: Run test to verify it passes**

Run (from `server/`): `go test ./internal/tcl/ -run TestParseSingleCommand`
Expected: PASS (Task 1's implementation already covers this — this test locks the word-range behavior).

- [ ] **Step 3: Commit**

```bash
git add server/internal/tcl/parser_test.go
git commit -m "test(tcl): single command of barewords with ranges"
```

---

## Task 3: Multiple commands via separators

**Files:**
- Modify: `server/internal/tcl/parser_test.go`

- [ ] **Step 1: Write the test**

Add to `server/internal/tcl/parser_test.go`:

```go
func TestParseMultipleCommands(t *testing.T) {
	got := Parse("set x 1\nputs $x;incr x")
	if len(got) != 3 {
		t.Fatalf("got %d commands, want 3: %#v", len(got), got)
	}
	// Command word counts: [set x 1], [puts $x], [incr x]
	wantCounts := []int{3, 2, 2}
	for i, c := range got {
		if len(c.Words) != wantCounts[i] {
			t.Fatalf("command %d has %d words, want %d: %#v", i, len(c.Words), wantCounts[i], c)
		}
	}
	// First word of each command.
	wantHeads := []string{"set", "puts", "incr"}
	for i, c := range got {
		if c.Words[0].Text != wantHeads[i] {
			t.Fatalf("command %d head = %q, want %q", i, c.Words[0].Text, wantHeads[i])
		}
	}
}
```

- [ ] **Step 2: Run test to verify it passes**

Run (from `server/`): `go test ./internal/tcl/ -run TestParseMultipleCommands`
Expected: PASS (newline and semicolon both flush the current command).

- [ ] **Step 3: Commit**

```bash
git add server/internal/tcl/parser_test.go
git commit -m "test(tcl): split commands on newline and semicolon"
```

---

## Task 4: Comments are not commands

**Files:**
- Modify: `server/internal/tcl/parser_test.go`

- [ ] **Step 1: Write the test**

Add to `server/internal/tcl/parser_test.go`:

```go
func TestParseSkipsComments(t *testing.T) {
	src := "# a comment\nset x 1\n# another\nputs $x"
	got := Parse(src)
	if len(got) != 2 {
		t.Fatalf("got %d commands, want 2 (comments skipped): %#v", len(got), got)
	}
	if got[0].Words[0].Text != "set" || got[1].Words[0].Text != "puts" {
		t.Fatalf("unexpected command heads: %#v", got)
	}
}
```

- [ ] **Step 2: Run test to verify it passes**

Run (from `server/`): `go test ./internal/tcl/ -run TestParseSkipsComments`
Expected: PASS (the `KindComment` case adds nothing; the following newline flushes an already-empty command).

- [ ] **Step 3: Commit**

```bash
git add server/internal/tcl/parser_test.go
git commit -m "test(tcl): comments are not parsed as commands"
```

---

## Task 5: Word-kind classification (braced / quoted / bare)

**Files:**
- Modify: `server/internal/tcl/parser_test.go`

- [ ] **Step 1: Write the test**

Add to `server/internal/tcl/parser_test.go`:

```go
func TestParseWordKinds(t *testing.T) {
	got := Parse(`proc p {a b} "hello world"`)
	if len(got) != 1 {
		t.Fatalf("got %d commands, want 1: %#v", len(got), got)
	}
	words := got[0].Words
	wantKinds := []WordKind{WordBare, WordBare, WordBraced, WordQuoted}
	if len(words) != len(wantKinds) {
		t.Fatalf("got %d words, want %d: %#v", len(words), len(wantKinds), words)
	}
	for i, w := range words {
		if w.Kind != wantKinds[i] {
			t.Fatalf("word %d (%q) kind = %d, want %d", i, w.Text, w.Kind, wantKinds[i])
		}
	}
	// Braced/quoted word text includes its delimiters.
	if words[2].Text != "{a b}" {
		t.Fatalf("braced word text = %q, want %q", words[2].Text, "{a b}")
	}
	if words[3].Text != `"hello world"` {
		t.Fatalf("quoted word text = %q, want %q", words[3].Text, `"hello world"`)
	}
}
```

- [ ] **Step 2: Run test to verify it passes**

Run (from `server/`): `go test ./internal/tcl/ -run TestParseWordKinds`
Expected: PASS (`wordFromToken` classifies on the first byte).

- [ ] **Step 3: Commit**

```bash
git add server/internal/tcl/parser_test.go
git commit -m "test(tcl): classify word kinds (bare/braced/quoted)"
```

---

## Task 6: Realistic snippet integration + byte-range fidelity

**Files:**
- Modify: `server/internal/tcl/parser_test.go`

- [ ] **Step 1: Write the test**

Add to `server/internal/tcl/parser_test.go`:

```go
func TestParseRealisticSnippet(t *testing.T) {
	// A namespace command whose body is one (opaque) braced word at this layer.
	src := "namespace eval ::app {\n    set v 1\n}"
	got := Parse(src)
	if len(got) != 1 {
		t.Fatalf("got %d commands, want 1: %#v", len(got), got)
	}
	w := got[0].Words
	if len(w) != 4 {
		t.Fatalf("got %d words, want 4: %#v", len(w), w)
	}
	if w[0].Text != "namespace" || w[1].Text != "eval" || w[2].Text != "::app" {
		t.Fatalf("unexpected heads: %q %q %q", w[0].Text, w[1].Text, w[2].Text)
	}
	if w[3].Kind != WordBraced {
		t.Fatalf("body word kind = %d, want WordBraced", w[3].Kind)
	}
	// The body word's range slices back to its exact source text.
	if src[w[3].Start:w[3].End] != w[3].Text {
		t.Fatalf("body range mismatch: src[%d:%d]=%q text=%q", w[3].Start, w[3].End, src[w[3].Start:w[3].End], w[3].Text)
	}
	if w[3].Text != "{\n    set v 1\n}" {
		t.Fatalf("body text = %q", w[3].Text)
	}
}
```

- [ ] **Step 2: Run the full suite**

Run (from `server/`): `go vet ./...`
Then: `go test ./...`
Expected: clean vet; all tests PASS (Plan 1 + Plan 2).

- [ ] **Step 3: Commit**

```bash
git add server/internal/tcl/parser_test.go
git commit -m "test(tcl): realistic snippet and body-range fidelity"
```

---

## Done criteria for Plan 2

- `go vet ./...` clean; `go test ./...` all pass.
- `tcl.Parse(src)` returns `[]Command`, each a `[]Word` with `WordKind` (bare/braced/quoted) and exact byte ranges; comments discarded; commands split on newline/semicolon; no empty commands. Braced/quoted words remain opaque single words (delimiters included).

**Next:** Plan 3 — intra-word analysis: scan bareword/quoted word interiors for `$var` references and `[cmd]` substitution spans (recursing into the latter), producing per-identifier occurrences with byte ranges. Then Plan 4 — context walker (namespace + frame kind) + scope-command recognition + the resolver contract.
