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
