package main

import (
	"bytes"
	"encoding/json"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"testing"
	"time"

	"github.com/unknownbreaker/tcl-lsp/internal/lsp"
)

// TestBinaryEndToEnd builds the tcl-lsp binary and drives a real LSP session
// over its stdin/stdout, asserting a cross-file goto-definition resolves.
func TestBinaryEndToEnd(t *testing.T) {
	bin := filepath.Join(t.TempDir(), "tcl-lsp")
	if out, err := exec.Command("go", "build", "-o", bin, ".").CombinedOutput(); err != nil {
		t.Fatalf("build failed: %v\n%s", err, out)
	}

	cmd := exec.Command(bin)
	stdin, err := cmd.StdinPipe()
	if err != nil {
		t.Fatal(err)
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	cmd.Stderr = os.Stderr
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() {
		_ = stdin.Close()
		_ = cmd.Wait()
	}()

	w := lsp.NewConn(bytes.NewReader(nil), stdin)
	r := lsp.NewConn(stdout, io.Discard)

	send := func(method string, id, params any) {
		m := &lsp.Message{Method: method}
		if id != nil {
			b, _ := json.Marshal(id)
			m.ID = b
		}
		if params != nil {
			b, _ := json.Marshal(params)
			m.Params = b
		}
		if err := w.Write(m); err != nil {
			t.Fatalf("write %s: %v", method, err)
		}
	}

	send("initialize", 1, lsp.InitializeParams{})
	send("textDocument/didOpen", nil, lsp.DidOpenParams{
		TextDocument: lsp.TextDocumentItem{URI: "file:///lib.tcl", Text: "proc greet {} {}"}})
	send("textDocument/didOpen", nil, lsp.DidOpenParams{
		TextDocument: lsp.TextDocumentItem{URI: "file:///main.tcl", Text: "greet"}})
	send("textDocument/definition", 2, lsp.TextDocumentPositionParams{
		TextDocument: lsp.TextDocumentIdentifier{URI: "file:///main.tcl"},
		Position:     lsp.Position{Line: 0, Character: 0}})
	send("exit", nil, nil)

	// Read responses until we see id 2 (with a guard against hanging).
	done := make(chan []lsp.Location, 1)
	go func() {
		for {
			m, err := r.Read()
			if err != nil {
				done <- nil
				return
			}
			if string(m.ID) == "2" {
				var locs []lsp.Location
				_ = json.Unmarshal(m.Result, &locs)
				done <- locs
				return
			}
		}
	}()

	select {
	case locs := <-done:
		if len(locs) != 1 || locs[0].URI != "file:///lib.tcl" {
			t.Fatalf("definition over binary = %#v", locs)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("timed out waiting for definition response")
	}
}
