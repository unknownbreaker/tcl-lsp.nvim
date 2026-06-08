package lsp

import (
	"encoding/json"
	"io"
	"log"

	"github.com/unknownbreaker/tcl-lsp/internal/index"
	"github.com/unknownbreaker/tcl-lsp/internal/resolve"
)

// Server is a single-goroutine LSP server: it reads and dispatches messages
// sequentially, so the index/resolver need no locking.
type Server struct {
	conn *Conn
	ix   *index.Index
	res  *resolve.Resolver
	docs map[string]string // uri -> live text
}

// NewServer builds a server over conn with an empty index.
func NewServer(conn *Conn) *Server {
	ix := index.New()
	return &Server{conn: conn, ix: ix, res: resolve.New(ix), docs: map[string]string{}}
}

// Run reads and dispatches messages until exit or the stream ends.
func (s *Server) Run() error {
	for {
		m, err := s.conn.Read()
		if err != nil {
			if err == io.EOF {
				return nil
			}
			return err
		}
		if s.dispatch(m) {
			return nil
		}
	}
}

// dispatch handles one message; returns true to stop the server (exit).
func (s *Server) dispatch(m *Message) (stop bool) {
	defer func() {
		if r := recover(); r != nil {
			log.Printf("panic in dispatch(%s): %v", m.Method, r)
			if len(m.ID) > 0 {
				s.reply(m.ID, nil) // avoid leaving a request unanswered
			}
		}
	}()
	switch m.Method {
	case "initialize":
		var p InitializeParams
		_ = json.Unmarshal(m.Params, &p)
		root := p.RootPath
		if root == "" && p.RootURI != "" {
			root = uriToPath(p.RootURI)
		}
		if root != "" {
			// Best-effort: IndexDir continues past unreadable entries and returns
			// an aggregated error, which we log (stderr) rather than fail on.
			if err := s.ix.IndexDir(root); err != nil {
				log.Printf("workspace index (%s): %v", root, err)
			}
		}
		s.reply(m.ID, InitializeResult{Capabilities: ServerCapabilities{
			TextDocumentSync: 1, DefinitionProvider: true, ReferencesProvider: true,
		}})
	case "initialized":
		// notification; no-op
	case "shutdown":
		s.reply(m.ID, nil)
	case "textDocument/didOpen":
		var p DidOpenParams
		if err := json.Unmarshal(m.Params, &p); err != nil {
			log.Printf("didOpen: bad params: %v", err)
			break
		}
		s.setDoc(p.TextDocument.URI, p.TextDocument.Text)
	case "textDocument/didChange":
		var p DidChangeParams
		if err := json.Unmarshal(m.Params, &p); err != nil {
			log.Printf("didChange: bad params: %v", err)
			break
		}
		if n := len(p.ContentChanges); n > 0 {
			s.setDoc(p.TextDocument.URI, p.ContentChanges[n-1].Text)
		}
	case "textDocument/didClose":
		var p DidCloseParams
		if err := json.Unmarshal(m.Params, &p); err != nil {
			log.Printf("didClose: bad params: %v", err)
			break
		}
		delete(s.docs, p.TextDocument.URI)
	case "textDocument/definition":
		var p TextDocumentPositionParams
		_ = json.Unmarshal(m.Params, &p)
		s.reply(m.ID, s.handleDefinition(p))
	case "textDocument/references":
		var p ReferenceParams
		_ = json.Unmarshal(m.Params, &p)
		s.reply(m.ID, s.handleReferences(p))
	case "exit":
		return true
	default:
		// Unknown request: reply null so the client does not hang. Unknown
		// notifications (no id) are ignored. Document-sync and feature methods
		// are added in the next task.
		if len(m.ID) > 0 {
			s.reply(m.ID, nil)
		}
	}
	return false
}

// reply writes a JSON-RPC response for the given id. A nil result is sent as
// JSON null. A marshal failure is logged and reported as an internal error so
// the client does not hang.
func (s *Server) reply(id json.RawMessage, result any) {
	raw := json.RawMessage("null")
	if result != nil {
		b, err := json.Marshal(result)
		if err != nil {
			log.Printf("reply: marshal error for id %s: %v", string(id), err)
			_ = s.conn.Write(&Message{ID: id, Error: &ResponseError{Code: -32603, Message: "internal error"}})
			return
		}
		raw = b
	}
	_ = s.conn.Write(&Message{ID: id, Result: raw})
}

// setDoc stores a document's live text and re-indexes it.
func (s *Server) setDoc(uri, text string) {
	s.docs[uri] = text
	s.ix.IndexFile(uriToPath(uri), text)
}

// sourceOf returns the best-available source for a path: the live document if
// open, else the indexed copy.
func (s *Server) sourceOf(path string) string {
	if t, ok := s.docs[pathToURI(path)]; ok {
		return t
	}
	return s.ix.Source(path)
}

func (s *Server) handleDefinition(p TextDocumentPositionParams) []Location {
	path := uriToPath(p.TextDocument.URI)
	src := s.sourceOf(path)
	off := ByteOffset(src, p.Position.Line, p.Position.Character)
	return s.toLocations(s.res.Definition(path, src, off))
}

func (s *Server) handleReferences(p ReferenceParams) []Location {
	path := uriToPath(p.TextDocument.URI)
	src := s.sourceOf(path)
	off := ByteOffset(src, p.Position.Line, p.Position.Character)
	locs := s.res.References(path, src, off)
	// includeDeclaration (true by default in most clients): prepend the symbol's
	// declaration site(s), which are not themselves invocation references.
	// Declarations (not Definition) resolves even when the cursor is on the
	// definition, so `gr` on the proc name still lists it.
	if p.Context.IncludeDeclaration {
		locs = mergeLocations(s.res.Declarations(path, src, off), locs)
	}
	return s.toLocations(locs)
}

// mergeLocations concatenates two location lists, declarations first, dropping
// any whose file and name-range already appear (a declaration is never also an
// invocation site, but this keeps the result free of accidental duplicates).
func mergeLocations(decls, refs []index.Location) []index.Location {
	type key struct {
		file       string
		start, end int
	}
	seen := make(map[key]bool, len(decls)+len(refs))
	out := make([]index.Location, 0, len(decls)+len(refs))
	for _, group := range [][]index.Location{decls, refs} {
		for _, l := range group {
			k := key{l.File, l.NameStart, l.NameEnd}
			if seen[k] {
				continue
			}
			seen[k] = true
			out = append(out, l)
		}
	}
	return out
}

// toLocations converts resolver locations (byte ranges) to LSP locations.
func (s *Server) toLocations(locs []index.Location) []Location {
	var out []Location
	for _, l := range locs {
		src := s.sourceOf(l.File)
		sl, sc := LSPPosition(src, l.NameStart)
		el, ec := LSPPosition(src, l.NameEnd)
		out = append(out, Location{
			URI: pathToURI(l.File),
			Range: Range{
				Start: Position{Line: sl, Character: sc},
				End:   Position{Line: el, Character: ec},
			},
		})
	}
	return out
}
