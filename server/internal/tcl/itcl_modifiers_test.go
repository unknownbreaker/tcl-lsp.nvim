package tcl

import "testing"

// TestAccessModifiedMembers covers the dominant real-world Itcl form: members
// declared with public/protected/private. All must be indexed as DefMethod /
// DefIvar, and a modified method's body must still be descended (so a call
// inside it is found).
func TestAccessModifiedMembers(t *testing.T) {
	src := "::itcl::class ::C {\n" +
		"  public method show {} { helper }\n" +
		"  protected method esc {s} {}\n" +
		"  private method secret {} {}\n" +
		"  public variable title \"\"\n" +
		"  protected variable mode List\n" +
		"  private variable count 0\n" +
		"  private common REGISTRY\n" +
		"  public proc make {} {}\n" +
		"  method bare {} {}\n" +
		"  variable barevar 0\n" +
		"}"

	methods := map[string]bool{}
	ivars := map[string]bool{}
	for _, d := range FileDefs(src) {
		switch d.Kind {
		case DefMethod:
			methods[d.Name] = true
			// the name range must point at the member name, not the modifier
			if got := src[d.NameStart:d.NameEnd]; got != d.Name {
				t.Errorf("method %q name range = %q", d.Name, got)
			}
		case DefIvar:
			ivars[d.Name] = true
		}
	}

	for _, m := range []string{"show", "esc", "secret", "make", "bare"} {
		if !methods[m] {
			t.Errorf("method %q not indexed; got methods %v", m, methods)
		}
	}
	for _, v := range []string{"title", "mode", "count", "REGISTRY", "barevar"} {
		if !ivars[v] {
			t.Errorf("ivar %q not indexed; got ivars %v", v, ivars)
		}
	}

	// The body of `public method show` must be descended: the bare `helper`
	// call inside it should appear as a reference.
	var sawHelper bool
	for _, r := range FileRefs(src) {
		if src[r.Ref.Start:r.Ref.End] == "helper" {
			sawHelper = true
		}
	}
	if !sawHelper {
		t.Errorf("call inside an access-modified method body was not walked")
	}
}
