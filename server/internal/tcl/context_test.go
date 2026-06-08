package tcl

import (
	"reflect"
	"testing"
)

func TestFileRefsFlatGlobal(t *testing.T) {
	got := FileRefs("set x $y")
	want := []ContextRef{
		{Ref: Reference{Kind: RefCommand, Name: "set", Start: 0, End: 3}, Namespace: "::", Frame: FrameNamespace},
		{Ref: Reference{Kind: RefVariable, Name: "y", Start: 6, End: 8}, Namespace: "::", Frame: FrameNamespace},
	}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("\n got: %#v\nwant: %#v", got, want)
	}
}
