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

func TestFileNamespacesPathList(t *testing.T) {
	src := "namespace eval ::u {\n  namespace path {::lib ::other}\n}"
	m := FileNamespaces(src)
	info := m["::u"]
	if info == nil || !reflect.DeepEqual(info.Path, []string{"::lib", "::other"}) {
		t.Fatalf("path = %#v", m["::u"])
	}
}

func TestFileNamespacesPathSingleRelative(t *testing.T) {
	src := "namespace eval ::a {\n  namespace path b\n}"
	m := FileNamespaces(src)
	info := m["::a"]
	if info == nil || !reflect.DeepEqual(info.Path, []string{"::a::b"}) {
		t.Fatalf("path = %#v", m["::a"])
	}
}

func TestFileNamespacesPathLastWins(t *testing.T) {
	src := "namespace eval ::a {\n  namespace path ::x\n  namespace path ::y\n}"
	m := FileNamespaces(src)
	info := m["::a"]
	if info == nil || !reflect.DeepEqual(info.Path, []string{"::y"}) {
		t.Fatalf("path (last wins) = %#v", m["::a"])
	}
}

func TestFileNamespacesPathEmpty(t *testing.T) {
	// `namespace path {}` clears any previous path (last-wins with empty).
	src := "namespace eval ::a {\n  namespace path ::x\n  namespace path {}\n}"
	m := FileNamespaces(src)
	info := m["::a"]
	if info == nil || len(info.Path) != 0 {
		t.Fatalf("empty path should clear previous: %#v", m["::a"])
	}
}

func TestFileNamespacesExportNoclashFlagSkipped(t *testing.T) {
	m := FileNamespaces("namespace export -noclash foo bar*")
	if !reflect.DeepEqual(m["::"].Exports, []string{"foo", "bar*"}) {
		t.Fatalf("export flag skipping: %#v", m["::"])
	}
}

func TestFileNamespacesCombinedNested(t *testing.T) {
	src := "namespace eval ::a {\n" +
		"  namespace export api*\n" +
		"  namespace path {::lib}\n" +
		"  namespace eval b {\n" +
		"    namespace import ::p::tool\n" +
		"  }\n" +
		"}"
	m := FileNamespaces(src)

	a := m["::a"]
	if a == nil {
		t.Fatalf("no ::a in %#v", m)
	}
	if !reflect.DeepEqual(a.Exports, []string{"api*"}) {
		t.Fatalf("::a exports = %#v", a.Exports)
	}
	if !reflect.DeepEqual(a.Path, []string{"::lib"}) {
		t.Fatalf("::a path = %#v", a.Path)
	}

	b := m["::a::b"]
	if b == nil {
		t.Fatalf("no ::a::b in %#v", m)
	}
	if !reflect.DeepEqual(b.Imports, []string{"::p::tool"}) {
		t.Fatalf("::a::b imports = %#v", b.Imports)
	}
}
