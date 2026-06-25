package tcl

import (
	"strings"
	"testing"
)

// TestConstructorThreePart covers the `constructor args {init} {body}` form
// (rivetweb style): the constructor is indexed, the body is walked, AND the
// init block's base-class chain call is found as a reference.
func TestConstructorThreePart(t *testing.T) {
	src := "::itcl::class ::RWPage {\n" +
		"  constructor {pagekey} {RWContent::constructor $pagekey} {\n" +
		"    set metadata [dict create]\n" +
		"    init_local\n" +
		"  }\n" +
		"}"
	var ctor bool
	for _, d := range FileDefs(src) {
		if d.Kind == DefMethod && d.Name == "constructor" {
			ctor = true
		}
	}
	if !ctor {
		t.Fatalf("constructor not indexed")
	}
	var bodyWalked, initWalked bool
	for _, r := range FileRefs(src) {
		switch src[r.Ref.Start:r.Ref.End] {
		case "init_local":
			bodyWalked = true
		case "RWContent::constructor":
			initWalked = true
		}
	}
	if !bodyWalked {
		t.Errorf("constructor body not walked (init_local missing)")
	}
	if !initWalked {
		t.Errorf("constructor init block not walked (base-class chain call missing)")
	}
}

// TestNamespacedAutoInstantiation guards that ClassOf types a receiver from a
// namespaced ::#auto instantiation with a literal class head.
func TestNamespacedAutoInstantiation(t *testing.T) {
	src := "namespace eval ::app {\n" +
		"  proc go {} {\n" +
		"    set w [::app::Widget ::app::#auto -size 10]\n" +
		"    $w draw\n" +
		"  }\n" +
		"}"
	useOff := strings.LastIndex(src, "$w draw") + 1
	classes := ClassOf(src, useOff)
	if len(classes) != 1 || classes[0] != "::app::Widget" {
		t.Fatalf("ClassOf($w) = %v, want [::app::Widget]", classes)
	}
}

// TestCommonBracedValueNotWalked guards that a `common` initial value in braces
// is treated as data (like `variable`), not walked as a script body that would
// emit bogus command references.
func TestCommonBracedValueNotWalked(t *testing.T) {
	src := "::itcl::class ::C {\n  common defaults {alpha beta gamma}\n}"
	for _, r := range FileRefs(src) {
		switch src[r.Ref.Start:r.Ref.End] {
		case "alpha", "beta", "gamma":
			t.Errorf("common braced value walked as script: bogus ref %q", src[r.Ref.Start:r.Ref.End])
		}
	}
}

// TestSignatureOnlyMethodArgListNotWalked: a forward-declared (signature-only)
// method has no body — its trailing brace is the parameter list, which must NOT
// be walked as a script. The method is still indexed; a real body is still
// walked.
func TestSignatureOnlyMethodArgListNotWalked(t *testing.T) {
	src := "::itcl::class ::C {\n" +
		"  public method add_metadata {field value}\n" + // signature only, body via itcl::body
		"  public method run {x} { real_call $x }\n" + // has a body
		"  method send {}\n" + // signature only, empty args
		"}\n" +
		"::itcl::body ::C::add_metadata {field value} { dict set meta $field $value }"

	methods := map[string]bool{}
	var bogus []string
	var sawReal, sawItclBody bool
	for _, d := range FileDefs(src) {
		if d.Kind == DefMethod {
			methods[d.Name] = true
		}
	}
	for _, r := range FileRefs(src) {
		switch name := src[r.Ref.Start:r.Ref.End]; {
		case r.Ref.Kind == RefCommand && (name == "field" || name == "value"):
			bogus = append(bogus, name) // a parameter name walked as a command
		case name == "real_call":
			sawReal = true // inline method body still walked
		case name == "dict":
			sawItclBody = true // external itcl::body still walked
		}
	}

	// Signature-only declarations are still indexed (goto-def/symbols preserved).
	for _, m := range []string{"add_metadata", "run", "send"} {
		if !methods[m] {
			t.Errorf("method %q not indexed", m)
		}
	}
	if len(bogus) != 0 {
		t.Errorf("parameter list walked as a script body: bogus command refs %v", bogus)
	}
	if !sawReal {
		t.Errorf("inline method body not walked (real_call missing) — regression")
	}
	if !sawItclBody {
		t.Errorf("external itcl::body not walked (dict missing) — regression")
	}
}
