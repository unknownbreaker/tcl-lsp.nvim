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
	// Word/separator/comment branches are added in later tasks.
	s.emit(KindEOF, s.pos, s.pos)
	return s.toks
}
