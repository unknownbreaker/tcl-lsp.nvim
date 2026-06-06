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
			s.pos++ // inter-word whitespace is not emitted
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
	s.scanBare()
	s.emit(KindWord, start, s.pos)
}

// scanBare advances past a bareword, stopping at unescaped word terminators.
func (s *scanner) scanBare() {
	for s.pos < len(s.src) {
		c := s.src[s.pos]
		switch c {
		case ' ', '\t', '\n', ';':
			return
		default:
			s.pos++
		}
	}
}
