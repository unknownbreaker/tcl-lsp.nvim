package resolve

import (
	"os"
	"path/filepath"
	"sort"
	"strings"
	"testing"

	"github.com/unknownbreaker/tcl-lsp/internal/index"
	"github.com/unknownbreaker/tcl-lsp/internal/source"
	"github.com/unknownbreaker/tcl-lsp/internal/tcl"
)

// These tests run against VERBATIM excerpts of real production code vendored in
// testdata/realworld/ (see MANIFEST.md). They pin the Itcl idioms real TCL uses —
// chiefly access-modified members (public/protected/private), which the synthetic
// fixtures never exercised and which were silently unparsed before.

func readRealworld(t *testing.T, name string) string {
	t.Helper()
	b, err := os.ReadFile(filepath.Join("testdata", "realworld", name))
	if err != nil {
		t.Fatalf("read fixture %s: %v", name, err)
	}
	return string(b)
}

func methodNames(ci *index.ClassInfo) []string {
	var out []string
	for n := range ci.Methods {
		out = append(out, n)
	}
	sort.Strings(out)
	return out
}

func ivarNames(ci *index.ClassInfo) []string {
	var out []string
	for n := range ci.Ivars {
		out = append(out, n)
	}
	sort.Strings(out)
	return out
}

// TestRealWorldAccessModifiedMembersIndexed: every access-modified member of a
// real Itcl class lands in the class table. Before the access-modifier fix the
// class table was nearly empty for this file.
func TestRealWorldAccessModifiedMembersIndexed(t *testing.T) {
	ix := index.New()
	ix.IndexFile("rweb_content.tcl", readRealworld(t, "rweb_content.tcl"))

	ci := ix.Class("::rwpage::RWContent")
	if ci == nil {
		t.Fatal("RWContent class not indexed")
	}
	// public + protected methods (inline, abstract-no-body, and external itcl::body)
	for _, m := range []string{"init", "postprocessing", "set_key", "key", "destroy", "send_headers", "prepare_content", "content_type", "mimetype"} {
		if _, ok := ci.Methods[m]; !ok {
			t.Errorf("method %q not indexed; have %v", m, methodNames(ci))
		}
	}
	// private ivars
	for _, v := range []string{"key", "hits", "stored_vars", "url_handler", "ctype"} {
		if _, ok := ci.Ivars[v]; !ok {
			t.Errorf("private ivar %q not indexed; have %v", v, ivarNames(ci))
		}
	}
}

// TestRealWorldInheritanceEdge: `inherit RWContent` in a real subclass resolves to
// the base class FQ.
func TestRealWorldInheritanceEdge(t *testing.T) {
	ix := index.New()
	ix.IndexFile("rweb_content.tcl", readRealworld(t, "rweb_content.tcl"))
	ix.IndexFile("rweb_page.tcl", readRealworld(t, "rweb_page.tcl"))

	ci := ix.Class("::rwpage::RWPage")
	if ci == nil {
		t.Fatal("RWPage class not indexed")
	}
	found := false
	for _, b := range ci.Inherit {
		if b == "::rwpage::RWContent" {
			found = true
		}
	}
	if !found {
		t.Errorf("RWPage inherit edges = %v, want to include ::rwpage::RWContent", ci.Inherit)
	}
	// The access-modified `protected proc merge_menus` is a member too.
	if _, ok := ci.Methods["merge_menus"]; !ok {
		t.Errorf("protected proc merge_menus not indexed; have %v", methodNames(ci))
	}
}

// TestRealWorldTier2ThisMethod: a `$this method` call inside a real method body
// resolves to the method's declaration (Tier-2 intra-class).
func TestRealWorldTier2ThisMethod(t *testing.T) {
	src := readRealworld(t, "rweb_content.tcl")
	ix := index.New()
	ix.IndexFile("rweb_content.tcl", src)
	r := New(ix)

	// `return [$this content_type]` inside the mimetype method.
	off := strings.Index(src, "$this content_type") + len("$this ")
	if off < len("$this ") {
		t.Fatal("could not locate $this content_type call in fixture")
	}
	locs := r.Definition("rweb_content.tcl", src, off)
	if len(locs) == 0 {
		t.Fatal("$this content_type did not resolve to a definition")
	}
	ok := false
	for _, l := range locs {
		if src[l.NameStart:l.NameEnd] == "content_type" {
			ok = true
		}
	}
	if !ok {
		t.Errorf("resolved location is not the content_type method: %#v", locs)
	}
}

// TestRealWorldNoBogusParamRefs: the signature-only methods in the real fixture
// (forward declarations whose bodies are supplied later by itcl::body) must not
// leak their parameter names as command references. mdlist/dictionary/hooks_d
// each appear only as the sole parameter of such a declaration in rweb_page.tcl.
func TestRealWorldNoBogusParamRefs(t *testing.T) {
	src := readRealworld(t, "rweb_page.tcl")
	params := map[string]bool{"mdlist": true, "dictionary": true, "hooks_d": true}
	for _, r := range source.Refs("rweb_page.tcl", src) {
		name := src[r.Ref.Start:r.Ref.End]
		if r.Ref.Kind == tcl.RefCommand && params[name] {
			t.Errorf("parameter %q of a signature-only method leaked as a command reference", name)
		}
	}
}

// TestRealWorldRvtObjMethodShape: the `$display show` call on the real speedtables
// demo page is recognized as a `$obj method` shape (the Tier-3 entry point),
// through the .rvt coordinate seam.
func TestRealWorldRvtObjMethodShape(t *testing.T) {
	src := readRealworld(t, "display_direct.rvt")
	off := strings.Index(src, "$display show") + len("$display ")
	if off < len("$display ") {
		t.Fatal("could not locate $display show call in fixture")
	}
	_, method, ok := source.ObjMethodAt("display_direct.rvt", src, off)
	if !ok || method != "show" {
		t.Fatalf("ObjMethodAt on real .rvt = (method=%q, ok=%v), want show/true", method, ok)
	}
}

// TestRealWorldStdisplay indexes the full ~2600-line STDisplay class — the
// worst-case real Itcl and the class the feature was built for. A bare-only
// parser saw almost none of its ivars (all access-modified) and far fewer
// methods, so these bounds fail without access-modifier support.
func TestRealWorldStdisplay(t *testing.T) {
	ix := index.New()
	ix.IndexFile("display.tcl", readRealworld(t, "display.tcl"))

	ci := ix.Class("::STDisplay")
	if ci == nil {
		t.Fatal("::STDisplay not indexed")
	}
	if len(ci.Methods) < 100 {
		t.Errorf("STDisplay methods = %d, want >= 100", len(ci.Methods))
	}
	if len(ci.Ivars) < 50 {
		t.Errorf("STDisplay ivars = %d, want >= 50 (nearly all are access-modified)", len(ci.Ivars))
	}
	for _, m := range []string{"escape_cgi", "escape_url", "escape_html", "names2fields"} {
		if _, ok := ci.Methods[m]; !ok { // protected/private methods
			t.Errorf("access-modified method %q not indexed", m)
		}
	}
	for _, v := range []string{"table", "ctable", "ct_selection", "case"} {
		if _, ok := ci.Ivars[v]; !ok { // public/private variables
			t.Errorf("access-modified ivar %q not indexed", v)
		}
	}

	// The boolean subclass: inheritance edge + the three-part constructor.
	cb := ix.Class("::STDisplayField_boolean")
	if cb == nil {
		t.Fatal("::STDisplayField_boolean not indexed")
	}
	inherits := false
	for _, b := range cb.Inherit {
		if b == "::STDisplayField" {
			inherits = true
		}
	}
	if !inherits {
		t.Errorf("STDisplayField_boolean inherit = %v, want to include ::STDisplayField", cb.Inherit)
	}
	if _, ok := cb.Methods["constructor"]; !ok {
		t.Errorf("STDisplayField_boolean three-part constructor not indexed")
	}
}
