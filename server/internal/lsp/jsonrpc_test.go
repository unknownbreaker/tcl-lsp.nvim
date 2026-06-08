package lsp

import (
	"bytes"
	"encoding/json"
	"io"
	"strings"
	"testing"
)

func TestConnWriteThenRead(t *testing.T) {
	var out bytes.Buffer
	w := NewConn(bytes.NewReader(nil), &out)
	if err := w.Write(&Message{Method: "initialize", ID: json.RawMessage("1")}); err != nil {
		t.Fatalf("write: %v", err)
	}
	// The framed bytes must start with a Content-Length header.
	if !bytes.HasPrefix(out.Bytes(), []byte("Content-Length: ")) {
		t.Fatalf("missing Content-Length header: %q", out.String())
	}

	r := NewConn(bytes.NewReader(out.Bytes()), io.Discard)
	m, err := r.Read()
	if err != nil {
		t.Fatalf("read: %v", err)
	}
	if m.JSONRPC != "2.0" {
		t.Fatalf("jsonrpc = %q, want 2.0", m.JSONRPC)
	}
	if m.Method != "initialize" || string(m.ID) != "1" {
		t.Fatalf("round-trip mismatch: method=%q id=%q", m.Method, string(m.ID))
	}
}

func TestConnReadTwoMessages(t *testing.T) {
	var buf bytes.Buffer
	w := NewConn(bytes.NewReader(nil), &buf)
	_ = w.Write(&Message{Method: "a"})
	_ = w.Write(&Message{Method: "b"})

	r := NewConn(bytes.NewReader(buf.Bytes()), io.Discard)
	m1, err := r.Read()
	if err != nil || m1.Method != "a" {
		t.Fatalf("first message: %v / %q", err, m1.Method)
	}
	m2, err := r.Read()
	if err != nil || m2.Method != "b" {
		t.Fatalf("second message: %v / %q", err, m2.Method)
	}
}

func TestConnReadEOF(t *testing.T) {
	r := NewConn(bytes.NewReader(nil), io.Discard)
	if _, err := r.Read(); err != io.EOF {
		t.Fatalf("expected io.EOF on empty input, got %v", err)
	}
}

func TestConnContentLengthZero(t *testing.T) {
	r := NewConn(strings.NewReader("Content-Length: 0\r\n\r\n"), io.Discard)
	if _, err := r.Read(); err == nil {
		t.Fatal("expected error for Content-Length: 0")
	}
}

func TestConnMalformedContentLength(t *testing.T) {
	r := NewConn(strings.NewReader("Content-Length: abc\r\n\r\n"), io.Discard)
	if _, err := r.Read(); err == nil {
		t.Fatal("expected error for non-integer Content-Length")
	}
}

func TestConnContentLengthTooLarge(t *testing.T) {
	r := NewConn(strings.NewReader("Content-Length: 999999999999\r\n\r\n"), io.Discard)
	if _, err := r.Read(); err == nil {
		t.Fatal("expected error for oversized Content-Length (must not allocate)")
	}
}

func TestConnMidBodyEOF(t *testing.T) {
	// Declares 50 bytes but provides only 2 -> io.ReadFull errors.
	r := NewConn(strings.NewReader("Content-Length: 50\r\n\r\n{}"), io.Discard)
	if _, err := r.Read(); err == nil {
		t.Fatal("expected error for truncated body")
	}
}
