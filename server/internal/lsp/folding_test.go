package lsp

import (
	"bytes"
	"encoding/json"
	"testing"

	"github.com/unknownbreaker/tcl-lsp/internal/tcl"
)

// The server advertises folding support.
func TestServerAdvertisesFoldingCapability(t *testing.T) {
	var in bytes.Buffer
	in.Write(frame(t, "initialize", 1, InitializeParams{}))
	in.Write(frame(t, "exit", nil, nil))
	resp := responseByID(runServer(t, in.Bytes()), "1")
	var res InitializeResult
	_ = json.Unmarshal(resp.Result, &res)
	if !res.Capabilities.FoldingRangeProvider {
		t.Fatalf("folding capability not advertised: %#v", res.Capabilities)
	}
}

// A multi-line proc yields a fold from its first line to its closing brace line.
func TestServerFoldingRange(t *testing.T) {
	src := "proc render {} {\n  puts a\n  puts b\n}\n"
	var in bytes.Buffer
	in.Write(frame(t, "initialize", 1, InitializeParams{}))
	in.Write(frame(t, "textDocument/didOpen", nil, DidOpenParams{
		TextDocument: TextDocumentItem{URI: "file:///m.tcl", Text: src}}))
	in.Write(frame(t, "textDocument/foldingRange", 2, FoldingRangeParams{
		TextDocument: TextDocumentIdentifier{URI: "file:///m.tcl"}}))
	in.Write(frame(t, "exit", nil, nil))
	resp := responseByID(runServer(t, in.Bytes()), "2")
	var ranges []FoldingRange
	_ = json.Unmarshal(resp.Result, &ranges)
	if len(ranges) != 1 || ranges[0].StartLine != 0 || ranges[0].EndLine != 3 {
		t.Fatalf("folding ranges = %#v, want one {0,3}", ranges)
	}
}

// A .rvt template folds the TCL structure inside its <? ?> regions, reported in
// .rvt source line coordinates (not the stitched-script coordinates).
func TestServerFoldingRangeRVT(t *testing.T) {
	// Line 0: <html>, lines 1-5: a <? ?> block holding a multi-line proc.
	src := "<html>\n<?\nproc p {} {\n  puts hi\n}\n?>\n</html>\n"
	var in bytes.Buffer
	in.Write(frame(t, "initialize", 1, InitializeParams{}))
	in.Write(frame(t, "textDocument/didOpen", nil, DidOpenParams{
		TextDocument: TextDocumentItem{URI: "file:///p.rvt", Text: src}}))
	in.Write(frame(t, "textDocument/foldingRange", 2, FoldingRangeParams{
		TextDocument: TextDocumentIdentifier{URI: "file:///p.rvt"}}))
	in.Write(frame(t, "exit", nil, nil))
	resp := responseByID(runServer(t, in.Bytes()), "2")
	var ranges []FoldingRange
	_ = json.Unmarshal(resp.Result, &ranges)
	// proc opens on source line 2 ("proc p {} {") and closes on line 4 ("}").
	found := false
	for _, r := range ranges {
		if r.StartLine == 2 && r.EndLine == 4 {
			found = true
		}
	}
	if !found {
		t.Fatalf("rvt proc fold not found in source coords; got %#v", ranges)
	}
}

// An unterminated body (a file mid-edit) surfaces no fold: the open '{' and the
// EOF-pointing close land on the same line, so the line-collapse guard drops it.
func TestBuildFoldingRangesUnterminated(t *testing.T) {
	src := "proc p {} {"
	got := buildFoldingRanges(tcl.FileFolds(src), src)
	if len(got) != 0 {
		t.Fatalf("unterminated body should surface no fold; got %#v", got)
	}
}

// buildFoldingRanges drops single-line bodies (nothing to collapse).
func TestBuildFoldingRangesDropsSingleLine(t *testing.T) {
	src := "proc p {} {}\n"
	got := buildFoldingRanges([]tcl.FoldRange{{Open: len("proc p {} "), Close: len("proc p {} ") + 1}}, src)
	if len(got) != 0 {
		t.Fatalf("single-line body should not fold; got %#v", got)
	}
}
