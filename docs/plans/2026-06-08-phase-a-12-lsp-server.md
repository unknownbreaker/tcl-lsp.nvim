# Phase A — Plan 12: LSP Server + handlers + binary

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Wire the framing/position utilities, workspace index, and resolver into a working LSP server, and produce the runnable `tcl-lsp` binary.

**Architecture:** Extends the `lsp` package and adds `cmd/tcl-lsp/main.go` (see `docs/plans/2026-06-06-goto-def-ref-design.md`). The `Server` runs a synchronous read→dispatch loop (single goroutine, so no locking), handles lifecycle + document sync + `textDocument/definition`/`references`, converting LSP positions to byte offsets and resolver results back to LSP `Location`s.

**Tech Stack:** Go 1.23+ (local 1.26.4), standard library + the tcl/index/resolve packages, `testing`.

---

## File structure

- `server/internal/lsp/protocol.go` — LSP types + `uriToPath`/`pathToURI`.
- `server/internal/lsp/server.go` — `Server`, `NewServer`, `Run`, dispatch + handlers.
- `server/internal/lsp/server_test.go` — server tests over in-memory buffers.
- `server/cmd/tcl-lsp/main.go` — the binary entry point.

Imports `.../internal/index` and `.../internal/resolve` (in server.go).

---

## Task 1: LSP protocol types + URI helpers

**Files:**
- Create: `server/internal/lsp/protocol.go`
- Create: `server/internal/lsp/protocol_test.go`

- [ ] **Step 1: Write the failing test**

Create `server/internal/lsp/protocol_test.go`:

```go
package lsp

import "testing"

func TestURIRoundTrip(t *testing.T) {
	path := "/Users/x/a b.tcl" // space must be percent-encoded
	uri := pathToURI(path)
	if uri != "file:///Users/x/a%20b.tcl" {
		t.Fatalf("pathToURI = %q", uri)
	}
	if got := uriToPath(uri); got != path {
		t.Fatalf("uriToPath = %q, want %q", got, path)
	}
}

func TestURIToPathPlainPath(t *testing.T) {
	// A non-URI string is returned as-is (best effort).
	if got := uriToPath("/already/a/path.tcl"); got != "/already/a/path.tcl" {
		t.Fatalf("uriToPath plain = %q", got)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/lsp/ -run TestURI`
Expected: FAIL — `pathToURI`/`uriToPath` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `server/internal/lsp/protocol.go`:

```go
package lsp

import "net/url"

// Position is an LSP position (UTF-16 character units).
type Position struct {
	Line      int `json:"line"`
	Character int `json:"character"`
}

// Range is an LSP range.
type Range struct {
	Start Position `json:"start"`
	End   Position `json:"end"`
}

// Location is an LSP location.
type Location struct {
	URI   string `json:"uri"`
	Range Range  `json:"range"`
}

// TextDocumentIdentifier references a document by URI.
type TextDocumentIdentifier struct {
	URI string `json:"uri"`
}

// TextDocumentItem is a document with its full text.
type TextDocumentItem struct {
	URI  string `json:"uri"`
	Text string `json:"text"`
}

// DidOpenParams is textDocument/didOpen.
type DidOpenParams struct {
	TextDocument TextDocumentItem `json:"textDocument"`
}

// TextDocumentContentChangeEvent is one change (full-document sync: Text is the
// whole new content).
type TextDocumentContentChangeEvent struct {
	Text string `json:"text"`
}

// DidChangeParams is textDocument/didChange.
type DidChangeParams struct {
	TextDocument   TextDocumentIdentifier           `json:"textDocument"`
	ContentChanges []TextDocumentContentChangeEvent `json:"contentChanges"`
}

// DidCloseParams is textDocument/didClose.
type DidCloseParams struct {
	TextDocument TextDocumentIdentifier `json:"textDocument"`
}

// TextDocumentPositionParams is a position in a document (definition/references).
type TextDocumentPositionParams struct {
	TextDocument TextDocumentIdentifier `json:"textDocument"`
	Position     Position               `json:"position"`
}

// InitializeParams is the subset of initialize we use.
type InitializeParams struct {
	RootURI  string `json:"rootUri"`
	RootPath string `json:"rootPath"`
}

// InitializeResult advertises server capabilities.
type InitializeResult struct {
	Capabilities ServerCapabilities `json:"capabilities"`
}

// ServerCapabilities is the subset we advertise.
type ServerCapabilities struct {
	TextDocumentSync   int  `json:"textDocumentSync"` // 1 = full sync
	DefinitionProvider bool `json:"definitionProvider"`
	ReferencesProvider bool `json:"referencesProvider"`
}

// uriToPath converts a file:// URI to a filesystem path. A string that is not a
// file URI is returned unchanged (best effort).
func uriToPath(uri string) string {
	u, err := url.Parse(uri)
	if err != nil || u.Scheme != "file" {
		return uri
	}
	return u.Path
}

// pathToURI converts a filesystem path to a file:// URI.
func pathToURI(path string) string {
	u := url.URL{Scheme: "file", Path: path}
	return u.String()
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/lsp/ -run TestURI`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add server/internal/lsp/protocol.go server/internal/lsp/protocol_test.go
git commit -m "feat(lsp): protocol types and file URI <-> path helpers"
```

---

## Task 2: Server skeleton + lifecycle (initialize/shutdown/exit)

**Files:**
- Create: `server/internal/lsp/server.go`
- Create: `server/internal/lsp/server_test.go`

- [ ] **Step 1: Write the failing test**

Create `server/internal/lsp/server_test.go`:

```go
package lsp

import (
	"bytes"
	"encoding/json"
	"io"
	"testing"
)

// frame returns the framed bytes for one message (id nil => notification).
func frame(t *testing.T, method string, id interface{}, params interface{}) []byte {
	t.Helper()
	var buf bytes.Buffer
	c := NewConn(bytes.NewReader(nil), &buf)
	m := &Message{Method: method}
	if id != nil {
		b, _ := json.Marshal(id)
		m.ID = b
	}
	if params != nil {
		b, _ := json.Marshal(params)
		m.Params = b
	}
	if err := c.Write(m); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

// runServer feeds framed input bytes through a Server and returns its responses.
func runServer(t *testing.T, input []byte) []*Message {
	t.Helper()
	var out bytes.Buffer
	s := NewServer(NewConn(bytes.NewReader(input), &out))
	if err := s.Run(); err != nil {
		t.Fatalf("Run: %v", err)
	}
	c := NewConn(bytes.NewReader(out.Bytes()), io.Discard)
	var ms []*Message
	for {
		m, err := c.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			t.Fatalf("read response: %v", err)
		}
		ms = append(ms, m)
	}
	return ms
}

func responseByID(ms []*Message, id string) *Message {
	for _, m := range ms {
		if string(m.ID) == id {
			return m
		}
	}
	return nil
}

func TestServerInitializeCapabilities(t *testing.T) {
	var in bytes.Buffer
	in.Write(frame(t, "initialize", 1, InitializeParams{}))
	in.Write(frame(t, "exit", nil, nil))

	resp := responseByID(runServer(t, in.Bytes()), "1")
	if resp == nil {
		t.Fatal("no initialize response")
	}
	var res InitializeResult
	if err := json.Unmarshal(resp.Result, &res); err != nil {
		t.Fatalf("unmarshal result: %v", err)
	}
	if !res.Capabilities.DefinitionProvider || !res.Capabilities.ReferencesProvider {
		t.Fatalf("capabilities = %#v", res.Capabilities)
	}
	if res.Capabilities.TextDocumentSync != 1 {
		t.Fatalf("textDocumentSync = %d, want 1", res.Capabilities.TextDocumentSync)
	}
}

func TestServerShutdownThenExit(t *testing.T) {
	var in bytes.Buffer
	in.Write(frame(t, "shutdown", 2, nil))
	in.Write(frame(t, "exit", nil, nil))

	resp := responseByID(runServer(t, in.Bytes()), "2")
	if resp == nil || string(resp.Result) != "null" {
		t.Fatalf("shutdown response = %#v", resp)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/lsp/ -run TestServer`
Expected: FAIL — `NewServer`/`Server`/`Run` undefined.

- [ ] **Step 3: Write minimal implementation**

Create `server/internal/lsp/server.go`:

```go
package lsp

import (
	"encoding/json"
	"io"

	"github.com/unknownbreaker/tcl-lsp/internal/index"
	"github.com/unknownbreaker/tcl-lsp/internal/resolve"
)

// Server is a single-goroutine LSP server: it reads and dispatches messages
// sequentially, so the index/resolver need no locking.
type Server struct {
	conn *Conn
	ix   *index.Index
	res  *resolve.Resolver
	docs map[string]string // uri -> live text
}

// NewServer builds a server over conn with an empty index.
func NewServer(conn *Conn) *Server {
	ix := index.New()
	return &Server{conn: conn, ix: ix, res: resolve.New(ix), docs: map[string]string{}}
}

// Run reads and dispatches messages until exit or the stream ends.
func (s *Server) Run() error {
	for {
		m, err := s.conn.Read()
		if err != nil {
			if err == io.EOF {
				return nil
			}
			return err
		}
		if s.dispatch(m) {
			return nil
		}
	}
}

// dispatch handles one message; returns true to stop the server (exit).
func (s *Server) dispatch(m *Message) (stop bool) {
	switch m.Method {
	case "initialize":
		var p InitializeParams
		_ = json.Unmarshal(m.Params, &p)
		root := p.RootPath
		if root == "" && p.RootURI != "" {
			root = uriToPath(p.RootURI)
		}
		if root != "" {
			_ = s.ix.IndexDir(root) // best-effort; missing/permission errors are non-fatal
		}
		s.reply(m.ID, InitializeResult{Capabilities: ServerCapabilities{
			TextDocumentSync: 1, DefinitionProvider: true, ReferencesProvider: true,
		}})
	case "initialized":
		// notification; no-op
	case "shutdown":
		s.reply(m.ID, nil)
	case "exit":
		return true
	default:
		// Unknown request: reply null so the client does not hang. Unknown
		// notifications (no id) are ignored. Document-sync and feature methods
		// are added in the next task.
		if len(m.ID) > 0 {
			s.reply(m.ID, nil)
		}
	}
	return false
}

// reply writes a JSON-RPC response for the given id. A nil result is sent as
// JSON null.
func (s *Server) reply(id json.RawMessage, result interface{}) {
	raw := json.RawMessage("null")
	if result != nil {
		b, err := json.Marshal(result)
		if err != nil {
			return
		}
		raw = b
	}
	_ = s.conn.Write(&Message{ID: id, Result: raw})
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/lsp/ -run TestServer`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add server/internal/lsp/server.go server/internal/lsp/server_test.go
git commit -m "feat(lsp): server lifecycle (initialize/shutdown/exit) loop"
```

---

## Task 3: Document sync + definition/references handlers

**Files:**
- Modify: `server/internal/lsp/server.go`
- Modify: `server/internal/lsp/server_test.go`

- [ ] **Step 1: Write the failing test**

Add to `server/internal/lsp/server_test.go`:

```go
func TestServerDefinitionFlow(t *testing.T) {
	var in bytes.Buffer
	in.Write(frame(t, "initialize", 1, InitializeParams{}))
	in.Write(frame(t, "textDocument/didOpen", nil, DidOpenParams{
		TextDocument: TextDocumentItem{URI: "file:///lib.tcl", Text: "proc greet {} {}"}}))
	in.Write(frame(t, "textDocument/didOpen", nil, DidOpenParams{
		TextDocument: TextDocumentItem{URI: "file:///main.tcl", Text: "greet"}}))
	in.Write(frame(t, "textDocument/definition", 2, TextDocumentPositionParams{
		TextDocument: TextDocumentIdentifier{URI: "file:///main.tcl"},
		Position:     Position{Line: 0, Character: 0}}))
	in.Write(frame(t, "exit", nil, nil))

	resp := responseByID(runServer(t, in.Bytes()), "2")
	if resp == nil {
		t.Fatal("no definition response")
	}
	var locs []Location
	if err := json.Unmarshal(resp.Result, &locs); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(locs) != 1 || locs[0].URI != "file:///lib.tcl" {
		t.Fatalf("definition = %#v", locs)
	}
	// The range points at the `greet` proc name: line 0, chars 5..10.
	if locs[0].Range.Start != (Position{Line: 0, Character: 5}) ||
		locs[0].Range.End != (Position{Line: 0, Character: 10}) {
		t.Fatalf("range = %#v", locs[0].Range)
	}
}

func TestServerReferencesFlow(t *testing.T) {
	var in bytes.Buffer
	in.Write(frame(t, "initialize", 1, InitializeParams{}))
	in.Write(frame(t, "textDocument/didOpen", nil, DidOpenParams{
		TextDocument: TextDocumentItem{URI: "file:///lib.tcl", Text: "proc greet {} {}"}}))
	in.Write(frame(t, "textDocument/didOpen", nil, DidOpenParams{
		TextDocument: TextDocumentItem{URI: "file:///a.tcl", Text: "greet\ngreet"}}))
	in.Write(frame(t, "textDocument/references", 3, TextDocumentPositionParams{
		TextDocument: TextDocumentIdentifier{URI: "file:///a.tcl"},
		Position:     Position{Line: 0, Character: 0}}))
	in.Write(frame(t, "exit", nil, nil))

	resp := responseByID(runServer(t, in.Bytes()), "3")
	if resp == nil {
		t.Fatal("no references response")
	}
	var locs []Location
	if err := json.Unmarshal(resp.Result, &locs); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if len(locs) != 2 {
		t.Fatalf("expected 2 references, got %#v", locs)
	}
}

func TestServerDidChangeUpdatesIndex(t *testing.T) {
	var in bytes.Buffer
	in.Write(frame(t, "initialize", 1, InitializeParams{}))
	in.Write(frame(t, "textDocument/didOpen", nil, DidOpenParams{
		TextDocument: TextDocumentItem{URI: "file:///lib.tcl", Text: "proc old {} {}"}}))
	in.Write(frame(t, "textDocument/didChange", nil, DidChangeParams{
		TextDocument:   TextDocumentIdentifier{URI: "file:///lib.tcl"},
		ContentChanges: []TextDocumentContentChangeEvent{{Text: "proc new {} {}"}}}))
	in.Write(frame(t, "textDocument/didOpen", nil, DidOpenParams{
		TextDocument: TextDocumentItem{URI: "file:///main.tcl", Text: "new"}}))
	in.Write(frame(t, "textDocument/definition", 4, TextDocumentPositionParams{
		TextDocument: TextDocumentIdentifier{URI: "file:///main.tcl"},
		Position:     Position{Line: 0, Character: 0}}))
	in.Write(frame(t, "exit", nil, nil))

	resp := responseByID(runServer(t, in.Bytes()), "4")
	var locs []Location
	_ = json.Unmarshal(resp.Result, &locs)
	if len(locs) != 1 || locs[0].URI != "file:///lib.tcl" {
		t.Fatalf("after didChange, `new` should resolve to lib.tcl: %#v", locs)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/lsp/ -run "TestServerDefinitionFlow|TestServerReferencesFlow|TestServerDidChange"`
Expected: FAIL — document-sync and feature methods are not handled yet (definition/references responses are null).

- [ ] **Step 3: Write minimal implementation**

In `server/internal/lsp/server.go`, add the `index` import is already present. Add the new cases to the `dispatch` switch (before `default`):

```go
	case "textDocument/didOpen":
		var p DidOpenParams
		_ = json.Unmarshal(m.Params, &p)
		s.setDoc(p.TextDocument.URI, p.TextDocument.Text)
	case "textDocument/didChange":
		var p DidChangeParams
		_ = json.Unmarshal(m.Params, &p)
		if n := len(p.ContentChanges); n > 0 {
			s.setDoc(p.TextDocument.URI, p.ContentChanges[n-1].Text)
		}
	case "textDocument/didClose":
		var p DidCloseParams
		_ = json.Unmarshal(m.Params, &p)
		delete(s.docs, p.TextDocument.URI)
	case "textDocument/definition":
		var p TextDocumentPositionParams
		_ = json.Unmarshal(m.Params, &p)
		s.reply(m.ID, s.handleDefinition(p))
	case "textDocument/references":
		var p TextDocumentPositionParams
		_ = json.Unmarshal(m.Params, &p)
		s.reply(m.ID, s.handleReferences(p))
```

And add the helpers at the end of `server.go`:

```go
// setDoc stores a document's live text and re-indexes it.
func (s *Server) setDoc(uri, text string) {
	s.docs[uri] = text
	s.ix.IndexFile(uriToPath(uri), text)
}

// sourceOf returns the best-available source for a path: the live document if
// open, else the indexed copy.
func (s *Server) sourceOf(path string) string {
	if t, ok := s.docs[pathToURI(path)]; ok {
		return t
	}
	return s.ix.Source(path)
}

func (s *Server) handleDefinition(p TextDocumentPositionParams) []Location {
	path := uriToPath(p.TextDocument.URI)
	src := s.sourceOf(path)
	off := ByteOffset(src, p.Position.Line, p.Position.Character)
	return s.toLocations(s.res.Definition(path, src, off))
}

func (s *Server) handleReferences(p TextDocumentPositionParams) []Location {
	path := uriToPath(p.TextDocument.URI)
	src := s.sourceOf(path)
	off := ByteOffset(src, p.Position.Line, p.Position.Character)
	return s.toLocations(s.res.References(path, src, off))
}

// toLocations converts resolver locations (byte ranges) to LSP locations.
func (s *Server) toLocations(locs []index.Location) []Location {
	var out []Location
	for _, l := range locs {
		src := s.sourceOf(l.File)
		sl, sc := LSPPosition(src, l.NameStart)
		el, ec := LSPPosition(src, l.NameEnd)
		out = append(out, Location{
			URI: pathToURI(l.File),
			Range: Range{
				Start: Position{Line: sl, Character: sc},
				End:   Position{Line: el, Character: ec},
			},
		})
	}
	return out
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/lsp/`
Expected: PASS (all lsp tests).

- [ ] **Step 5: Commit**

```bash
git add server/internal/lsp/server.go server/internal/lsp/server_test.go
git commit -m "feat(lsp): document sync and definition/references handlers"
```

---

## Task 4: The `tcl-lsp` binary

**Files:**
- Create: `server/cmd/tcl-lsp/main.go`

- [ ] **Step 1: Create the entry point**

Create `server/cmd/tcl-lsp/main.go`:

```go
// Command tcl-lsp is a Language Server Protocol server for TCL/RVT. It speaks
// LSP over stdio; logs go to stderr (stdout is the protocol channel).
package main

import (
	"log"
	"os"

	"github.com/unknownbreaker/tcl-lsp/internal/lsp"
)

func main() {
	log.SetOutput(os.Stderr)
	log.SetPrefix("tcl-lsp: ")
	srv := lsp.NewServer(lsp.NewConn(os.Stdin, os.Stdout))
	if err := srv.Run(); err != nil {
		log.Fatalf("server error: %v", err)
	}
}
```

- [ ] **Step 2: Verify the binary builds**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server build -o /tmp/tcl-lsp ./cmd/tcl-lsp`
Then: `ls -la /tmp/tcl-lsp`
Expected: builds with no output; the binary exists and is non-zero in size.

- [ ] **Step 3: Smoke-test the binary over stdio (optional, manual)**

The binary reads framed LSP messages on stdin. A full manual smoke test is covered in the next plan; for now the build succeeding plus the server tests passing is sufficient.

- [ ] **Step 4: Run the full suite + vet**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server vet ./...`
Then: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./...`
Expected: clean vet; all tests PASS (tcl + index + resolve + lsp).

- [ ] **Step 5: Commit**

```bash
git add server/cmd/tcl-lsp/main.go
git commit -m "feat(cmd): tcl-lsp binary entry point (stdio)"
```

---

## Done criteria for Plan 12

- `go vet ./...` clean; `go test ./...` all pass; `go build ./cmd/tcl-lsp` produces a binary.
- The `Server` handles initialize (advertising definition+references, full sync), shutdown/exit, `didOpen`/`didChange`/`didClose` (indexing live docs), and `textDocument/definition`/`references` (converting positions and returning LSP `Location`s). A scripted client session resolves a cross-file definition and references end-to-end.

**Next (final Phase A plan):** Plan 13 — the Neovim/LazyVim client config, a build/install README, and a manual smoke-test walkthrough so you can `gd`/`gr` on TCL in your editor.

