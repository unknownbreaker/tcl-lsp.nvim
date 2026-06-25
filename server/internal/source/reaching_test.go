package source

import (
	"strings"
	"testing"
)

func TestReachingRVTTranslatesCoords(t *testing.T) {
	content := "<?\nproc f {} {\n  set x 1\n  set x 2\n  puts $x\n}\n?>"
	off := strings.LastIndex(content, "$x") + 1
	defs, ok := Reaching("page.rvt", content, off)
	if !ok || len(defs) != 1 {
		t.Fatalf("rvt reaching: ok=%v defs=%#v", ok, defs)
	}
	want := strings.LastIndex(content, "set x 2") + len("set ")
	if defs[0].NameStart != want {
		t.Fatalf("range %d, want the `set x 2` binding at %d (source coords)", defs[0].NameStart, want)
	}
}
