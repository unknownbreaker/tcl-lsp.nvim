package tcl

import "testing"

// foldsContain reports whether folds includes a span whose Open/Close land on the
// given bytes, and that those bytes are actually '{' and '}' in src.
func foldAt(t *testing.T, src string, folds []FoldRange, open, close int) bool {
	t.Helper()
	if src[open] != '{' || src[close] != '}' {
		t.Fatalf("test bug: src[%d]=%q src[%d]=%q, expected braces", open, src[open], close, src[close])
	}
	for _, f := range folds {
		if f.Open == open && f.Close == close {
			return true
		}
	}
	return false
}

// A proc body folds, with Open at its '{' and Close at its '}'.
func TestFileFolds_ProcBody(t *testing.T) {
	src := "proc greet {name} {\n  puts hi\n  puts bye\n}\n"
	open := len("proc greet {name} ") // the body '{'
	close := len(src) - 2             // the final '}' (before trailing \n)
	folds := FileFolds(src)
	if !foldAt(t, src, folds, open, close) {
		t.Fatalf("proc body not folded; got %+v", folds)
	}
}

// Nested control-flow bodies fold too, at any depth.
func TestFileFolds_Nested(t *testing.T) {
	src := "proc p {} {\n  if {$x} {\n    puts a\n  }\n}\n"
	folds := FileFolds(src)
	// the proc body and the if body should both be present
	ifOpen := -1
	for i := 0; i+1 < len(src); i++ {
		if src[i] == '}' && src[i+1] == ' ' { // close of {$x}, then ' {'
			ifOpen = i + 2
			break
		}
	}
	if ifOpen < 0 || src[ifOpen] != '{' {
		t.Fatalf("could not locate if body brace in %q", src)
	}
	var foundProc, foundIf bool
	for _, f := range folds {
		if f.Open == len("proc p {} ") {
			foundProc = true
		}
		if f.Open == ifOpen {
			foundIf = true
		}
	}
	if !foundProc || !foundIf {
		t.Fatalf("nested folds missing: proc=%v if=%v folds=%+v", foundProc, foundIf, folds)
	}
}

// itcl method bodies fold — childBodies only yields these when the class frame is
// threaded, so this guards the frame-threading in FileFolds.
func TestFileFolds_ItclMethodBody(t *testing.T) {
	src := "itcl::class C {\n  method m {} {\n    puts inside\n  }\n}\n"
	folds := FileFolds(src)
	// locate the method body '{' (after "method m {} ")
	idx := -1
	for i := 0; i+1 < len(src); i++ {
		if src[i] == '}' && src[i+1] == ' ' { // close of the empty arg list {}
			idx = i + 2
			break
		}
	}
	if idx < 0 || src[idx] != '{' {
		t.Fatalf("could not locate method body brace in %q", src)
	}
	for _, f := range folds {
		if f.Open == idx {
			return
		}
	}
	t.Fatalf("itcl method body not folded; got %+v", folds)
}

// An empty/single-line body still yields a span (caller drops single-line ones).
func TestFileFolds_EmptyBody(t *testing.T) {
	src := "proc p {} {}\n"
	folds := FileFolds(src)
	open := len("proc p {} ")
	if len(folds) == 0 || folds[0].Open != open || folds[0].Close != open+1 {
		t.Fatalf("empty body span wrong: %+v", folds)
	}
}
