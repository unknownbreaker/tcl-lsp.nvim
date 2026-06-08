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
