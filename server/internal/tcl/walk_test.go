package tcl

import (
	"reflect"
	"testing"
)

// richSource exercises every collector: nested namespaces, a namespace path, a
// proc with a parameter, a proc defined inside an `if` body, an itcl class with
// inherit + ivar + method, and a decorated proc.
const richSource = `namespace eval ::app {
	variable count 0
	namespace path ::other
	proc helper {x} {
		if {$x} { proc inner {} { return [compute $x] } }
		return $x
	}
}
itcl::class ::Widget {
	inherit ::Base
	variable size 10
	method draw {} { render $size }
}
CACHE_PROC proc decorated {a b} { combine $a $b }`

// TestFileAllMatchesIndividualWalkers locks the core invariant of the unified
// traversal: enabling all four collectors at once (FileAll) yields exactly the
// same per-field result as enabling each one alone (FileDefs/FileRefs/
// FileNamespaces/FileClasses). If collectors interfered, this would catch it.
func TestFileAllMatchesIndividualWalkers(t *testing.T) {
	all := FileAll(richSource)

	if got, want := all.Defs, FileDefs(richSource); !reflect.DeepEqual(got, want) {
		t.Errorf("FileAll.Defs != FileDefs\n got=%#v\nwant=%#v", got, want)
	}
	if got, want := all.Refs, FileRefs(richSource); !reflect.DeepEqual(got, want) {
		t.Errorf("FileAll.Refs != FileRefs\n got=%#v\nwant=%#v", got, want)
	}
	if got, want := all.Namespaces, FileNamespaces(richSource); !reflect.DeepEqual(got, want) {
		t.Errorf("FileAll.Namespaces != FileNamespaces\n got=%#v\nwant=%#v", got, want)
	}
	if got, want := all.Classes, FileClasses(richSource); !reflect.DeepEqual(got, want) {
		t.Errorf("FileAll.Classes != FileClasses\n got=%#v\nwant=%#v", got, want)
	}
}

// TestFileNamespacesFindsDeclInMethodBody documents the one intentional behavior
// change from the unification: because the single walk tracks the real frame
// (the former walkNS hardcoded FrameNamespace and so never descended method
// bodies), a namespace declaration inside a method body is now captured. A
// `namespace import` in a method runs in the class's enclosing namespace.
func TestFileNamespacesFindsDeclInMethodBody(t *testing.T) {
	src := "itcl::class ::Widget {\n  method draw {} {\n    namespace import ::other::*\n  }\n}"
	m := FileNamespaces(src)
	info, ok := m["::"]
	if !ok {
		t.Fatalf("expected a namespace entry for ::, got %v", m)
	}
	found := false
	for _, im := range info.Imports {
		if im == "::other::*" {
			found = true
		}
	}
	if !found {
		t.Fatalf("namespace import inside a method body was not captured: %#v", info)
	}
}

// BenchmarkFourWalks measures the old index path: four independent parses+walks
// of the same source. BenchmarkFileAll measures the unified single parse+walk.
// The ratio is the indexing speedup per file.
func BenchmarkFourWalks(b *testing.B) {
	b.ReportAllocs()
	for i := 0; i < b.N; i++ {
		_ = FileDefs(richSource)
		_ = FileRefs(richSource)
		_ = FileNamespaces(richSource)
		_ = FileClasses(richSource)
	}
}

func BenchmarkFileAll(b *testing.B) {
	b.ReportAllocs()
	for i := 0; i < b.N; i++ {
		_ = FileAll(richSource)
	}
}
