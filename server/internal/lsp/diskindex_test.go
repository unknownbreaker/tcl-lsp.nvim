package lsp

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

// TestServerReferencesRVTOnDiskNotOpened reproduces the real user scenario:
// the .tcl with the proc definition is opened in the editor, but the .rvt that
// calls the proc is only present on disk and indexed via IndexDir at initialize
// (never didOpen'd). find-references from the proc definition must still include
// the .rvt call site.
func TestServerReferencesRVTOnDiskNotOpened(t *testing.T) {
	dir := t.TempDir()
	libPath := filepath.Join(dir, "lib.tcl")
	rvtPath := filepath.Join(dir, "page.rvt")
	// namespaced proc, called fully-qualified from the page (the common real pattern).
	if err := os.WriteFile(libPath, []byte("namespace eval ::lib { proc helper {} {} }"), 0o644); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(rvtPath, []byte("<? ::lib::helper ?>"), 0o644); err != nil {
		t.Fatal(err)
	}

	var in bytes.Buffer
	in.Write(frame(t, "initialize", 1, InitializeParams{RootURI: pathToURI(dir)}))
	// Only the .tcl is opened; the .rvt stays on disk (indexed by IndexDir).
	in.Write(frame(t, "textDocument/didOpen", nil, DidOpenParams{
		TextDocument: TextDocumentItem{URI: pathToURI(libPath),
			Text: "namespace eval ::lib { proc helper {} {} }"}}))
	// references from the proc definition; "helper" name starts at byte 23.
	col := bytes.Index([]byte("namespace eval ::lib { proc helper {} {} }"), []byte("helper"))
	in.Write(frame(t, "textDocument/references", 3, ReferenceParams{
		TextDocumentPositionParams: TextDocumentPositionParams{
			TextDocument: TextDocumentIdentifier{URI: pathToURI(libPath)},
			Position:     Position{Line: 0, Character: col}},
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
	t.Logf("locs: %#v", locs)
	var inRVT bool
	for _, l := range locs {
		if l.URI == pathToURI(rvtPath) {
			inRVT = true
		}
	}
	if !inRVT {
		t.Fatalf("FAIL: .rvt call site (on disk, not opened) missing from references: %#v", locs)
	}
}
