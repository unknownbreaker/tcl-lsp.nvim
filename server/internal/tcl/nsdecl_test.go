package tcl

import (
	"reflect"
	"testing"
)

func TestFileNamespacesExport(t *testing.T) {
	src := "namespace eval ::a {\n  namespace export pub get*\n}"
	m := FileNamespaces(src)
	info := m["::a"]
	if info == nil {
		t.Fatalf("no NamespaceInfo for ::a in %#v", m)
	}
	if !reflect.DeepEqual(info.Exports, []string{"pub", "get*"}) {
		t.Fatalf("exports = %#v, want [pub get*]", info.Exports)
	}
}

func TestFileNamespacesExportGlobal(t *testing.T) {
	m := FileNamespaces("namespace export foo")
	info := m["::"]
	if info == nil || !reflect.DeepEqual(info.Exports, []string{"foo"}) {
		t.Fatalf("global exports = %#v", m)
	}
}

func TestFileNamespacesImport(t *testing.T) {
	src := "namespace eval ::c {\n  namespace import ::p::pub\n}"
	m := FileNamespaces(src)
	info := m["::c"]
	if info == nil || !reflect.DeepEqual(info.Imports, []string{"::p::pub"}) {
		t.Fatalf("imports = %#v", m["::c"])
	}
}

func TestFileNamespacesImportForceFlagSkipped(t *testing.T) {
	src := "namespace eval ::c {\n  namespace import -force ::p::x ::p::y\n}"
	m := FileNamespaces(src)
	info := m["::c"]
	if info == nil || !reflect.DeepEqual(info.Imports, []string{"::p::x", "::p::y"}) {
		t.Fatalf("imports = %#v", m["::c"])
	}
}

func TestFileNamespacesImportRelativeQualified(t *testing.T) {
	src := "namespace eval ::a {\n  namespace import sub::x\n}"
	m := FileNamespaces(src)
	info := m["::a"]
	if info == nil || !reflect.DeepEqual(info.Imports, []string{"::a::sub::x"}) {
		t.Fatalf("imports = %#v", m["::a"])
	}
}
