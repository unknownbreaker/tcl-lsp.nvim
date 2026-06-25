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
