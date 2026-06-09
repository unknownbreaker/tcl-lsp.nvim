package source

import (
	"strings"
	"testing"

	"github.com/unknownbreaker/tcl-lsp/internal/tcl"
)

func TestDefsTCLPassthrough(t *testing.T) {
	defs := Defs("x.tcl", "proc greet {} {}")
	if len(defs) == 0 || defs[0].Name != "::greet" {
		t.Fatalf("tcl passthrough = %#v", defs)
	}
}

func TestDefsRVTTranslatesToSource(t *testing.T) {
	src := "<? proc greet {} {} ?>"
	want := strings.Index(src, "greet")
	var found bool
	for _, d := range Defs("page.rvt", src) {
		if d.Name == "::request::greet" {
			found = true
			if d.NameStart != want {
				t.Fatalf("greet NameStart = %d, want %d (.rvt coord)", d.NameStart, want)
			}
		}
	}
	if !found {
		t.Fatalf("::request::greet not found in %#v", Defs("page.rvt", src))
	}
}

func TestRefsRVTTranslatesAndDropsWrapper(t *testing.T) {
	src := "<? proc greet {} { hello } ?>"
	want := strings.Index(src, "hello")
	refs := Refs("page.rvt", src)

	var found bool
	for _, r := range refs {
		if r.Ref.Kind == tcl.RefCommand && r.Ref.Name == "hello" {
			found = true
			if r.Ref.Start != want {
				t.Fatalf("hello ref Start = %d, want %d (.rvt coord)", r.Ref.Start, want)
			}
		}
		// The synthetic `namespace eval ::request {` wrapper must not leak through.
		if r.Ref.Name == "namespace" {
			t.Fatalf("synthetic wrapper ref leaked: %#v", r)
		}
	}
	if !found {
		t.Fatalf("hello ref not found in %#v", refs)
	}
}
