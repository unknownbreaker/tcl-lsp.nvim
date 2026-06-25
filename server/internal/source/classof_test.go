package source

import (
	"strings"
	"testing"
)

func TestClassOfRVT(t *testing.T) {
	content := "<?\nset d [::STDisplay #auto]\n$d field\n?>"
	off := strings.LastIndex(content, "$d") + 1
	got := ClassOf("page.rvt", content, off)
	if len(got) != 1 || got[0] != "::STDisplay" {
		t.Fatalf("rvt ClassOf = %#v, want [::STDisplay]", got)
	}
}
