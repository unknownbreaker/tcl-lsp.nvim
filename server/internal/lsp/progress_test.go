package lsp

import (
	"bytes"
	"encoding/json"
	"os"
	"path/filepath"
	"testing"
)

// TestServerIndexProgress: when the client advertises window.workDoneProgress,
// the initial workspace index is reported via a create request + $/progress
// begin/end (so the editor can show "indexing… / ready").
func TestServerIndexProgress(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "a.tcl"), []byte("proc p {} {}"), 0o644); err != nil {
		t.Fatal(err)
	}

	var in bytes.Buffer
	in.Write(frame(t, "initialize", 1, map[string]any{
		"rootUri":      pathToURI(dir),
		"capabilities": map[string]any{"window": map[string]any{"workDoneProgress": true}},
	}))
	in.Write(frame(t, "exit", nil, nil))

	var created, begin, report, end bool
	for _, m := range runServer(t, in.Bytes()) {
		if m.Method == "window/workDoneProgress/create" {
			created = true
		}
		if m.Method == "$/progress" {
			var pp struct {
				Token string         `json:"token"`
				Value map[string]any `json:"value"`
			}
			_ = json.Unmarshal(m.Params, &pp)
			switch pp.Value["kind"] {
			case "begin":
				begin = true
			case "report":
				report = true // the running count (first file always reports)
			case "end":
				end = true
			}
		}
	}
	if !created || !begin || !report || !end {
		t.Fatalf("index progress not reported: create=%v begin=%v report=%v end=%v", created, begin, report, end)
	}
}

// TestServerNoProgressWithoutCapability: a client that does not advertise
// work-done progress gets no $/progress traffic (the index still runs).
func TestServerNoProgressWithoutCapability(t *testing.T) {
	dir := t.TempDir()
	if err := os.WriteFile(filepath.Join(dir, "a.tcl"), []byte("proc p {} {}"), 0o644); err != nil {
		t.Fatal(err)
	}

	var in bytes.Buffer
	in.Write(frame(t, "initialize", 1, InitializeParams{RootURI: pathToURI(dir)}))
	in.Write(frame(t, "exit", nil, nil))

	for _, m := range runServer(t, in.Bytes()) {
		if m.Method == "$/progress" {
			t.Fatalf("sent $/progress though the client did not advertise the capability")
		}
	}
}
