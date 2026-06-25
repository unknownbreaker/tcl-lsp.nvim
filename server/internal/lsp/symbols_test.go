package lsp

import (
	"testing"

	"github.com/unknownbreaker/tcl-lsp/internal/tcl"
)

// posLE reports whether position a is less than or equal to position b.
func posLE(a, b Position) bool {
	return a.Line < b.Line || (a.Line == b.Line && a.Character <= b.Character)
}

func TestBuildDocumentSymbolsFlat(t *testing.T) {
	src := "proc render {} {}\nitcl::class ::C {}"
	defs := tcl.FileDefs(src)
	syms := buildDocumentSymbols(defs, src)
	byName := map[string]DocumentSymbol{}
	for _, s := range syms {
		byName[s.Name] = s
	}
	if byName["::render"].Kind != SymKindFunction {
		t.Fatalf("render kind = %d", byName["::render"].Kind)
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
