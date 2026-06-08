package lsp

import (
	"bytes"
	"encoding/json"
	"io"
	"testing"
)

// frame returns the framed bytes for one message (id nil => notification).
func frame(t *testing.T, method string, id interface{}, params interface{}) []byte {
	t.Helper()
	var buf bytes.Buffer
	c := NewConn(bytes.NewReader(nil), &buf)
	m := &Message{Method: method}
	if id != nil {
		b, _ := json.Marshal(id)
		m.ID = b
	}
	if params != nil {
		b, _ := json.Marshal(params)
		m.Params = b
	}
	if err := c.Write(m); err != nil {
		t.Fatal(err)
	}
	return buf.Bytes()
}

// runServer feeds framed input bytes through a Server and returns its responses.
func runServer(t *testing.T, input []byte) []*Message {
	t.Helper()
	var out bytes.Buffer
	s := NewServer(NewConn(bytes.NewReader(input), &out))
	if err := s.Run(); err != nil {
		t.Fatalf("Run: %v", err)
	}
	c := NewConn(bytes.NewReader(out.Bytes()), io.Discard)
	var ms []*Message
	for {
		m, err := c.Read()
		if err == io.EOF {
			break
		}
		if err != nil {
			t.Fatalf("read response: %v", err)
		}
		ms = append(ms, m)
	}
	return ms
}

func responseByID(ms []*Message, id string) *Message {
	for _, m := range ms {
		if string(m.ID) == id {
			return m
		}
	}
	return nil
}

func TestServerInitializeCapabilities(t *testing.T) {
	var in bytes.Buffer
	in.Write(frame(t, "initialize", 1, InitializeParams{}))
	in.Write(frame(t, "exit", nil, nil))

	resp := responseByID(runServer(t, in.Bytes()), "1")
	if resp == nil {
		t.Fatal("no initialize response")
	}
	var res InitializeResult
	if err := json.Unmarshal(resp.Result, &res); err != nil {
		t.Fatalf("unmarshal result: %v", err)
	}
	if !res.Capabilities.DefinitionProvider || !res.Capabilities.ReferencesProvider {
		t.Fatalf("capabilities = %#v", res.Capabilities)
	}
	if res.Capabilities.TextDocumentSync != 1 {
		t.Fatalf("textDocumentSync = %d, want 1", res.Capabilities.TextDocumentSync)
	}
}

func TestServerShutdownThenExit(t *testing.T) {
	var in bytes.Buffer
	in.Write(frame(t, "shutdown", 2, nil))
	in.Write(frame(t, "exit", nil, nil))

	resp := responseByID(runServer(t, in.Bytes()), "2")
	if resp == nil || string(resp.Result) != "null" {
		t.Fatalf("shutdown response = %#v", resp)
	}
}
