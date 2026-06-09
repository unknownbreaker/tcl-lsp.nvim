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

func TestServerReferencesIncludesDeclaration(t *testing.T) {
	var in bytes.Buffer
	in.Write(frame(t, "initialize", 1, InitializeParams{}))
	in.Write(frame(t, "textDocument/didOpen", nil, DidOpenParams{
		TextDocument: TextDocumentItem{URI: "file:///lib.tcl", Text: "proc greet {} {}"}}))
	in.Write(frame(t, "textDocument/didOpen", nil, DidOpenParams{
		TextDocument: TextDocumentItem{URI: "file:///a.tcl", Text: "greet\ngreet"}}))
	in.Write(frame(t, "textDocument/references", 3, ReferenceParams{
		TextDocumentPositionParams: TextDocumentPositionParams{
			TextDocument: TextDocumentIdentifier{URI: "file:///a.tcl"},
			Position:     Position{Line: 0, Character: 0}},
		Context: ReferenceContext{IncludeDeclaration: true}}))
	in.Write(frame(t, "exit", nil, nil))

	resp := responseByID(runServer(t, in.Bytes()), "3")
	if resp == nil {
		t.Fatal("no references response")
	}
	var locs []Location
	if err := json.Unmarshal(resp.Result, &locs); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	// 2 call sites in a.tcl + the declaration in lib.tcl.
	if len(locs) != 3 {
		t.Fatalf("expected 3 (2 calls + declaration), got %#v", locs)
	}
	var hasDecl bool
	for _, l := range locs {
		if l.URI == "file:///lib.tcl" {
			hasDecl = true
		}
	}
	if !hasDecl {
		t.Fatalf("declaration in lib.tcl should be included: %#v", locs)
	}
}

func TestServerReferencesFromDefinitionIncludesDeclaration(t *testing.T) {
	// gr with the cursor on the proc's own definition must still include the
	// declaration (goto-definition is a no-op there, so this exercises the
	// Declarations path rather than Definition).
	var in bytes.Buffer
	in.Write(frame(t, "initialize", 1, InitializeParams{}))
	in.Write(frame(t, "textDocument/didOpen", nil, DidOpenParams{
		TextDocument: TextDocumentItem{URI: "file:///lib.tcl", Text: "proc greet {} {}"}}))
	in.Write(frame(t, "textDocument/didOpen", nil, DidOpenParams{
		TextDocument: TextDocumentItem{URI: "file:///a.tcl", Text: "greet\ngreet"}}))
	in.Write(frame(t, "textDocument/references", 3, ReferenceParams{
		TextDocumentPositionParams: TextDocumentPositionParams{
			TextDocument: TextDocumentIdentifier{URI: "file:///lib.tcl"},
			Position:     Position{Line: 0, Character: 5}}, // on "greet" in the proc def
		Context: ReferenceContext{IncludeDeclaration: true}}))
	in.Write(frame(t, "exit", nil, nil))

	resp := responseByID(runServer(t, in.Bytes()), "3")
	var locs []Location
	_ = json.Unmarshal(resp.Result, &locs)
	// declaration in lib.tcl + 2 call sites in a.tcl.
	if len(locs) != 3 {
		t.Fatalf("expected 3 (declaration + 2 calls), got %#v", locs)
	}
	var hasDecl bool
	for _, l := range locs {
		if l.URI == "file:///lib.tcl" {
			hasDecl = true
		}
	}
	if !hasDecl {
		t.Fatalf("declaration in lib.tcl should be included when cursor is on it: %#v", locs)
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
	if resp == nil {
		t.Fatal("no definition response")
	}
	var locs []Location
	_ = json.Unmarshal(resp.Result, &locs)
	if len(locs) != 1 || locs[0].URI != "file:///lib.tcl" {
		t.Fatalf("after didChange, `new` should resolve to lib.tcl: %#v", locs)
	}
}

func TestServerDidCloseThenDefinition(t *testing.T) {
	var in bytes.Buffer
	in.Write(frame(t, "initialize", 1, InitializeParams{}))
	in.Write(frame(t, "textDocument/didOpen", nil, DidOpenParams{
		TextDocument: TextDocumentItem{URI: "file:///lib.tcl", Text: "proc greet {} {}"}}))
	in.Write(frame(t, "textDocument/didOpen", nil, DidOpenParams{
		TextDocument: TextDocumentItem{URI: "file:///main.tcl", Text: "greet"}}))
	in.Write(frame(t, "textDocument/didClose", nil, DidCloseParams{
		TextDocument: TextDocumentIdentifier{URI: "file:///main.tcl"}}))
	in.Write(frame(t, "textDocument/definition", 5, TextDocumentPositionParams{
		TextDocument: TextDocumentIdentifier{URI: "file:///main.tcl"},
		Position:     Position{Line: 0, Character: 0}}))
	in.Write(frame(t, "exit", nil, nil))

	resp := responseByID(runServer(t, in.Bytes()), "5")
	if resp == nil {
		t.Fatal("no definition response")
	}
	var locs []Location
	_ = json.Unmarshal(resp.Result, &locs)
	// A closed doc is removed from the live map but remains indexed, so the
	// definition still resolves via the indexed source.
	if len(locs) != 1 || locs[0].URI != "file:///lib.tcl" {
		t.Fatalf("after didClose, definition = %#v", locs)
	}
}

func TestServerRVTToTCLDefinition(t *testing.T) {
	var in bytes.Buffer
	in.Write(frame(t, "initialize", 1, InitializeParams{}))
	in.Write(frame(t, "textDocument/didOpen", nil, DidOpenParams{
		TextDocument: TextDocumentItem{URI: "file:///lib.tcl",
			Text: "namespace eval ::lib { proc helper {} {} }"}}))
	in.Write(frame(t, "textDocument/didOpen", nil, DidOpenParams{
		TextDocument: TextDocumentItem{URI: "file:///page.rvt",
			Text: "<? ::lib::helper ?>"}}))
	// cursor on the ::lib::helper call (char 3 = start of the qualified name).
	in.Write(frame(t, "textDocument/definition", 2, TextDocumentPositionParams{
		TextDocument: TextDocumentIdentifier{URI: "file:///page.rvt"},
		Position:     Position{Line: 0, Character: 3}}))
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
		t.Fatalf("rvt->tcl definition = %#v", locs)
	}
}

func TestServerRVTPageLocalDefinition(t *testing.T) {
	var in bytes.Buffer
	in.Write(frame(t, "initialize", 1, InitializeParams{}))
	in.Write(frame(t, "textDocument/didOpen", nil, DidOpenParams{
		TextDocument: TextDocumentItem{URI: "file:///page.rvt",
			Text: "<? proc greet {} {} ?>\n<? greet ?>"}}))
	// cursor on the greet call on line 1 (char 3).
	in.Write(frame(t, "textDocument/definition", 2, TextDocumentPositionParams{
		TextDocument: TextDocumentIdentifier{URI: "file:///page.rvt"},
		Position:     Position{Line: 1, Character: 3}}))
	in.Write(frame(t, "exit", nil, nil))

	resp := responseByID(runServer(t, in.Bytes()), "2")
	var locs []Location
	_ = json.Unmarshal(resp.Result, &locs)
	if len(locs) != 1 || locs[0].URI != "file:///page.rvt" {
		t.Fatalf("page-local definition = %#v", locs)
	}
}

func TestServerReferencesIncludeRVTCallSite(t *testing.T) {
	var in bytes.Buffer
	in.Write(frame(t, "initialize", 1, InitializeParams{}))
	in.Write(frame(t, "textDocument/didOpen", nil, DidOpenParams{
		TextDocument: TextDocumentItem{URI: "file:///lib.tcl", Text: "proc greet {} {}"}}))
	in.Write(frame(t, "textDocument/didOpen", nil, DidOpenParams{
		TextDocument: TextDocumentItem{URI: "file:///page.rvt", Text: "<? greet ?>"}}))
	// references from the proc definition in lib.tcl (cursor on the name, char 5).
	in.Write(frame(t, "textDocument/references", 3, ReferenceParams{
		TextDocumentPositionParams: TextDocumentPositionParams{
			TextDocument: TextDocumentIdentifier{URI: "file:///lib.tcl"},
			Position:     Position{Line: 0, Character: 5}},
		Context: ReferenceContext{IncludeDeclaration: true}}))
	in.Write(frame(t, "exit", nil, nil))

	resp := responseByID(runServer(t, in.Bytes()), "3")
	var locs []Location
	_ = json.Unmarshal(resp.Result, &locs)
	var inRVT bool
	for _, l := range locs {
		if l.URI == "file:///page.rvt" {
			inRVT = true
		}
	}
	if !inRVT {
		t.Fatalf("references should include the .rvt call site: %#v", locs)
	}
}

func TestServerRVTCursorInLiteralIsEmpty(t *testing.T) {
	var in bytes.Buffer
	in.Write(frame(t, "initialize", 1, InitializeParams{}))
	in.Write(frame(t, "textDocument/didOpen", nil, DidOpenParams{
		TextDocument: TextDocumentItem{URI: "file:///page.rvt", Text: "<h1>title</h1>"}}))
	// cursor inside the literal HTML word "title" (char 5) — no TCL symbol there.
	in.Write(frame(t, "textDocument/definition", 4, TextDocumentPositionParams{
		TextDocument: TextDocumentIdentifier{URI: "file:///page.rvt"},
		Position:     Position{Line: 0, Character: 5}}))
	in.Write(frame(t, "exit", nil, nil))

	resp := responseByID(runServer(t, in.Bytes()), "4")
	if resp == nil || string(resp.Result) != "null" {
		t.Fatalf("cursor in literal should yield null, got %#v", resp)
	}
}

func TestServerReferencesUnknownDoc(t *testing.T) {
	var in bytes.Buffer
	in.Write(frame(t, "initialize", 1, InitializeParams{}))
	in.Write(frame(t, "textDocument/references", 6, TextDocumentPositionParams{
		TextDocument: TextDocumentIdentifier{URI: "file:///never-opened.tcl"},
		Position:     Position{Line: 0, Character: 0}}))
	in.Write(frame(t, "exit", nil, nil))

	resp := responseByID(runServer(t, in.Bytes()), "6")
	if resp == nil {
		t.Fatal("no references response")
	}
	if string(resp.Result) != "null" {
		t.Fatalf("references on unknown doc should be null, got %s", resp.Result)
	}
}
