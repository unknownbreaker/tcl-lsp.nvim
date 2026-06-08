package tcl

import (
	"reflect"
	"testing"
)

func findVar(refs []ContextRef, name string) *ContextRef {
	for i := range refs {
		if refs[i].Ref.Kind == RefVariable && refs[i].Ref.Name == name {
			return &refs[i]
		}
	}
	return nil
}

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

func TestFileRefsNamespaceEval(t *testing.T) {
	src := "namespace eval ::app {\n    set v $w\n}"
	got := FileRefs(src)
	vw := findVar(got, "w")
	if vw == nil {
		t.Fatalf("did not find var w in %#v", got)
	}
	if vw.Namespace != "::app" {
		t.Fatalf("namespace = %q, want ::app", vw.Namespace)
	}
	if vw.Frame != FrameNamespace {
		t.Fatalf("frame = %d, want FrameNamespace", vw.Frame)
	}
	if src[vw.Ref.Start:vw.Ref.End] != "$w" {
		t.Fatalf("offset slice = %q, want $w", src[vw.Ref.Start:vw.Ref.End])
	}
}

func TestFileRefsNestedNamespace(t *testing.T) {
	src := "namespace eval ::a { namespace eval b { set x $y } }"
	got := FileRefs(src)
	vy := findVar(got, "y")
	if vy == nil {
		t.Fatalf("did not find var y in %#v", got)
	}
	if vy.Namespace != "::a::b" {
		t.Fatalf("namespace = %q, want ::a::b", vy.Namespace)
	}
}

func TestFileRefsProcBody(t *testing.T) {
	src := "proc p {} {\n    set a $b\n}"
	got := FileRefs(src)
	vb := findVar(got, "b")
	if vb == nil {
		t.Fatalf("did not find var b in %#v", got)
	}
	if vb.Frame != FrameProc {
		t.Fatalf("frame = %d, want FrameProc", vb.Frame)
	}
	if vb.Namespace != "::" {
		t.Fatalf("namespace = %q, want ::", vb.Namespace)
	}
}

func TestFileRefsProcInNamespace(t *testing.T) {
	src := "namespace eval ::app {\n  proc f {} { set a $b }\n}"
	got := FileRefs(src)
	vb := findVar(got, "b")
	if vb == nil {
		t.Fatalf("did not find var b in %#v", got)
	}
	if vb.Frame != FrameProc {
		t.Fatalf("frame = %d, want FrameProc", vb.Frame)
	}
	if vb.Namespace != "::app" {
		t.Fatalf("namespace = %q, want ::app", vb.Namespace)
	}
}

func TestFileRefsCombinedAndOffsets(t *testing.T) {
	src := "namespace eval ::app {\n  variable base 10\n  proc scale {n} {\n    return [expr {$n * $base}]\n  }\n}"
	got := FileRefs(src)

	// $n is used inside proc scale's body, in namespace ::app, proc frame.
	// (It appears outside the braced expr arg? No: it is inside {$n * $base},
	// which is braced, so per the expr-braced limitation it is NOT found.)
	// Instead, assert the command refs we DO expect, and offset fidelity for one.

	// The `expr` command ref is inside proc scale's body (namespace ::app, proc frame).
	var exprRef *ContextRef
	for i := range got {
		if got[i].Ref.Kind == RefCommand && got[i].Ref.Name == "expr" {
			exprRef = &got[i]
		}
	}
	if exprRef == nil {
		t.Fatalf("did not find expr command in %#v", got)
	}
	if exprRef.Namespace != "::app" || exprRef.Frame != FrameProc {
		t.Fatalf("expr context = (%q, %d), want (::app, FrameProc)", exprRef.Namespace, exprRef.Frame)
	}
	if src[exprRef.Ref.Start:exprRef.Ref.End] != "expr" {
		t.Fatalf("expr offset slice = %q", src[exprRef.Ref.Start:exprRef.Ref.End])
	}

	// Guard the expr-braced limitation: vars inside the braced expr arg are not found.
	if findVar(got, "n") != nil || findVar(got, "base") != nil {
		t.Fatalf("did not expect expr-braced vars n/base to be found: %#v", got)
	}
}

func TestFileRefsNamespaceInsideProc(t *testing.T) {
	// Inverse nesting: namespace eval inside a proc body must RESET to
	// FrameNamespace (not inherit FrameProc) and use the inner namespace.
	src := "proc p {} { namespace eval ::sub { set x $y } }"
	got := FileRefs(src)
	vy := findVar(got, "y")
	if vy == nil {
		t.Fatalf("did not find var y in %#v", got)
	}
	if vy.Namespace != "::sub" {
		t.Fatalf("namespace = %q, want ::sub", vy.Namespace)
	}
	if vy.Frame != FrameNamespace {
		t.Fatalf("frame = %d, want FrameNamespace", vy.Frame)
	}
}
