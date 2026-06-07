package tcl

// VarRef is a $-substitution occurrence within a word, with an absolute byte
// range [Start,End) covering the reference token (e.g. "$x").
type VarRef struct {
	Name  string
	Start int
	End   int
}

// WordVarRefs returns the variable references substituted inside a single word.
// Braced words undergo no substitution and yield none. Bare and quoted words are
// scanned for $name forms. Interiors of [command substitution] spans are NOT
// descended here (handled later with the command walker).
func WordVarRefs(w Word) []VarRef {
	if w.Kind == WordBraced {
		return nil
	}
	return scanVarRefs(w.Text, w.Start)
}

func scanVarRefs(text string, base int) []VarRef {
	var refs []VarRef
	i := 0
	for i < len(text) {
		if text[i] == '$' {
			ref, next, ok := parseVarRef(text, i, base)
			if ok {
				refs = append(refs, ref)
			}
			i = next
		} else {
			i++
		}
	}
	return refs
}

func parseVarRef(text string, dollar, base int) (VarRef, int, bool) {
	i := dollar + 1
	if i >= len(text) {
		return VarRef{}, dollar + 1, false
	}
	if text[i] == '{' {
		j := i + 1
		for j < len(text) && text[j] != '}' {
			j++
		}
		if j >= len(text) {
			return VarRef{}, len(text), false // unterminated ${ : tolerant
		}
		return VarRef{Name: text[i+1 : j], Start: base + dollar, End: base + j + 1}, j + 1, true
	}
	if !isNameByte(text[i]) {
		return VarRef{}, dollar + 1, false
	}
	j := i
	for j < len(text) && isNameByte(text[j]) {
		j++
	}
	return VarRef{Name: text[i:j], Start: base + dollar, End: base + j}, j, true
}

func isNameByte(b byte) bool {
	return b == '_' ||
		(b >= 'a' && b <= 'z') ||
		(b >= 'A' && b <= 'Z') ||
		(b >= '0' && b <= '9')
}
