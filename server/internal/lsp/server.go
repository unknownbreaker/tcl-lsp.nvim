package lsp

import (
	"encoding/json"
	"io"

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
	switch m.Method {
	case "initialize":
		var p InitializeParams
		_ = json.Unmarshal(m.Params, &p)
		root := p.RootPath
		if root == "" && p.RootURI != "" {
			root = uriToPath(p.RootURI)
		}
		if root != "" {
			_ = s.ix.IndexDir(root) // best-effort; missing/permission errors are non-fatal
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
		_ = json.Unmarshal(m.Params, &p)
		s.setDoc(p.TextDocument.URI, p.TextDocument.Text)
	case "textDocument/didChange":
		var p DidChangeParams
		_ = json.Unmarshal(m.Params, &p)
		if n := len(p.ContentChanges); n > 0 {
			s.setDoc(p.TextDocument.URI, p.ContentChanges[n-1].Text)
		}
	case "textDocument/didClose":
		var p DidCloseParams
		_ = json.Unmarshal(m.Params, &p)
		delete(s.docs, p.TextDocument.URI)
	case "textDocument/definition":
		var p TextDocumentPositionParams
		_ = json.Unmarshal(m.Params, &p)
		s.reply(m.ID, s.handleDefinition(p))
	case "textDocument/references":
		var p TextDocumentPositionParams
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
// JSON null.
func (s *Server) reply(id json.RawMessage, result interface{}) {
	raw := json.RawMessage("null")
	if result != nil {
		b, err := json.Marshal(result)
		if err != nil {
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

func (s *Server) handleReferences(p TextDocumentPositionParams) []Location {
	path := uriToPath(p.TextDocument.URI)
	src := s.sourceOf(path)
	off := ByteOffset(src, p.Position.Line, p.Position.Character)
	return s.toLocations(s.res.References(path, src, off))
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
