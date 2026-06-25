package tcl

import "testing"

func TestChildBodiesItclClassFrame(t *testing.T) {
	src := "itcl::class ::C {\n  method m {} { puts hi }\n}"
	cmds := Parse(src)
	var classBody *bodyScope
	for _, c := range cmds {
		for _, b := range childBodies(c, 0, "::", FrameNamespace, 0, "") {
			bb := b
			classBody = &bb
		}
	}
	if classBody == nil || classBody.Frame != FrameClass || classBody.Class != "::C" {
		t.Fatalf("itcl::class body should be FrameClass with Class ::C, got %#v", classBody)
	}
}
