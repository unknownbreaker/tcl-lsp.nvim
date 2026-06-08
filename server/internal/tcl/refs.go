package tcl

// RefKind classifies a reference by its syntactic position.
type RefKind int

const (
	RefCommand  RefKind = iota // command-position name (a command being invoked)
	RefVariable                // a $-substituted variable
)

// Reference is one classified identifier occurrence with an absolute byte range.
type Reference struct {
	Kind  RefKind
	Name  string
	Start int
	End   int
}

// CommandRefs returns the references in a single command: the command-position
// name (when the first word is a literal name) plus the variable references in
// every word. Offsets are absolute when the command's word offsets are absolute
// (as produced by Parse on source text). References nested inside
// [command substitution] spans are included via substRefs.
func CommandRefs(c Command) []Reference {
	var refs []Reference
	isExpr := len(c.Words) > 0 && isLiteralName(c.Words[0]) && c.Words[0].Text == "expr"
	for idx, w := range c.Words {
		if idx == 0 && isLiteralName(w) {
			refs = append(refs, Reference{Kind: RefCommand, Name: w.Text, Start: w.Start, End: w.End})
			continue
		}
		if isExpr && w.Kind == WordBraced {
			// expr evaluates [command substitutions] inside its braces even though
			// braces otherwise suppress substitution. Scan only the bracket spans so
			// embedded calls are found while bare operands stay non-references.
			inner, innerBase := bracedInner(w, 0)
			refs = append(refs, exprBracketRefs(inner, innerBase)...)
			continue
		}
		refs = append(refs, wordRefs(w)...)
	}
	return refs
}

// exprBracketRefs scans an expr's braced argument for [command substitution]
// spans only, recursing into each via substRefs. Unlike scanRefs it ignores
// bare $vars and operands, which are not substituted inside an expr brace.
func exprBracketRefs(text string, base int) []Reference {
	var refs []Reference
	i := 0
	for i < len(text) {
		switch c := text[i]; {
		case c == '\\' && i+1 < len(text):
			i += 2
		case c == '[':
			end := skipBracketSpan(text, i) // index just past the matching ']'
			innerEnd := end
			if end > i+1 && text[end-1] == ']' {
				innerEnd = end - 1
			}
			refs = append(refs, substRefs(text[i+1:innerEnd], base+i+1)...)
			i = end
		default:
			i++
		}
	}
	return refs
}

// isLiteralName reports whether a word is a static command name: a bareword with
// no substitution ($ or [). Dynamic heads ($cmd, [get]) are not command names.
func isLiteralName(w Word) bool {
	if w.Kind != WordBare || w.Text == "" {
		return false
	}
	for i := 0; i < len(w.Text); i++ {
		if w.Text[i] == '$' || w.Text[i] == '[' {
			return false
		}
	}
	return true
}

// wordRefs scans one word for variable references and command substitutions.
// Braced words undergo no substitution and yield none. Bare and quoted words are
// scanned for $var refs and [cmd] spans; bracket interiors are recursed into via
// substRefs.
func wordRefs(w Word) []Reference {
	if w.Kind == WordBraced {
		return nil
	}
	return scanRefs(w.Text, w.Start)
}

// scanRefs differs from scanVarRefs (varref.go): it descends into [cmd] spans
// (via substRefs) rather than skipping them, and also reports command-position
// names found inside those spans.
func scanRefs(text string, base int) []Reference {
	var refs []Reference
	i := 0
	for i < len(text) {
		c := text[i]
		switch {
		case c == '\\' && i+1 < len(text):
			i += 2
		case c == '$':
			ref, next, ok := parseVarRef(text, i, base)
			if ok {
				refs = append(refs, Reference{Kind: RefVariable, Name: ref.Name, Start: ref.Start, End: ref.End})
			}
			i = next
		case c == '[':
			end := skipBracketSpan(text, i) // index just past the matching ']'
			innerEnd := end
			// Strip the closing ']' if present; on unterminated input
			// skipBracketSpan returns len(text) and there is no ']' to remove.
			if end > i+1 && text[end-1] == ']' {
				innerEnd = end - 1
			}
			refs = append(refs, substRefs(text[i+1:innerEnd], base+i+1)...)
			i = end
		default:
			i++
		}
	}
	return refs
}

// substRefs extracts references from the interior of a [command substitution].
// innerBase is the absolute offset of the interior's first byte. The interior is
// itself a script, so it is parsed and each command recursed into; offsets are
// shifted from interior-relative to absolute.
func substRefs(inner string, innerBase int) []Reference {
	var refs []Reference
	for _, c := range Parse(inner) {
		for _, r := range CommandRefs(c) {
			r.Start += innerBase
			r.End += innerBase
			refs = append(refs, r)
		}
	}
	return refs
}
