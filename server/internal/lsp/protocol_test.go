package lsp

import "testing"

func TestURIRoundTrip(t *testing.T) {
	path := "/Users/x/a b.tcl" // space must be percent-encoded
	uri := pathToURI(path)
	if uri != "file:///Users/x/a%20b.tcl" {
		t.Fatalf("pathToURI = %q", uri)
	}
	if got := uriToPath(uri); got != path {
		t.Fatalf("uriToPath = %q, want %q", got, path)
	}
}

func TestURIToPathPlainPath(t *testing.T) {
	// A non-URI string is returned as-is (best effort).
	if got := uriToPath("/already/a/path.tcl"); got != "/already/a/path.tcl" {
		t.Fatalf("uriToPath plain = %q", got)
	}
}
