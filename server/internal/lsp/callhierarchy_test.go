package lsp

import (
	"bytes"
	"encoding/json"
	"strings"
	"testing"

	"github.com/unknownbreaker/tcl-lsp/internal/index"
	"github.com/unknownbreaker/tcl-lsp/internal/resolve"
)

func newCHServer(docs map[string]string) *Server {
	ix := index.New()
	s := &Server{ix: ix, res: resolve.New(ix), docs: map[string]string{}}
	for uri, text := range docs {
		s.setDoc(uri, text)
	}
	return s
}

// posOf returns the LSP position of the first byte of substr in src.
func posOf(src, substr string) Position {
	off := strings.Index(src, substr)
	l, c := LSPPosition(src, off)
	return Position{Line: l, Character: c}
}

func TestCallHierarchy(t *testing.T) {
	lib := "proc helper {x} { return $x }\nproc render {} {\n  helper 1\n  helper 2\n}"
	caller := "proc main {} {\n  render\n}"
	page := "<? render ?>"
	s := newCHServer(map[string]string{
		"file:///lib.tcl":    lib,
		"file:///caller.tcl": caller,
		"file:///page.rvt":   page,
	})

	// prepare on the `render` definition.
	items := s.prepareCallHierarchy(CallHierarchyPrepareParams{
		TextDocument: TextDocumentIdentifier{URI: "file:///lib.tcl"},
		Position:     posOf(lib, "render {}"),
	})
	if len(items) != 1 {
		t.Fatalf("prepare returned %d items, want 1: %#v", len(items), items)
	}
	item := items[0]
	if item.Name != "render" || item.Kind != SymKindFunction {
		t.Fatalf("prepared item = %+v, want render/Function", item)
	}

	// incomingCalls: render is called by main (a proc) and by the page (file-level).
	in := s.incomingCalls(CallHierarchyIncomingCallsParams{Item: item})
	callers := map[string]int{}
	for _, c := range in {
		callers[c.From.Name] = len(c.FromRanges)
	}
	if callers["main"] != 1 {
		t.Errorf("incoming: expected main to call render once, got %v", callers)
	}
	if callers["page.rvt"] != 1 {
		t.Errorf("incoming: expected page.rvt (file-level) caller, got %v", callers)
	}

	// outgoingCalls: render calls helper (twice).
	out := s.outgoingCalls(CallHierarchyOutgoingCallsParams{Item: item})
	callees := map[string]int{}
	for _, c := range out {
		callees[c.To.Name] = len(c.FromRanges)
	}
	if callees["helper"] != 2 {
		t.Errorf("outgoing: expected render to call helper twice, got %v", callees)
	}
}

// TestCallHierarchyItcl: method-to-method edges via the Itcl Tier-2 resolution —
// a bare intra-class call inside one method resolves to a sibling method.
func TestCallHierarchyItcl(t *testing.T) {
	src := "::itcl::class ::C {\n" +
		"  public method helper {} {}\n" +
		"  public method run {} { helper }\n" +
		"}"
	s := newCHServer(map[string]string{"file:///c.tcl": src})

	items := s.prepareCallHierarchy(CallHierarchyPrepareParams{
		TextDocument: TextDocumentIdentifier{URI: "file:///c.tcl"},
		Position:     posOf(src, "helper {}"),
	})
	if len(items) != 1 || items[0].Kind != SymKindMethod || items[0].Name != "helper" {
		t.Fatalf("prepare on method = %#v, want helper/Method", items)
	}

	in := s.incomingCalls(CallHierarchyIncomingCallsParams{Item: items[0]})
	var fromRun bool
	for _, c := range in {
		if c.From.Name == "run" && c.From.Kind == SymKindMethod {
			fromRun = true
		}
	}
	if !fromRun {
		t.Errorf("incoming on method helper: expected caller method run, got %#v", in)
	}

	// outgoing on run -> helper
	runItems := s.prepareCallHierarchy(CallHierarchyPrepareParams{
		TextDocument: TextDocumentIdentifier{URI: "file:///c.tcl"},
		Position:     posOf(src, "run {}"),
	})
	out := s.outgoingCalls(CallHierarchyOutgoingCallsParams{Item: runItems[0]})
	var toHelper bool
	for _, c := range out {
		if c.To.Name == "helper" {
			toHelper = true
		}
	}
	if !toHelper {
		t.Errorf("outgoing on method run: expected callee helper, got %#v", out)
	}
}

func TestServerAdvertisesCallHierarchy(t *testing.T) {
	var in bytes.Buffer
	in.Write(frame(t, "initialize", 1, InitializeParams{}))
	in.Write(frame(t, "exit", nil, nil))
	resp := responseByID(runServer(t, in.Bytes()), "1")
	var res InitializeResult
	_ = json.Unmarshal(resp.Result, &res)
	if !res.Capabilities.CallHierarchyProvider {
		t.Fatalf("callHierarchyProvider not advertised: %#v", res.Capabilities)
	}
}
