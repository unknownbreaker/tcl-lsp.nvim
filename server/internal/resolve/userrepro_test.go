package resolve

import (
	"strings"
	"testing"

	"github.com/unknownbreaker/tcl-lsp/internal/index"
)

// Mirrors the user's real structure: a global proc defined in a .tcl, called
// from a .rvt inside an `if {…} { … }` block, on a line after a comment, inside
// command substitution. goto-def from the .rvt works for them; find-references
// from the .tcl definition reportedly returns nothing.
const userTCL = `proc my_awesome_proc {p_searchterm} {
    return $p_searchterm
}`

// Normal multi-line formatting (comment on its own line).
const userRVTMultiline = `<?
if {[awesome_config awesomeness_enabled 0]} {
    # Search things - take awesomeness into account.
    set things [my_awesome_proc $response(searchterm)]
} else {
    set things {}
}
?>`

// Collapsed onto one line (comment and the set share a line) — as pasted.
const userRVTCollapsed = `<? if {[awesome_config awesomeness_enabled 0]} {    # Search things - take awesomeness into account.    set things [my_awesome_proc $response(searchterm)]} else { set things {} } ?>`

func runUserCase(t *testing.T, rvt string) (defWorks, refFound bool, refs []index.Location) {
	t.Helper()
	ix := index.New()
	ix.IndexFile("helpers.tcl", userTCL)
	ix.IndexFile("page.rvt", rvt)
	r := New(ix)

	// Direction 1: goto-def from the .rvt call (user says this works).
	callOff := strings.Index(rvt, "my_awesome_proc")
	defs := r.Definition("page.rvt", rvt, callOff)
	for _, d := range defs {
		if d.File == "helpers.tcl" {
			defWorks = true
		}
	}

	// Direction 2: find-references from the .tcl proc definition.
	defOff := strings.Index(userTCL, "my_awesome_proc")
	refs = r.References("helpers.tcl", userTCL, defOff)
	for _, l := range refs {
		if l.File == "page.rvt" {
			refFound = true
		}
	}
	return defWorks, refFound, refs
}

func TestUserCaseMultiline(t *testing.T) {
	defWorks, refFound, refs := runUserCase(t, userRVTMultiline)
	t.Logf("multiline: defWorks=%v refFound=%v refs=%#v", defWorks, refFound, refs)
	if defWorks && !refFound {
		t.Errorf("REPRODUCED: goto-def works but find-refs misses the .rvt call (multiline)")
	}
	if !refFound {
		t.Errorf("find-refs missed the .rvt call (multiline)")
	}
}

func TestUserCaseCollapsed(t *testing.T) {
	// When the comment and the `set` share a line, the `#` comment runs to the
	// end of the line and swallows the call — so it is correctly NOT a reference
	// (and goto-def from it also fails). This documents that real TCL semantics:
	// a call hidden behind an inline comment is genuinely not a call.
	defWorks, refFound, _ := runUserCase(t, userRVTCollapsed)
	if defWorks || refFound {
		t.Errorf("a call swallowed by a # comment must not resolve: defWorks=%v refFound=%v", defWorks, refFound)
	}
}
