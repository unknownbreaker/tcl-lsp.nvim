package tcl

// Kind enumerates the token categories the scanner emits.
type Kind int

const (
	KindEOF       Kind = iota // end of input
	KindNewline               // "\n" — a command separator
	KindSemicolon             // ";"  — a command separator
	KindComment               // "# ..." to end of line (only at command start)
	KindWord                  // one word: bare, {braced}, or "quoted" (raw text)
)

// Token is a lexical unit with its raw source text and byte range [Start,End).
type Token struct {
	Kind  Kind
	Text  string
	Start int
	End   int
}

// Scan tokenizes src into a slice of tokens always terminated by KindEOF.
func Scan(src string) []Token {
	s := &scanner{src: src, atCommandStart: true}
	return s.scan()
}

type scanner struct {
	src            string
	pos            int
	atCommandStart bool
	toks           []Token
}

func (s *scanner) emit(k Kind, start, end int) {
	s.toks = append(s.toks, Token{Kind: k, Text: s.src[start:end], Start: start, End: end})
}

func (s *scanner) scan() []Token {
	for s.pos < len(s.src) {
		c := s.src[s.pos]
		switch {
		case c == ' ' || c == '\t':
			s.pos++
		case c == '\n':
			s.emit(KindNewline, s.pos, s.pos+1)
			s.pos++
			s.atCommandStart = true
		case c == ';':
			s.emit(KindSemicolon, s.pos, s.pos+1)
			s.pos++
			s.atCommandStart = true
		case c == '#' && s.atCommandStart:
			s.scanComment()
		default:
			s.scanWord()
			s.atCommandStart = false
		}
	}
	s.emit(KindEOF, s.pos, s.pos)
	return s.toks
}

func (s *scanner) scanWord() {
	start := s.pos
	switch s.src[s.pos] {
	case '{':
		s.scanBraced()
	case '"':
		s.scanQuoted()
	default:
		s.scanBare()
	}
	s.emit(KindWord, start, s.pos)
}

// scanQuoted advances over a "quoted" word to the next unescaped quote.
// Tolerant of unterminated input.
func (s *scanner) scanQuoted() {
	s.pos++ // opening quote
	for s.pos < len(s.src) {
		c := s.src[s.pos]
		switch {
		case c == '\\' && s.pos+1 < len(s.src):
			s.pos += 2
			continue
		case c == '"':
			s.pos++ // closing quote
			return
		}
		s.pos++
	}
}

// scanBraced advances over a {braced} word, honoring nesting. Backslash escapes
// the next byte so \{ and \} do not change depth. Tolerant of unterminated input.
func (s *scanner) scanBraced() {
	depth := 0
	for s.pos < len(s.src) {
		c := s.src[s.pos]
		switch {
		case c == '\\' && s.pos+1 < len(s.src):
			s.pos += 2
			continue
		case c == '{':
			depth++
		case c == '}':
			depth--
			if depth == 0 {
				s.pos++ // consume closing brace
				return
			}
		}
		s.pos++
	}
}

// scanComment advances over a comment from '#' to (but not including) newline.
// A backslash-newline continues the comment onto the next physical line.
func (s *scanner) scanComment() {
	start := s.pos
	for s.pos < len(s.src) && s.src[s.pos] != '\n' {
		if s.src[s.pos] == '\\' && s.pos+1 < len(s.src) {
			s.pos += 2
			continue
		}
		s.pos++
	}
	s.emit(KindComment, start, s.pos)
}

// scanBare advances past a bareword, stopping at unescaped word terminators.
func (s *scanner) scanBare() {
	for s.pos < len(s.src) {
		c := s.src[s.pos]
		switch {
		case c == '\\' && s.pos+1 < len(s.src):
			s.pos += 2
		case c == '[':
			s.scanBracket()
		case c == ' ' || c == '\t' || c == '\n' || c == ';':
			return
		default:
			s.pos++
		}
	}
}

// scanBracket advances over a balanced [command substitution] span, backslash-
// aware. Tolerant of unterminated input. (Pragmatic depth counting; a closing
// bracket inside a nested brace is a rare edge case accepted as a known limit.)
func (s *scanner) scanBracket() {
	depth := 0
	for s.pos < len(s.src) {
		c := s.src[s.pos]
		switch {
		case c == '\\' && s.pos+1 < len(s.src):
			s.pos += 2
			continue
		case c == '[':
			depth++
		case c == ']':
			depth--
			if depth == 0 {
				s.pos++
				return
			}
		}
		s.pos++
	}
}
