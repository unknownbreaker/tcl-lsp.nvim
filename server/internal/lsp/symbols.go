package lsp

import "github.com/unknownbreaker/tcl-lsp/internal/tcl"

// symbolKind maps a tcl.DefKind to an LSP SymbolKind.
// Returns (kind, true) for symbol-worthy definitions, (0, false) for locals and links.
func symbolKind(k tcl.DefKind) (SymbolKind, bool) {
	switch k {
	case tcl.DefProc:
		return SymKindFunction, true
	case tcl.DefMethod:
		return SymKindMethod, true
	case tcl.DefIvar:
		return SymKindField, true
	case tcl.DefClass:
		return SymKindClass, true
	case tcl.DefNamespaceVar:
		return SymKindVariable, true
	default:
		return 0, false
	}
}

// buildDocumentSymbols converts a slice of tcl.Definition values into a flat
// list of DocumentSymbol values. Locals and global links are skipped. Range is
// the full extent of the defining command; SelectionRange is the name token.
// If the full extent does not contain the name range (or is zero), Range falls
// back to the name range.
func buildDocumentSymbols(defs []tcl.Definition, src string) []DocumentSymbol {
	var out []DocumentSymbol
	for _, d := range defs {
		kind, ok := symbolKind(d.Kind)
		if !ok {
			continue
		}

		selStart := offsetToPosition(src, d.NameStart)
		selEnd := offsetToPosition(src, d.NameEnd)
		selRange := Range{Start: selStart, End: selEnd}

		// Use the full extent as Range, but guard the invariant that Range must
		// contain SelectionRange. Fall back to the name range when the full extent
		// is zero or does not contain the name range.
		var fullRange Range
		if d.FullStart == 0 && d.FullEnd == 0 {
			fullRange = selRange
		} else {
			fullStart := offsetToPosition(src, d.FullStart)
			fullEnd := offsetToPosition(src, d.FullEnd)
			if posContains(fullStart, fullEnd, selStart, selEnd) {
				fullRange = Range{Start: fullStart, End: fullEnd}
			} else {
				fullRange = selRange
			}
		}

		out = append(out, DocumentSymbol{
			Name:           d.Name,
			Kind:           kind,
			Range:          fullRange,
			SelectionRange: selRange,
		})
	}
	return out
}

// offsetToPosition converts a byte offset in src to an LSP Position.
func offsetToPosition(src string, offset int) Position {
	line, char := LSPPosition(src, offset)
	return Position{Line: line, Character: char}
}

// posContains reports whether the range [outerStart, outerEnd] contains [innerStart, innerEnd].
// All four positions are inclusive on both ends in LSP line/character space.
func posContains(outerStart, outerEnd, innerStart, innerEnd Position) bool {
	startOK := outerStart.Line < innerStart.Line ||
		(outerStart.Line == innerStart.Line && outerStart.Character <= innerStart.Character)
	endOK := outerEnd.Line > innerEnd.Line ||
		(outerEnd.Line == innerEnd.Line && outerEnd.Character >= innerEnd.Character)
	return startOK && endOK
}
