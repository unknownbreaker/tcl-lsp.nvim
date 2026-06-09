package resolve

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/unknownbreaker/tcl-lsp/internal/index"
)

// These golden scenarios drive goto-definition / find-references over realistic
// .rvt shapes from the shared corpus (internal/rvt/testdata/corpus), so the test
// suite -- not a live editor -- verifies that resolution lands on the right symbol
// for cross-file, page-local, output-shorthand, and block-spanning templates.

// corpusFile reads a fixture from the shared corpus. Go runs each package's tests
// with the package dir as CWD, so the corpus is one directory over.
func corpusFile(t *testing.T, name string) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join("..", "rvt", "testdata", "corpus", name))
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func corpusContainsFile(locs []index.Location, file string) bool {
	for _, l := range locs {
		if l.File == file {
			return true
		}
	}
	return false
}

// Cross-file: a qualified call in a .rvt resolves into a .tcl namespace, and
// references from the .tcl definition include the .rvt call site.
func TestCorpusCrossFileRvtToTcl(t *testing.T) {
	lib := corpusFile(t, "petlib.tcl")
	page := corpusFile(t, "cross_file_caller.rvt")

	ix := index.New()
	ix.IndexFile("petlib.tcl", lib)
	ix.IndexFile("cross_file_caller.rvt", page)
	r := New(ix)

	off := strings.Index(page, "format_name") // the qualified call in the .rvt
	locs := r.Definition("cross_file_caller.rvt", page, off)
	if len(locs) != 1 || locs[0].File != "petlib.tcl" || locs[0].Name != "::petlib::format_name" {
		t.Fatalf("rvt->tcl goto-def = %#v", locs)
	}

	defOff := strings.Index(lib, "format_name")
	refs := r.References("petlib.tcl", lib, defOff)
	if !corpusContainsFile(refs, "cross_file_caller.rvt") {
		t.Fatalf("references to ::petlib::format_name missing the .rvt call site: %#v", refs)
	}
}

// Page-local: a bare helper defined at template top level resolves within its own
// page, and an identically-sourced second page does not cross-match.
func TestCorpusPageLocalIsolation(t *testing.T) {
	page := corpusFile(t, "page_local.rvt")

	ix := index.New()
	ix.IndexFile("a.rvt", page)
	ix.IndexFile("b.rvt", page) // same content, a different page
	r := New(ix)

	off := strings.Index(page, "[greeting") + 1 // the call, not the proc name
	locs := r.Definition("a.rvt", page, off)
	if len(locs) != 1 || locs[0].File != "a.rvt" || locs[0].Name != "::request::greeting" {
		t.Fatalf("page-local goto-def = %#v", locs)
	}

	refs := r.References("a.rvt", page, off)
	if corpusContainsFile(refs, "b.rvt") {
		t.Fatalf("page-local references leaked into b.rvt: %#v", refs)
	}
}

// Output shorthand: a $var inside <?= ?> resolves to its page-local definition.
func TestCorpusOutputShorthandVarRef(t *testing.T) {
	page := corpusFile(t, "output_shorthand.rvt")

	ix := index.New()
	ix.IndexFile("p.rvt", page)
	r := New(ix)

	off := strings.Index(page, "$name") + 1 // on the variable name inside <?= $name ?>
	locs := r.Definition("p.rvt", page, off)
	if len(locs) != 1 || locs[0].File != "p.rvt" || locs[0].Name != "::request::name" {
		t.Fatalf("output-shorthand var goto-def = %#v", locs)
	}
}

// Block-spanning: a call inside a <?= ?> that sits between <? foreach { ?> and
// <? } ?> still resolves -- proof the regions stitched into one balanced script.
func TestCorpusControlFlowSpanningResolves(t *testing.T) {
	page := corpusFile(t, "control_flow_spanning.rvt")

	ix := index.New()
	ix.IndexFile("p.rvt", page)
	r := New(ix)

	off := strings.Index(page, "[render_row") + 1 // the call inside the loop body
	locs := r.Definition("p.rvt", page, off)
	if len(locs) != 1 || locs[0].File != "p.rvt" || locs[0].Name != "::request::render_row" {
		t.Fatalf("block-spanning goto-def = %#v", locs)
	}
}
