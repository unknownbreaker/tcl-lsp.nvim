package lsp

import "net/url"

// Position is an LSP position (UTF-16 character units).
type Position struct {
	Line      int `json:"line"`
	Character int `json:"character"`
}

// Range is an LSP range.
type Range struct {
	Start Position `json:"start"`
	End   Position `json:"end"`
}

// Location is an LSP location.
type Location struct {
	URI   string `json:"uri"`
	Range Range  `json:"range"`
}

// TextDocumentIdentifier references a document by URI.
type TextDocumentIdentifier struct {
	URI string `json:"uri"`
}

// TextDocumentItem is a document with its full text.
type TextDocumentItem struct {
	URI  string `json:"uri"`
	Text string `json:"text"`
}

// DidOpenParams is textDocument/didOpen.
type DidOpenParams struct {
	TextDocument TextDocumentItem `json:"textDocument"`
}

// TextDocumentContentChangeEvent is one change (full-document sync: Text is the
// whole new content).
type TextDocumentContentChangeEvent struct {
	Text string `json:"text"`
}

// DidChangeParams is textDocument/didChange.
type DidChangeParams struct {
	TextDocument   TextDocumentIdentifier           `json:"textDocument"`
	ContentChanges []TextDocumentContentChangeEvent `json:"contentChanges"`
}

// DidCloseParams is textDocument/didClose.
type DidCloseParams struct {
	TextDocument TextDocumentIdentifier `json:"textDocument"`
}

// TextDocumentPositionParams is a position in a document (definition/references).
type TextDocumentPositionParams struct {
	TextDocument TextDocumentIdentifier `json:"textDocument"`
	Position     Position               `json:"position"`
}

// InitializeParams is the subset of initialize we use.
type InitializeParams struct {
	RootURI  string `json:"rootUri"`
	RootPath string `json:"rootPath"`
}

// InitializeResult advertises server capabilities.
type InitializeResult struct {
	Capabilities ServerCapabilities `json:"capabilities"`
}

// ServerCapabilities is the subset we advertise.
type ServerCapabilities struct {
	TextDocumentSync   int  `json:"textDocumentSync"` // 1 = full sync
	DefinitionProvider bool `json:"definitionProvider"`
	ReferencesProvider bool `json:"referencesProvider"`
}

// uriToPath converts a file:// URI to a filesystem path. A string that is not a
// file URI is returned unchanged (best effort).
func uriToPath(uri string) string {
	u, err := url.Parse(uri)
	if err != nil || u.Scheme != "file" {
		return uri
	}
	return u.Path
}

// pathToURI converts a filesystem path to a file:// URI.
func pathToURI(path string) string {
	u := url.URL{Scheme: "file", Path: path}
	return u.String()
}
