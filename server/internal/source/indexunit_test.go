package source

import (
	"reflect"
	"testing"
)

// TestIndexUnitMatchesIndividual verifies that the bundled single-parse path
// (IndexUnit) produces exactly what the four individual functions produce, for
// both .tcl and the offset-translated .rvt path. This is what lets index.IndexFile
// call IndexUnit once instead of Defs/Refs/Namespaces/Classes four times.
func TestIndexUnitMatchesIndividual(t *testing.T) {
	cases := []struct {
		name, path, content string
	}{
		{
			name:    "tcl",
			path:    "a.tcl",
			content: "namespace eval ::app {\n  namespace path ::other\n  proc run {x} { compute $x }\n}\nitcl::class ::C {\n  inherit ::B\n  variable n 0\n  method m {} { go }\n}",
		},
		{
			name:    "rvt",
			path:    "p.rvt",
			content: "<? proc render {x} { draw $x } ?>\n<b><?= $title ?></b>\n<? namespace eval ::app { namespace import ::other::* } ?>",
		},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			u := IndexUnit(tc.path, tc.content)
			if got, want := u.Defs, Defs(tc.path, tc.content); !reflect.DeepEqual(got, want) {
				t.Errorf("Defs mismatch\n got=%#v\nwant=%#v", got, want)
			}
			if got, want := u.Refs, Refs(tc.path, tc.content); !reflect.DeepEqual(got, want) {
				t.Errorf("Refs mismatch\n got=%#v\nwant=%#v", got, want)
			}
			if got, want := u.Namespaces, Namespaces(tc.path, tc.content); !reflect.DeepEqual(got, want) {
				t.Errorf("Namespaces mismatch\n got=%#v\nwant=%#v", got, want)
			}
			if got, want := u.Classes, Classes(tc.path, tc.content); !reflect.DeepEqual(got, want) {
				t.Errorf("Classes mismatch\n got=%#v\nwant=%#v", got, want)
			}
		})
	}
}
