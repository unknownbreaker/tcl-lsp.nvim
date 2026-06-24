package lsp

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func messageByMethod(ms []*Message, method string) *Message {
	for _, m := range ms {
		if m.Method == method {
			return m
		}
	}
	return nil
}

// After initialized, the server must dynamically register for file watching so
// the client sends workspace/didChangeWatchedFiles for .tcl/.rvt changes.
func TestServerRegistersFileWatchers(t *testing.T) {
	var in bytes.Buffer
	in.Write(frame(t, "initialize", 1, InitializeParams{}))
	in.Write(frame(t, "initialized", nil, struct{}{}))
	in.Write(frame(t, "exit", nil, nil))

	reg := messageByMethod(runServer(t, in.Bytes()), "client/registerCapability")
	if reg == nil {
		t.Fatal("server did not send client/registerCapability")
	}
	var p RegistrationParams
	if err := json.Unmarshal(reg.Params, &p); err != nil {
		t.Fatalf("unmarshal registration: %v", err)
	}
	var watched *Registration
	for i := range p.Registrations {
		if p.Registrations[i].Method == "workspace/didChangeWatchedFiles" {
			watched = &p.Registrations[i]
		}
	}
	if watched == nil {
		t.Fatalf("no didChangeWatchedFiles registration: %#v", p)
	}
	raw, _ := json.Marshal(watched.RegisterOptions)
	s := string(raw)
	if !strings.Contains(s, "*.tcl") || !strings.Contains(s, "*.rvt") {
		t.Fatalf("watchers should cover .tcl and .rvt globs: %s", s)
	}
}

// A .rvt created on disk AFTER initialize (never opened) must become a
// reference source once the client reports it via didChangeWatchedFiles.
func TestServerDidChangeWatchedFilesCreated(t *testing.T) {
	dir := t.TempDir()
	libPath := filepath.Join(dir, "lib.tcl")
	rvtPath := filepath.Join(dir, "page.rvt")
	if err := os.WriteFile(libPath, []byte("proc greet {} {}"), 0o644); err != nil {
		t.Fatal(err)
	}

	var in bytes.Buffer
	in.Write(frame(t, "initialize", 1, InitializeParams{RootURI: pathToURI(dir)}))
	in.Write(frame(t, "initialized", nil, struct{}{}))
	// lib.tcl is opened (its def is indexed). The .rvt does not exist yet.
	in.Write(frame(t, "textDocument/didOpen", nil, DidOpenParams{
		TextDocument: TextDocumentItem{URI: pathToURI(libPath), Text: "proc greet {} {}"}}))

	// Now create the .rvt on disk and notify via watched-files (Created = 1).
	// (The test writes the file; in the wild the editor/another tool does.)
	if err := os.WriteFile(rvtPath, []byte("<? greet ?>"), 0o644); err != nil {
		t.Fatal(err)
	}
	in.Write(frame(t, "workspace/didChangeWatchedFiles", nil, DidChangeWatchedFilesParams{
		Changes: []FileEvent{{URI: pathToURI(rvtPath), Type: FileChangeCreated}}}))

	// references from the proc definition should now include the .rvt call.
	col := bytes.Index([]byte("proc greet {} {}"), []byte("greet"))
	in.Write(frame(t, "textDocument/references", 3, ReferenceParams{
		TextDocumentPositionParams: TextDocumentPositionParams{
			TextDocument: TextDocumentIdentifier{URI: pathToURI(libPath)},
			Position:     Position{Line: 0, Character: col}},
		Context: ReferenceContext{IncludeDeclaration: true}}))
	in.Write(frame(t, "exit", nil, nil))

	resp := responseByID(runServer(t, in.Bytes()), "3")
	var locs []Location
	_ = json.Unmarshal(resp.Result, &locs)
	var inRVT bool
	for _, l := range locs {
		if l.URI == pathToURI(rvtPath) {
			inRVT = true
		}
	}
	if !inRVT {
		t.Fatalf("created .rvt should be indexed after didChangeWatchedFiles: %#v", locs)
	}
}

// A deleted file must drop out of the index.
func TestServerDidChangeWatchedFilesDeleted(t *testing.T) {
	dir := t.TempDir()
	libPath := filepath.Join(dir, "lib.tcl")
	rvtPath := filepath.Join(dir, "page.rvt")
	if err := os.WriteFile(libPath, []byte("proc greet {} {}"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(rvtPath, []byte("<? greet ?>"), 0o644); err != nil {
		t.Fatal(err)
	}

	var in bytes.Buffer
	in.Write(frame(t, "initialize", 1, InitializeParams{RootURI: pathToURI(dir)}))
	in.Write(frame(t, "initialized", nil, struct{}{}))
	in.Write(frame(t, "textDocument/didOpen", nil, DidOpenParams{
		TextDocument: TextDocumentItem{URI: pathToURI(libPath), Text: "proc greet {} {}"}}))
	// Delete the .rvt and report it (Deleted = 3).
	if err := os.Remove(rvtPath); err != nil {
		t.Fatal(err)
	}
	in.Write(frame(t, "workspace/didChangeWatchedFiles", nil, DidChangeWatchedFilesParams{
		Changes: []FileEvent{{URI: pathToURI(rvtPath), Type: FileChangeDeleted}}}))
	col := bytes.Index([]byte("proc greet {} {}"), []byte("greet"))
	in.Write(frame(t, "textDocument/references", 3, ReferenceParams{
		TextDocumentPositionParams: TextDocumentPositionParams{
			TextDocument: TextDocumentIdentifier{URI: pathToURI(libPath)},
			Position:     Position{Line: 0, Character: col}},
		Context: ReferenceContext{IncludeDeclaration: true}}))
	in.Write(frame(t, "exit", nil, nil))

	resp := responseByID(runServer(t, in.Bytes()), "3")
	var locs []Location
	_ = json.Unmarshal(resp.Result, &locs)
	for _, l := range locs {
		if l.URI == pathToURI(rvtPath) {
			t.Fatalf("deleted .rvt should not appear in references: %#v", locs)
		}
	}
}
