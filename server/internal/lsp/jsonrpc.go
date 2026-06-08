// Package lsp implements the Language Server Protocol shell (JSON-RPC framing,
// position conversion, and the request handlers) over stdio.
package lsp

import (
	"bufio"
	"encoding/json"
	"fmt"
	"io"
	"strconv"
	"strings"
	"sync"
)

// Message is a JSON-RPC 2.0 message (request, notification, or response). Unused
// fields are omitted on the wire.
type Message struct {
	JSONRPC string          `json:"jsonrpc"`
	ID      json.RawMessage `json:"id,omitempty"`
	Method  string          `json:"method,omitempty"`
	Params  json.RawMessage `json:"params,omitempty"`
	Result  json.RawMessage `json:"result,omitempty"`
	Error   *ResponseError  `json:"error,omitempty"`
}

// ResponseError is a JSON-RPC error object.
type ResponseError struct {
	Code    int    `json:"code"`
	Message string `json:"message"`
}

// Conn reads and writes LSP messages (Content-Length framed) over a stream.
type Conn struct {
	r  *bufio.Reader
	w  io.Writer
	mu sync.Mutex // serializes writes
}

// NewConn wraps a reader/writer pair (typically stdin/stdout).
func NewConn(r io.Reader, w io.Writer) *Conn {
	return &Conn{r: bufio.NewReader(r), w: w}
}

// Read reads one framed message. Returns io.EOF when the stream ends cleanly.
func (c *Conn) Read() (*Message, error) {
	contentLen := -1
	for {
		line, err := c.r.ReadString('\n')
		if err != nil {
			return nil, err
		}
		line = strings.TrimRight(line, "\r\n")
		if line == "" {
			break // blank line terminates the header block
		}
		if v, ok := strings.CutPrefix(line, "Content-Length:"); ok {
			n, err := strconv.Atoi(strings.TrimSpace(v))
			if err != nil {
				return nil, fmt.Errorf("invalid Content-Length: %w", err)
			}
			contentLen = n
		}
		// other headers (e.g. Content-Type) are ignored
	}
	if contentLen < 0 {
		return nil, fmt.Errorf("message missing Content-Length header")
	}
	body := make([]byte, contentLen)
	if _, err := io.ReadFull(c.r, body); err != nil {
		return nil, err
	}
	var m Message
	if err := json.Unmarshal(body, &m); err != nil {
		return nil, fmt.Errorf("invalid message body: %w", err)
	}
	return &m, nil
}

// Write frames and writes one message. Safe for concurrent use.
func (c *Conn) Write(m *Message) error {
	m.JSONRPC = "2.0"
	body, err := json.Marshal(m)
	if err != nil {
		return err
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	if _, err := fmt.Fprintf(c.w, "Content-Length: %d\r\n\r\n", len(body)); err != nil {
		return err
	}
	_, err = c.w.Write(body)
	return err
}
