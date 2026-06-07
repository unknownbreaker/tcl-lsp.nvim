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
// (as produced by Parse on source text). [command substitution] recursion is
// added in a later task.
func CommandRefs(c Command) []Reference {
	var refs []Reference
	for idx, w := range c.Words {
		if idx == 0 && isLiteralName(w) {
			refs = append(refs, Reference{Kind: RefCommand, Name: w.Text, Start: w.Start, End: w.End})
			continue
		}
		refs = append(refs, wordRefs(w)...)
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

// wordRefs scans one word for variable references. Braced words undergo no
// substitution and yield none. (Bracket recursion is added in a later task.)
func wordRefs(w Word) []Reference {
	if w.Kind == WordBraced {
		return nil
	}
	return scanRefs(w.Text, w.Start)
}

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
		default:
			i++
		}
	}
	return refs
}
