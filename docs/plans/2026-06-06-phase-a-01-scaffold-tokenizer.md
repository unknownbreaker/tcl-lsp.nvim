# Phase A — Plan 1: Scaffold + TCL Tokenizer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stand up the Go server project and a tolerant, hand-written TCL tokenizer that splits source into commands, words, separators, and comments with correct byte offsets.

**Architecture:** A standalone Go LSP server (see `docs/plans/2026-06-06-goto-def-ref-design.md`). This plan delivers the foundation: a Go module under `server/` and the `tcl` package's word/command scanner — the genuinely tricky part of TCL parsing (brace/quote/bracket/backslash-aware word splitting). The tokenizer emits whole words (raw text incl. delimiters); intra-word structure (`$var`, `[cmd]`) is the next plan's job.

**Tech Stack:** Go 1.23, standard `testing` package, GitHub Actions.

---

## File structure

- `server/go.mod` — Go module `github.com/unknownbreaker/tcl-lsp`.
- `server/internal/tcl/doc.go` — package doc.
- `server/internal/tcl/scanner.go` — the tokenizer (types + `Scan`).
- `server/internal/tcl/scanner_test.go` — table-driven tests.
- `.github/workflows/server-ci.yml` — vet + test on changes under `server/`.

Reference for tricky quoting/bracing rules: `archive-v1:tcl/core/tokenizer.tcl` (`git show archive-v1:tcl/core/tokenizer.tcl`).

---

## Task 1: Project scaffold

**Files:**
- Create: `server/go.mod`
- Create: `server/internal/tcl/doc.go`
- Create: `.github/workflows/server-ci.yml`

- [ ] **Step 1: Create the Go module file**

Create `server/go.mod`:

```
module github.com/unknownbreaker/tcl-lsp

go 1.23
```

- [ ] **Step 2: Create the package doc file**

Create `server/internal/tcl/doc.go`:

```go
// Package tcl provides a tolerant, hand-written tokenizer and structural parser
// for TCL source, scoped to the needs of goto-definition and goto-reference.
//
// The tokenizer never panics on malformed input: unterminated braces, quotes,
// and brackets are scanned to end-of-input rather than treated as errors, so the
// parser can still produce best-effort results for code that is mid-edit.
package tcl
```

- [ ] **Step 3: Verify the toolchain builds**

Run: `cd server && go vet ./...`
Expected: no output, exit code 0 (a package with no Go files yet still vets clean once `doc.go` exists).

- [ ] **Step 4: Add CI workflow**

Create `.github/workflows/server-ci.yml`:

```yaml
name: server-ci
on:
  push:
    paths: ['server/**', '.github/workflows/server-ci.yml']
  pull_request:
    paths: ['server/**', '.github/workflows/server-ci.yml']
jobs:
  test:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: server
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-go@v5
        with:
          go-version: '1.23'
      - run: go vet ./...
      - run: go test ./...
```

- [ ] **Step 5: Commit**

```bash
git add server/go.mod server/internal/tcl/doc.go .github/workflows/server-ci.yml
git commit -m "chore(server): scaffold Go module and CI"
```

---

## Task 2: Token types and empty-input scan

**Files:**
- Create: `server/internal/tcl/scanner.go`
- Create: `server/internal/tcl/scanner_test.go`

- [ ] **Step 1: Write the failing test**

Create `server/internal/tcl/scanner_test.go`:

```go
package tcl

import (
	"reflect"
	"testing"
)

// kt is a compact (kind, text) pair for readable assertions.
type kt struct {
	K Kind
	T string
}

func summarize(toks []Token) []kt {
	out := make([]kt, len(toks))
	for i, tk := range toks {
		out[i] = kt{tk.Kind, tk.Text}
	}
	return out
}

func TestScanEmpty(t *testing.T) {
	got := summarize(Scan(""))
	want := []kt{{KindEOF, ""}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("Scan(\"\")\n got: %#v\nwant: %#v", got, want)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && go test ./internal/tcl/`
Expected: FAIL — compile error, `undefined: Scan`, `undefined: Kind`, `undefined: Token`, `undefined: KindEOF`.

- [ ] **Step 3: Write minimal implementation**

Create `server/internal/tcl/scanner.go`:

```go
package tcl

// Kind enumerates the token categories the scanner emits.
type Kind int

const (
	KindEOF       Kind = iota // end of input
	KindNewline               // "\n" — a command separator
	KindSemicolon             // ";"  — a command separator
	KindComment               // "# ..." to end of line (only at command start)
	KindWord                  // one word: bare, {braced}, or "quoted" (raw text)
)

// Token is a lexical unit with its raw source text and byte range [Start,End).
type Token struct {
	Kind  Kind
	Text  string
	Start int
	End   int
}

// Scan tokenizes src into a slice of tokens always terminated by KindEOF.
func Scan(src string) []Token {
	s := &scanner{src: src, atCommandStart: true}
	return s.scan()
}

type scanner struct {
	src            string
	pos            int
	atCommandStart bool
	toks           []Token
}

func (s *scanner) emit(k Kind, start, end int) {
	s.toks = append(s.toks, Token{Kind: k, Text: s.src[start:end], Start: start, End: end})
}

func (s *scanner) scan() []Token {
	// Word/separator/comment branches are added in later tasks.
	s.emit(KindEOF, s.pos, s.pos)
	return s.toks
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd server && go test ./internal/tcl/`
Expected: PASS (`ok` for package `internal/tcl`).

- [ ] **Step 5: Commit**

```bash
git add server/internal/tcl/scanner.go server/internal/tcl/scanner_test.go
git commit -m "feat(tcl): token types and empty-input scan"
```

---

## Task 3: Barewords and whitespace

**Files:**
- Modify: `server/internal/tcl/scanner.go`
- Modify: `server/internal/tcl/scanner_test.go`

- [ ] **Step 1: Write the failing test**

Add to `server/internal/tcl/scanner_test.go`:

```go
func TestScanBarewords(t *testing.T) {
	got := summarize(Scan("set x 1"))
	want := []kt{
		{KindWord, "set"},
		{KindWord, "x"},
		{KindWord, "1"},
		{KindEOF, ""},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("Scan(\"set x 1\")\n got: %#v\nwant: %#v", got, want)
	}
}

func TestScanLeadingAndTrailingSpaces(t *testing.T) {
	got := summarize(Scan("  ab\tcd  "))
	want := []kt{
		{KindWord, "ab"},
		{KindWord, "cd"},
		{KindEOF, ""},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf(" got: %#v\nwant: %#v", got, want)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && go test ./internal/tcl/ -run TestScanBarewords`
Expected: FAIL — got only `[{KindEOF ""}]`.

- [ ] **Step 3: Write minimal implementation**

Replace the `scan` method in `server/internal/tcl/scanner.go` and add `scanWord`/`scanBare`:

```go
func (s *scanner) scan() []Token {
	for s.pos < len(s.src) {
		c := s.src[s.pos]
		switch {
		case c == ' ' || c == '\t':
			s.pos++ // inter-word whitespace is not emitted
		default:
			s.scanWord()
			s.atCommandStart = false
		}
	}
	s.emit(KindEOF, s.pos, s.pos)
	return s.toks
}

func (s *scanner) scanWord() {
	start := s.pos
	s.scanBare()
	s.emit(KindWord, start, s.pos)
}

// scanBare advances past a bareword, stopping at unescaped word terminators.
func (s *scanner) scanBare() {
	for s.pos < len(s.src) {
		c := s.src[s.pos]
		switch c {
		case ' ', '\t', '\n', ';':
			return
		default:
			s.pos++
		}
	}
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd server && go test ./internal/tcl/`
Expected: PASS (all three tests).

- [ ] **Step 5: Commit**

```bash
git add server/internal/tcl/scanner.go server/internal/tcl/scanner_test.go
git commit -m "feat(tcl): scan barewords separated by whitespace"
```

---

## Task 4: Command separators (newline and semicolon)

**Files:**
- Modify: `server/internal/tcl/scanner.go`
- Modify: `server/internal/tcl/scanner_test.go`

- [ ] **Step 1: Write the failing test**

Add to `server/internal/tcl/scanner_test.go`:

```go
func TestScanSeparators(t *testing.T) {
	got := summarize(Scan("a b\nc;d"))
	want := []kt{
		{KindWord, "a"},
		{KindWord, "b"},
		{KindNewline, "\n"},
		{KindWord, "c"},
		{KindSemicolon, ";"},
		{KindWord, "d"},
		{KindEOF, ""},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf(" got: %#v\nwant: %#v", got, want)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && go test ./internal/tcl/ -run TestScanSeparators`
Expected: FAIL — `\n` and `;` are currently swallowed into barewords (e.g. word `"b\nc"`).

- [ ] **Step 3: Write minimal implementation**

Replace the `scan` method in `server/internal/tcl/scanner.go` (adds the newline/semicolon branches; `scanBare` already stops at `\n`/`;`):

```go
func (s *scanner) scan() []Token {
	for s.pos < len(s.src) {
		c := s.src[s.pos]
		switch {
		case c == ' ' || c == '\t':
			s.pos++
		case c == '\n':
			s.emit(KindNewline, s.pos, s.pos+1)
			s.pos++
			s.atCommandStart = true
		case c == ';':
			s.emit(KindSemicolon, s.pos, s.pos+1)
			s.pos++
			s.atCommandStart = true
		default:
			s.scanWord()
			s.atCommandStart = false
		}
	}
	s.emit(KindEOF, s.pos, s.pos)
	return s.toks
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd server && go test ./internal/tcl/`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add server/internal/tcl/scanner.go server/internal/tcl/scanner_test.go
git commit -m "feat(tcl): emit newline and semicolon as command separators"
```

---

## Task 5: Comments

A `#` begins a comment **only at command start** (the position where a new command/word is expected). Leading whitespace before `#` is allowed. The comment runs to end of line; the terminating newline is emitted separately as a separator.

**Files:**
- Modify: `server/internal/tcl/scanner.go`
- Modify: `server/internal/tcl/scanner_test.go`

- [ ] **Step 1: Write the failing test**

Add to `server/internal/tcl/scanner_test.go`:

```go
func TestScanComment(t *testing.T) {
	got := summarize(Scan("# hi there\nset x 1"))
	want := []kt{
		{KindComment, "# hi there"},
		{KindNewline, "\n"},
		{KindWord, "set"},
		{KindWord, "x"},
		{KindWord, "1"},
		{KindEOF, ""},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf(" got: %#v\nwant: %#v", got, want)
	}
}

func TestHashMidCommandIsNotComment(t *testing.T) {
	// `#` is only a comment at command start; mid-command it is a literal word.
	got := summarize(Scan("set x #y"))
	want := []kt{
		{KindWord, "set"},
		{KindWord, "x"},
		{KindWord, "#y"},
		{KindEOF, ""},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf(" got: %#v\nwant: %#v", got, want)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && go test ./internal/tcl/ -run TestScanComment`
Expected: FAIL — `# hi there` is currently scanned as barewords `#`/`hi`/`there`.

- [ ] **Step 3: Write minimal implementation**

In `server/internal/tcl/scanner.go`, add a `#`-at-command-start branch to `scan` (place it immediately before the `default` branch) and add `scanComment`:

```go
		case c == '#' && s.atCommandStart:
			s.scanComment()
		default:
```

```go
// scanComment advances over a comment from '#' to (but not including) newline.
// A backslash-newline continues the comment onto the next physical line.
func (s *scanner) scanComment() {
	start := s.pos
	for s.pos < len(s.src) && s.src[s.pos] != '\n' {
		if s.src[s.pos] == '\\' && s.pos+1 < len(s.src) {
			s.pos += 2
			continue
		}
		s.pos++
	}
	s.emit(KindComment, start, s.pos)
}
```

Note: whitespace skipping does not change `atCommandStart`, so `   # x` is still recognized as a comment.

- [ ] **Step 4: Run test to verify it passes**

Run: `cd server && go test ./internal/tcl/`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add server/internal/tcl/scanner.go server/internal/tcl/scanner_test.go
git commit -m "feat(tcl): scan comments at command start"
```

---

## Task 6: Braced words

A word beginning with `{` reads to the matching `}`, with nesting. Inside braces, `\{` and `\}` (any backslash pair) do not affect nesting. Unterminated braces scan to end-of-input (tolerant). The emitted word text **includes** the braces.

**Files:**
- Modify: `server/internal/tcl/scanner.go`
- Modify: `server/internal/tcl/scanner_test.go`

- [ ] **Step 1: Write the failing test**

Add to `server/internal/tcl/scanner_test.go`:

```go
func TestScanBracedWord(t *testing.T) {
	got := summarize(Scan("proc p {a b} {body here}"))
	want := []kt{
		{KindWord, "proc"},
		{KindWord, "p"},
		{KindWord, "{a b}"},
		{KindWord, "{body here}"},
		{KindEOF, ""},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf(" got: %#v\nwant: %#v", got, want)
	}
}

func TestScanNestedBraces(t *testing.T) {
	got := summarize(Scan("set x {a {b} c}"))
	want := []kt{
		{KindWord, "set"},
		{KindWord, "x"},
		{KindWord, "{a {b} c}"},
		{KindEOF, ""},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf(" got: %#v\nwant: %#v", got, want)
	}
}

func TestScanUnterminatedBrace(t *testing.T) {
	got := summarize(Scan("set x {a b"))
	want := []kt{
		{KindWord, "set"},
		{KindWord, "x"},
		{KindWord, "{a b"},
		{KindEOF, ""},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf(" got: %#v\nwant: %#v", got, want)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && go test ./internal/tcl/ -run TestScanBracedWord`
Expected: FAIL — `{a b}` is split at the space into `{a` and `b}`.

- [ ] **Step 3: Write minimal implementation**

In `server/internal/tcl/scanner.go`, replace `scanWord` to dispatch on the first character, and add `scanBraced`:

```go
func (s *scanner) scanWord() {
	start := s.pos
	switch s.src[s.pos] {
	case '{':
		s.scanBraced()
	default:
		s.scanBare()
	}
	s.emit(KindWord, start, s.pos)
}

// scanBraced advances over a {braced} word, honoring nesting. Backslash escapes
// the next byte so \{ and \} do not change depth. Tolerant of unterminated input.
func (s *scanner) scanBraced() {
	depth := 0
	for s.pos < len(s.src) {
		c := s.src[s.pos]
		switch {
		case c == '\\' && s.pos+1 < len(s.src):
			s.pos += 2
			continue
		case c == '{':
			depth++
		case c == '}':
			depth--
			if depth == 0 {
				s.pos++ // consume closing brace
				return
			}
		}
		s.pos++
	}
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd server && go test ./internal/tcl/`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add server/internal/tcl/scanner.go server/internal/tcl/scanner_test.go
git commit -m "feat(tcl): scan braced words with nesting"
```

---

## Task 7: Quoted words

A word beginning with `"` reads to the next unescaped `"`. Backslash escapes the next byte. Whitespace and separators inside quotes are part of the word. The emitted word text **includes** the quotes. Unterminated quotes scan to end-of-input (tolerant).

**Files:**
- Modify: `server/internal/tcl/scanner.go`
- Modify: `server/internal/tcl/scanner_test.go`

- [ ] **Step 1: Write the failing test**

Add to `server/internal/tcl/scanner_test.go`:

```go
func TestScanQuotedWord(t *testing.T) {
	got := summarize(Scan(`set x "a b;c"`))
	want := []kt{
		{KindWord, "set"},
		{KindWord, "x"},
		{KindWord, `"a b;c"`},
		{KindEOF, ""},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf(" got: %#v\nwant: %#v", got, want)
	}
}

func TestScanQuotedWithEscapedQuote(t *testing.T) {
	got := summarize(Scan(`puts "she said \"hi\""`))
	want := []kt{
		{KindWord, "puts"},
		{KindWord, `"she said \"hi\""`},
		{KindEOF, ""},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf(" got: %#v\nwant: %#v", got, want)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && go test ./internal/tcl/ -run TestScanQuotedWord`
Expected: FAIL — the quoted word is split at the embedded space/semicolon.

- [ ] **Step 3: Write minimal implementation**

In `server/internal/tcl/scanner.go`, add a `'"'` case to `scanWord`'s switch (before `default`) and add `scanQuoted`:

```go
	case '"':
		s.scanQuoted()
```

```go
// scanQuoted advances over a "quoted" word to the next unescaped quote.
// Tolerant of unterminated input.
func (s *scanner) scanQuoted() {
	s.pos++ // opening quote
	for s.pos < len(s.src) {
		c := s.src[s.pos]
		switch {
		case c == '\\' && s.pos+1 < len(s.src):
			s.pos += 2
			continue
		case c == '"':
			s.pos++ // closing quote
			return
		}
		s.pos++
	}
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd server && go test ./internal/tcl/`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add server/internal/tcl/scanner.go server/internal/tcl/scanner_test.go
git commit -m "feat(tcl): scan quoted words"
```

---

## Task 8: Bracket command-substitution spans inside barewords

`[...]` command substitution can appear inside a bareword and may contain spaces, separators, and newlines without ending the word. The bracket span is balanced (nesting), backslash-aware, and tolerant of unterminated input.

**Files:**
- Modify: `server/internal/tcl/scanner.go`
- Modify: `server/internal/tcl/scanner_test.go`

- [ ] **Step 1: Write the failing test**

Add to `server/internal/tcl/scanner_test.go`:

```go
func TestScanBracketInBareword(t *testing.T) {
	got := summarize(Scan("set x [expr {1 + 2}]"))
	want := []kt{
		{KindWord, "set"},
		{KindWord, "x"},
		{KindWord, "[expr {1 + 2}]"},
		{KindEOF, ""},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf(" got: %#v\nwant: %#v", got, want)
	}
}

func TestScanNestedBrackets(t *testing.T) {
	got := summarize(Scan("set x a[b [c d]]e"))
	want := []kt{
		{KindWord, "set"},
		{KindWord, "x"},
		{KindWord, "a[b [c d]]e"},
		{KindEOF, ""},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf(" got: %#v\nwant: %#v", got, want)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && go test ./internal/tcl/ -run TestScanBracketInBareword`
Expected: FAIL — the word ends at the space inside `[expr {1 + 2}]`.

- [ ] **Step 3: Write minimal implementation**

In `server/internal/tcl/scanner.go`, extend `scanBare` to skip bracket spans and backslash escapes, and add `scanBracket`:

```go
func (s *scanner) scanBare() {
	for s.pos < len(s.src) {
		c := s.src[s.pos]
		switch {
		case c == '\\' && s.pos+1 < len(s.src):
			s.pos += 2
		case c == '[':
			s.scanBracket()
		case c == ' ' || c == '\t' || c == '\n' || c == ';':
			return
		default:
			s.pos++
		}
	}
}

// scanBracket advances over a balanced [command substitution] span, backslash-
// aware. Tolerant of unterminated input. (Pragmatic depth counting; a closing
// bracket inside a nested brace is a rare edge case accepted as a known limit.)
func (s *scanner) scanBracket() {
	depth := 0
	for s.pos < len(s.src) {
		c := s.src[s.pos]
		switch {
		case c == '\\' && s.pos+1 < len(s.src):
			s.pos += 2
			continue
		case c == '[':
			depth++
		case c == ']':
			depth--
			if depth == 0 {
				s.pos++
				return
			}
		}
		s.pos++
	}
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd server && go test ./internal/tcl/`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add server/internal/tcl/scanner.go server/internal/tcl/scanner_test.go
git commit -m "feat(tcl): keep bracket substitution spans inside barewords"
```

---

## Task 9: Backslash escapes and line continuation

A backslash escapes the next byte in a bareword (so `\ ` and `\;` are literal, not terminators). A backslash immediately before a newline is a **line continuation**: it acts as whitespace and does **not** start a new command.

**Files:**
- Modify: `server/internal/tcl/scanner.go`
- Modify: `server/internal/tcl/scanner_test.go`

- [ ] **Step 1: Write the failing test**

Add to `server/internal/tcl/scanner_test.go`:

```go
func TestScanEscapedSpaceInBareword(t *testing.T) {
	got := summarize(Scan(`set x a\ b`))
	want := []kt{
		{KindWord, "set"},
		{KindWord, "x"},
		{KindWord, `a\ b`},
		{KindEOF, ""},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf(" got: %#v\nwant: %#v", got, want)
	}
}

func TestScanLineContinuation(t *testing.T) {
	// Backslash-newline is whitespace, not a command separator.
	got := summarize(Scan("set x \\\n1"))
	want := []kt{
		{KindWord, "set"},
		{KindWord, "x"},
		{KindWord, "1"},
		{KindEOF, ""},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf(" got: %#v\nwant: %#v", got, want)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd server && go test ./internal/tcl/ -run TestScanLineContinuation`
Expected: FAIL — the `\` then `\n` currently emits a `KindNewline` separator (and the backslash becomes its own word).

- [ ] **Step 3: Write minimal implementation**

In `server/internal/tcl/scanner.go`, add a line-continuation branch to `scan`, placed **before** the `c == '\n'` branch (`scanBare` already handles in-word escapes from Task 8):

```go
		case c == '\\' && s.pos+1 < len(s.src) && s.src[s.pos+1] == '\n':
			s.pos += 2 // line continuation acts as whitespace
```

- [ ] **Step 4: Run test to verify it passes**

Run: `cd server && go test ./internal/tcl/`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add server/internal/tcl/scanner.go server/internal/tcl/scanner_test.go
git commit -m "feat(tcl): handle backslash escapes and line continuation"
```

---

## Task 10: Realistic integration test

Verify the scanner handles a small but representative multi-command snippet end to end, including byte offsets (which the parser will rely on for goto-def/ref position mapping).

**Files:**
- Modify: `server/internal/tcl/scanner_test.go`

- [ ] **Step 1: Write the test**

Add to `server/internal/tcl/scanner_test.go`:

```go
func TestScanRealisticSnippet(t *testing.T) {
	src := "namespace eval ::app {\n    variable v 1\n    proc f {x} { return [expr {$x + $v}] }\n}"
	got := summarize(Scan(src))
	want := []kt{
		{KindWord, "namespace"},
		{KindWord, "eval"},
		{KindWord, "::app"},
		{KindWord, "{\n    variable v 1\n    proc f {x} { return [expr {$x + $v}] }\n}"},
		{KindEOF, ""},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf(" got: %#v\nwant: %#v", got, want)
	}
}

func TestTokenByteOffsetsAreExact(t *testing.T) {
	src := "set x 1"
	toks := Scan(src)
	// The word "x" sits at bytes [4,5).
	var xtok Token
	for _, tk := range toks {
		if tk.Kind == KindWord && tk.Text == "x" {
			xtok = tk
		}
	}
	if xtok.Start != 4 || xtok.End != 5 {
		t.Fatalf("x offsets: got [%d,%d), want [4,5)", xtok.Start, xtok.End)
	}
	if src[xtok.Start:xtok.End] != "x" {
		t.Fatalf("offset slice mismatch: %q", src[xtok.Start:xtok.End])
	}
}
```

- [ ] **Step 2: Run test to verify it passes**

Run: `cd server && go test ./internal/tcl/`
Expected: PASS. (No implementation change — this confirms the accumulated scanner. The whole `namespace eval` body is one braced word, which is correct: the parser recurses into braced bodies in Plan 2.)

- [ ] **Step 3: Run vet and the full suite**

Run: `cd server && go vet ./... && go test ./...`
Expected: clean vet, all tests PASS.

- [ ] **Step 4: Commit**

```bash
git add server/internal/tcl/scanner_test.go
git commit -m "test(tcl): realistic snippet and byte-offset integration tests"
```

---

## Done criteria for Plan 1

- `cd server && go test ./...` passes; `go vet ./...` is clean.
- `tcl.Scan` splits TCL source into `KindWord` / `KindNewline` / `KindSemicolon` / `KindComment` / `KindEOF` tokens with exact byte offsets, correctly handling braces (nested), quotes, bracket substitution spans, comments (command-start only), backslash escapes, and line continuation — tolerantly (no panics on unterminated input).

**Next:** Plan 2 — structural parser that consumes this token stream to produce the parser→resolver contract (commands, current namespace, frame kind, and per-identifier command-vs-variable classification), recursing into braced bodies.

