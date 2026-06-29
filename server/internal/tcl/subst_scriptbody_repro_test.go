package tcl

import "testing"

// Repro: a command call inside the braced SCRIPT body of a command that is itself
// inside a [command substitution] is not found by FileRefs. The substitution path
// (substRefs -> CommandRefs) descends nested [..] but not the script bodies of the
// commands it parses, so `myproc` here is invisible to goto-def / references.
func hasCommandRef(refs []ContextRef, name string) bool {
	for _, r := range refs {
		if r.Ref.Kind == RefCommand && r.Ref.Name == name {
			return true
		}
	}
	return false
}

func TestSubstScriptBody_SimpleCatch(t *testing.T) {
	// `myproc` is inside catch's script body, which is inside [catch ...].
	src := "set x [catch {myproc} err]"
	refs := FileRefs(src)
	if !hasCommandRef(refs, "myproc") {
		t.Fatalf("myproc not found as a command ref; got %+v", refs)
	}
}

func TestSubstScriptBody_UserRepro(t *testing.T) {
	// The exact shape the user hit: if-condition expr -> [catch ...] -> catch body
	// -> set -> "quoted" -> [lindex [myproc ...] 0].
	src := `if {![catch {set v_description "[lindex [myproc $thing1 0 0 $thing2] 0]"} err]} {
  puts done
}`
	refs := FileRefs(src)
	if !hasCommandRef(refs, "myproc") {
		t.Fatalf("myproc not found in user repro; got %+v", refs)
	}
}
