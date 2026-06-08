# Phase A — Plan 11: LSP framing + position conversion

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the two pure foundations of the LSP server: JSON-RPC message framing over stdio, and UTF-16 ↔ byte-offset position conversion.

**Architecture:** New `lsp` package (the protocol shell — see `docs/plans/2026-06-06-goto-def-ref-design.md`). This plan delivers `Conn` (read/write LSP messages with `Content-Length` framing) and the position math (LSP positions count UTF-16 code units; the resolver works in byte offsets). The Server, handlers, and `main.go` binary come in the next plan; the editor client config in the one after.

**Tech Stack:** Go 1.23+ (local 1.26.4), standard library only, `testing`.

---

## File structure

- `server/internal/lsp/jsonrpc.go` — `Message`, `ResponseError`, `Conn`, `NewConn`.
- `server/internal/lsp/jsonrpc_test.go`
- `server/internal/lsp/position.go` — `ByteOffset`, `LSPPosition`.
- `server/internal/lsp/position_test.go`

No imports beyond the standard library.

---

## Task 1: JSON-RPC framing (`Conn`)

**Files:**
- Create: `server/internal/lsp/jsonrpc.go`
- Create: `server/internal/lsp/jsonrpc_test.go`

- [ ] **Step 1: Write the failing test**

Create `server/internal/lsp/jsonrpc_test.go`:

```go
package lsp

import (
	"bytes"
	"encoding/json"
	"io"
	"testing"
)

func TestConnWriteThenRead(t *testing.T) {
	var out bytes.Buffer
	w := NewConn(bytes.NewReader(nil), &out)
	if err := w.Write(&Message{Method: "initialize", ID: json.RawMessage("1")}); err != nil {
		t.Fatalf("write: %v", err)
	}
	// The framed bytes must start with a Content-Length header.
	if !bytes.HasPrefix(out.Bytes(), []byte("Content-Length: ")) {
		t.Fatalf("missing Content-Length header: %q", out.String())
	}

	r := NewConn(bytes.NewReader(out.Bytes()), io.Discard)
	m, err := r.Read()
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if m.JSONRPC != "2.0" {
		t.Fatalf("jsonrpc = %q, want 2.0", m.JSONRPC)
	}
	if m.Method != "initialize" || string(m.ID) != "1" {
		t.Fatalf("round-trip mismatch: method=%q id=%q", m.Method, string(m.ID))
	}
}

func TestConnReadTwoMessages(t *testing.T) {
	var buf bytes.Buffer
	w := NewConn(bytes.NewReader(nil), &buf)
	_ = w.Write(&Message{Method: "a"})
	_ = w.Write(&Message{Method: "b"})

	r := NewConn(bytes.NewReader(buf.Bytes()), io.Discard)
	m1, err := r.Read()
	if err != nil || m1.Method != "a" {
		t.Fatalf("first message: %v / %q", err, m1.Method)
	}
	m2, err := r.Read()
	if err != nil || m2.Method != "b" {
		t.Fatalf("second message: %v / %q", err, m2.Method)
	}
}

func TestConnReadEOF(t *testing.T) {
	r := NewConn(bytes.NewReader(nil), io.Discard)
	if _, err := r.Read(); err != io.EOF {
		t.Fatalf("expected io.EOF on empty input, got %v", err)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/lsp/`
Expected: FAIL — the `lsp` package does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `server/internal/lsp/jsonrpc.go`:

```go
// Package lsp implements the Language Server Protocol shell (JSON-RPC framing,
// position conversion, and the request handlers) over stdio.
package lsp

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"strconv"
	"strings"
	"sync"
)

// Message is a JSON-RPC 2.0 message (request, notification, or response). Unused
// fields are omitted on the wire.
type Message struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id,omitempty"`
	Method  string          `json:"method,omitempty"`
	Params  json.RawMessage `json:"params,omitempty"`
	Result  json.RawMessage `json:"result,omitempty"`
	Error   *ResponseError  `json:"error,omitempty"`
}

// ResponseError is a JSON-RPC error object.
type ResponseError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

// Conn reads and writes LSP messages (Content-Length framed) over a stream.
type Conn struct {
	r  *bufio.Reader
	w  io.Writer
	mu sync.Mutex // serializes writes
}

// NewConn wraps a reader/writer pair (typically stdin/stdout).
func NewConn(r io.Reader, w io.Writer) *Conn {
	return &Conn{r: bufio.NewReader(r), w: w}
}

// Read reads one framed message. Returns io.EOF when the stream ends cleanly.
func (c *Conn) Read() (*Message, error) {
	contentLen := -1
	for {
		line, err := c.r.ReadString('\n')
		if err != nil {
			return nil, err
		}
		line = strings.TrimRight(line, "\r\n")
		if line == "" {
			break // blank line terminates the header block
		}
		if v, ok := strings.CutPrefix(line, "Content-Length:"); ok {
			n, err := strconv.Atoi(strings.TrimSpace(v))
			if err != nil {
				return nil, fmt.Errorf("invalid Content-Length: %w", err)
			}
			contentLen = n
		}
		// other headers (e.g. Content-Type) are ignored
	}
	if contentLen < 0 {
		return nil, fmt.Errorf("message missing Content-Length header")
	}
	body := make([]byte, contentLen)
	if _, err := io.ReadFull(c.r, body); err != nil {
		return nil, err
	}
	var m Message
	if err := json.Unmarshal(body, &m); err != nil {
		return nil, fmt.Errorf("invalid message body: %w", err)
	}
	return &m, nil
}

// Write frames and writes one message. Safe for concurrent use.
func (c *Conn) Write(m *Message) error {
	m.JSONRPC = "2.0"
	body, err := json.Marshal(m)
	if err != nil {
		return err
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if _, err := fmt.Fprintf(c.w, "Content-Length: %d\r\n\r\n", len(body)); err != nil {
		return err
	}
	_, err = c.w.Write(body)
	return err
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/lsp/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add server/internal/lsp/
git commit -m "feat(lsp): JSON-RPC Content-Length framing over stdio"
```

---

## Task 2: UTF-16 ↔ byte-offset position conversion

LSP positions are `{line, character}` where `character` counts **UTF-16 code units**; the resolver works in byte offsets. These two functions convert between them, handling multibyte runes.

**Files:**
- Create: `server/internal/lsp/position.go`
- Create: `server/internal/lsp/position_test.go`

- [ ] **Step 1: Write the failing test**

Create `server/internal/lsp/position_test.go`:

```go
package lsp

import "testing"

func TestByteOffsetAndPositionASCII(t *testing.T) {
	src := "set x 1\nputs $x"
	// Start of line 1 ("puts") is byte 8.
	if got := ByteOffset(src, 1, 0); got != 8 {
		t.Fatalf("ByteOffset(1,0) = %d, want 8", got)
	}
	line, ch := LSPPosition(src, 8)
	if line != 1 || ch != 0 {
		t.Fatalf("LSPPosition(8) = (%d,%d), want (1,0)", line, ch)
	}
	// `$x` is at byte 13 (line 1, char 5).
	if got := ByteOffset(src, 1, 5); got != 13 {
		t.Fatalf("ByteOffset(1,5) = %d, want 13", got)
	}
}

func TestPositionUTF16Multibyte(t *testing.T) {
	// "😀" (U+1F600) is 4 UTF-8 bytes and 2 UTF-16 code units.
	src := "x😀y" // x=byte0, 😀=bytes1..4, y=byte5
	line, ch := LSPPosition(src, 5)
	if line != 0 || ch != 3 { // 1 (x) + 2 (😀) = 3 UTF-16 units
		t.Fatalf("LSPPosition(5) = (%d,%d), want (0,3)", line, ch)
	}
	if got := ByteOffset(src, 0, 3); got != 5 {
		t.Fatalf("ByteOffset(0,3) = %d, want 5", got)
	}
	// "é" (U+00E9) is 2 UTF-8 bytes and 1 UTF-16 unit.
	src2 := "é!" // é=bytes0..1, !=byte2
	if got := ByteOffset(src2, 0, 1); got != 2 {
		t.Fatalf("ByteOffset on é: %d, want 2", got)
	}
}

func TestByteOffsetClampsBeyondLine(t *testing.T) {
	src := "ab\ncd"
	// A character past the end of the line clamps to the line end (byte 2).
	if got := ByteOffset(src, 0, 99); got != 2 {
		t.Fatalf("ByteOffset(0,99) = %d, want 2", got)
	}
	// A line past the end clamps to len(src).
	if got := ByteOffset(src, 99, 0); got != len(src) {
		t.Fatalf("ByteOffset(99,0) = %d, want %d", got, len(src))
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/lsp/ -run "TestByteOffset|TestPosition"`
Expected: FAIL — `ByteOffset`/`LSPPosition` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `server/internal/lsp/position.go`:

```go
package lsp

import (
	"unicode/utf16"
	"unicode/utf8"
)

// ByteOffset converts an LSP (line, character) position — where character counts
// UTF-16 code units — to a byte offset in src. Positions past the end of a line
// clamp to the line end; lines past the end clamp to len(src).
func ByteOffset(src string, line, character int) int {
	off := 0
	for curLine := 0; off < len(src) && curLine < line; off++ {
		if src[off] == '\n' {
			curLine++
		}
	}
	u16 := 0
	for off < len(src) && src[off] != '\n' && u16 < character {
		r, size := utf8.DecodeRuneInString(src[off:])
		u16 += utf16.RuneLen(r)
		off += size
	}
	return off
}

// LSPPosition converts a byte offset in src to an LSP (line, character) position,
// where character counts UTF-16 code units. Offsets past len(src) clamp to it.
func LSPPosition(src string, offset int) (line, character int) {
	if offset > len(src) {
		offset = len(src)
	}
	lineStart := 0
	for i := 0; i < offset; i++ {
		if src[i] == '\n' {
			line++
			lineStart = i + 1
		}
	}
	for i := lineStart; i < offset; {
		r, size := utf8.DecodeRuneInString(src[i:])
		character += utf16.RuneLen(r)
		i += size
	}
	return line, character
}
```

- [ ] **Step 4: Run the full suite**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server vet ./...`
Then: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./...`
Expected: clean vet; all tests PASS (tcl + index + resolve + lsp).

- [ ] **Step 5: Commit**

```bash
git add server/internal/lsp/
git commit -m "feat(lsp): UTF-16 <-> byte-offset position conversion"
```

---

## Done criteria for Plan 11

- `go vet ./...` clean; `go test ./...` all pass.
- `lsp.Conn` reads/writes JSON-RPC messages with `Content-Length` framing (clean `io.EOF` at end of stream, ignores unknown headers, serializes writes).
- `lsp.ByteOffset` / `lsp.LSPPosition` convert between LSP UTF-16 positions and byte offsets, correct for multibyte runes, clamping out-of-range inputs.

**Next:** Plan 12 — the LSP types (initialize/definition/references/didOpen/didChange/didClose), URI↔path helpers, the `Server` (lifecycle, document store, workspace indexing on init, wiring `textDocument/definition` and `textDocument/references` to the resolver), and `cmd/tcl-lsp/main.go` — producing the runnable `tcl-lsp` binary. Then Plan 13 — the Neovim/LazyVim client config + build/install docs + manual smoke test.
