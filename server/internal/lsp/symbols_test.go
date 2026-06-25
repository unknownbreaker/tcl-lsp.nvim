package lsp

import (
	"testing"

	"github.com/unknownbreaker/tcl-lsp/internal/source"
	"github.com/unknownbreaker/tcl-lsp/internal/tcl"
)

// posLE reports whether position a is less than or equal to position b.
func posLE(a, b Position) bool {
	return a.Line < b.Line || (a.Line == b.Line && a.Character <= b.Character)
}

func TestBuildDocumentSymbolsFlat(t *testing.T) {
	src := "proc render {} {}\nitcl::class ::C {}"
	defs := tcl.FileDefs(src)
	syms := buildDocumentSymbols(defs, src, false)
	// flatten for lookup: global symbols are at root
	byName := map[string]DocumentSymbol{}
	for _, s := range syms {
		byName[s.Name] = s
	}
	if byName["render"].Kind != SymKindFunction {
		t.Fatalf("render kind = %d", byName["render"].Kind)
	}
	if byName["::C"].Kind != SymKindClass {
		t.Fatalf("::C kind = %d", byName["::C"].Kind)
	}
	// range must contain selectionRange
	r := byName["::render"]
	if !posLE(r.Range.Start, r.SelectionRange.Start) || !posLE(r.SelectionRange.End, r.Range.End) {
		t.Fatalf("range must contain selectionRange: %#v", r)
	}
}

func TestBuildDocumentSymbolsNested(t *testing.T) {
	src := "namespace eval ::app {\n  proc helper {} {}\n}\nitcl::class ::Disp {\n  method field {} {}\n  variable count 0\n}"
	syms := buildDocumentSymbols(tcl.FileDefs(src), src, false)
	app := findSym(syms, "::app")
	if app == nil || app.Kind != SymKindNamespace || findChild(app, "helper") == nil {
		t.Fatalf("::app namespace node with helper child missing: %#v", syms)
	}
	disp := findSym(syms, "::Disp")
	if disp == nil || disp.Kind != SymKindClass {
		t.Fatalf("::Disp class node missing: %#v", syms)
	}
	if findChild(disp, "field") == nil || findChild(disp, "count") == nil {
		t.Fatalf("::Disp method/ivar children missing: %#v", disp.Children)
	}
}

func findSym(syms []DocumentSymbol, name string) *DocumentSymbol {
	for i := range syms {
		if syms[i].Name == name {
			return &syms[i]
		}
		if got := findSym(syms[i].Children, name); got != nil {
			return got
		}
	}
	return nil
}

func findChild(s *DocumentSymbol, name string) *DocumentSymbol {
	for i := range s.Children {
		if s.Children[i].Name == name {
			return &s.Children[i]
		}
	}
	return nil
}

func TestBuildDocumentSymbolsRVTHoist(t *testing.T) {
	// Defs as produced for a .rvt page live in the ::request namespace.
	defs := source.Defs("page.rvt", "<? proc render {} {} ?>")
	syms := buildDocumentSymbols(defs, "<? proc render {} {} ?>", true)
	if findSym(syms, "render") == nil {
		t.Fatalf("render should be hoisted to root: %#v", syms)
	}
	// the ::request wrapper node must not appear at root
	for _, s := range syms {
		if s.Name == "::request" {
			t.Fatalf("::request wrapper should be elided, got %#v", syms)
		}
	}
}

func TestSymbolKind(t *testing.T) {
	tests := []struct {
		kind    tcl.DefKind
		want    SymbolKind
		wantOK  bool
	}{
		{tcl.DefProc, SymKindFunction, true},
		{tcl.DefMethod, SymKindMethod, true},
		{tcl.DefIvar, SymKindField, true},
		{tcl.DefClass, SymKindClass, true},
		{tcl.DefNamespaceVar, SymKindVariable, true},
		{tcl.DefLocal, 0, false},
		{tcl.DefGlobalLink, 0, false},
	}
	for _, tc := range tests {
		got, ok := symbolKind(tc.kind)
		if ok != tc.wantOK {
			t.Errorf("symbolKind(%d): ok = %v, want %v", tc.kind, ok, tc.wantOK)
		}
		if ok && got != tc.want {
			t.Errorf("symbolKind(%d): kind = %d, want %d", tc.kind, got, tc.want)
		}
	}
}
