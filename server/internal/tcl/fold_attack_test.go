package tcl

// Attack tests for fold.go — written to break the byte-offset math and
// frame-threading assumptions.

import (
	"strings"
	"testing"
)

// ---- helpers ----------------------------------------------------------------

// requireBrace asserts that src[off] == '{' or '}' (as named) and that folds
// contains a FoldRange where that field equals off. Returns the matching fold
// (or calls t.Fatalf).
func requireOpen(t *testing.T, src string, folds []FoldRange, off int) FoldRange {
	t.Helper()
	if off < 0 || off >= len(src) {
		t.Fatalf("test bug: open offset %d out of range for src len %d", off, len(src))
	}
	if src[off] != '{' {
		t.Fatalf("test bug: src[%d] = %q, expected '{'", off, src[off])
	}
	for _, f := range folds {
		if f.Open == off {
			return f
		}
	}
	t.Fatalf("no fold with Open=%d in %+v\n  src=%q", off, folds, src)
	panic("unreachable")
}

func requireClose(t *testing.T, src string, folds []FoldRange, off int) FoldRange {
	t.Helper()
	if off < 0 || off >= len(src) {
		t.Fatalf("test bug: close offset %d out of range for src len %d", off, len(src))
	}
	if src[off] != '}' {
		t.Fatalf("test bug: src[%d] = %q, expected '}'", off, src[off])
	}
	for _, f := range folds {
		if f.Close == off {
			return f
		}
	}
	t.Fatalf("no fold with Close=%d in %+v\n  src=%q", off, folds, src)
	panic("unreachable")
}

// firstByte returns the index of the first occurrence of b in s after start.
func firstByteAfter(s string, b byte, start int) int {
	for i := start; i < len(s); i++ {
		if s[i] == b {
			return i
		}
	}
	return -1
}

// assertAllOpenAreOpenBraces verifies every FoldRange.Open byte in src is '{'.
// This is the core invariant of FileFolds.
func assertAllOpenAreOpenBraces(t *testing.T, src string, folds []FoldRange) {
	t.Helper()
	for _, f := range folds {
		if f.Open < 0 || f.Open >= len(src) {
			t.Errorf("FoldRange.Open=%d out of bounds (src len %d)", f.Open, len(src))
			continue
		}
		if src[f.Open] != '{' {
			t.Errorf("FoldRange.Open=%d -> %q, expected '{'", f.Open, src[f.Open])
		}
		if f.Close < 0 || f.Close >= len(src) {
			t.Errorf("FoldRange.Close=%d out of bounds (src len %d)", f.Close, len(src))
			continue
		}
		if src[f.Close] != '}' {
			t.Errorf("FoldRange.Close=%d -> %q, expected '}'", f.Close, src[f.Close])
		}
	}
}

// ---- offset math attacks ---------------------------------------------------

// The formula is: Open = b.Base - 1, Close = b.Base + len(b.Inner).
// For every returned fold, src[Open] must be '{' and src[Close] must be '}'.
// This test attacks the formula by checking a diverse set of commands.

func TestFileFolds_OpenIsAlwaysOpenBrace(t *testing.T) {
	cases := []struct {
		name string
		src  string
	}{
		{
			"proc simple",
			"proc p {} {\n  puts hi\n}\n",
		},
		{
			"proc multiline arglist",
			"proc p {\n  a\n  b\n} {\n  puts $a\n}\n",
		},
		{
			"proc qualified name",
			"proc ::ns::p {} {\n  puts hi\n}\n",
		},
		{
			"namespace eval",
			"namespace eval ::foo {\n  set x 1\n}\n",
		},
		{
			"itcl class with method",
			"itcl::class C {\n  method m {} {\n    puts hi\n  }\n}\n",
		},
		{
			"itcl class with destructor",
			"itcl::class C {\n  destructor {\n    puts bye\n  }\n}\n",
		},
		{
			"itcl class with constructor no init block",
			"itcl::class C {\n  constructor {args} {\n    puts hi\n  }\n}\n",
		},
		{
			"itcl class constructor with init block",
			"itcl::class C {\n  constructor {args} {Base::constructor $args} {\n    puts hi\n  }\n}\n",
		},
		{
			"if body",
			"proc p {} {\n  if {1} {\n    puts yes\n  }\n}\n",
		},
		{
			"if else",
			"proc p {} {\n  if {1} {\n    puts yes\n  } else {\n    puts no\n  }\n}\n",
		},
		{
			"while body",
			"proc p {} {\n  while {1} {\n    puts loop\n  }\n}\n",
		},
		{
			"foreach body",
			"proc p {} {\n  foreach x {a b} {\n    puts $x\n  }\n}\n",
		},
		{
			"itcl::body external",
			"itcl::body ::C::m {args} {\n  puts body\n}\n",
		},
		{
			"decorated proc body not last word",
			"CACHE_PROC proc myfn {} {\n  puts hi\n} -ttl 60\n",
		},
		{
			"catch body",
			"proc p {} {\n  catch {\n    puts hi\n  }\n}\n",
		},
		{
			"try body",
			"proc p {} {\n  try {\n    puts hi\n  } on error {e} {\n    puts $e\n  } finally {\n    puts done\n  }\n}\n",
		},
		{
			"deeply nested proc in namespace",
			"namespace eval ::a {\n  namespace eval b {\n    proc p {} {\n      if {1} {\n        puts deep\n      }\n    }\n  }\n}\n",
		},
		{
			"access modifier method",
			"itcl::class C {\n  public method m {} {\n    puts hi\n  }\n}\n",
		},
		{
			"private destructor",
			"itcl::class C {\n  private destructor {\n    puts bye\n  }\n}\n",
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			folds := FileFolds(tc.src)
			if len(folds) == 0 {
				t.Fatalf("no folds produced for %q", tc.src)
			}
			assertAllOpenAreOpenBraces(t, tc.src, folds)
		})
	}
}

// Verify that Open < Close for every fold — a fold where Open >= Close is a sign
// of inverted or wrong offsets.
func TestFileFolds_OpenAlwaysLessThanClose(t *testing.T) {
	cases := []string{
		"proc p {} {\n  puts hi\n}\n",
		"itcl::class C {\n  method m {} {\n    puts hi\n  }\n}\n",
		"proc p {} {\n  if {1} {\n    puts yes\n  } else {\n    puts no\n  }\n}\n",
		"proc p {} {\n  for {set i 0} {$i<10} {incr i} {\n    puts $i\n  }\n}\n",
	}
	for _, src := range cases {
		folds := FileFolds(src)
		for _, f := range folds {
			if f.Open >= f.Close {
				t.Errorf("src=%q: fold Open=%d >= Close=%d", src, f.Open, f.Close)
			}
		}
	}
}

// Attack: proc body has no preceding single-space — multi-space/tab-separated.
// The scanner skips all whitespace between words, so the body word's Start is
// wherever the '{' appears. b.Base - 1 must still land exactly on '{'.
func TestFileFolds_ProcBodyWithTabBeforeBrace(t *testing.T) {
	// Tab between arglist and body.
	src := "proc p {}\t{\n  puts hi\n}\n"
	folds := FileFolds(src)
	// Find the '{' of the body (second '{', after "proc p {}")
	bodyOpen := strings.Index(src, "{\n  puts")
	if bodyOpen < 0 {
		t.Fatalf("test bug: couldn't find body brace in %q", src)
	}
	assertAllOpenAreOpenBraces(t, src, folds)
	f := requireOpen(t, src, folds, bodyOpen)
	if src[f.Close] != '}' {
		t.Fatalf("Close byte %d = %q, want '}'", f.Close, src[f.Close])
	}
}

// BUG: CRLF line endings cause the proc body fold to be silently dropped.
//
// Root cause: scanBare does not treat '\r' as whitespace. In "proc p {} {\r\n
// ...}\r\n", the scanner produces these words for the proc command:
//
//	w[0]="proc"  w[1]="p"  w[2]="{}"  w[3]="{\r\n...\r\n}"  w[4]="\r"
//
// The '\r' before the final '\n' is consumed as a bare word, making the
// command have 5 words. childBodies for proc checks w[len(w)-1].Kind==
// WordBraced; w[4] is WordBare, so the check fails and NO fold is emitted.
//
// FileDefs is unaffected because it only inspects w[0] and w[1].
//
// Expected: at least one fold with Open pointing to src[10] == '{'.
// Actual:   zero folds.
func TestFileFolds_CRLF_ProcBodyDroppedBug(t *testing.T) {
	// "proc p {} {\r\n  puts hi\r\n}\r\n"
	//  offsets:     10^             24^
	src := "proc p {} {\r\n  puts hi\r\n}\r\n"
	bodyOpen := 10 // the '{' at position 10
	if src[bodyOpen] != '{' {
		t.Fatalf("test bug: src[%d]=%q, expected '{'", bodyOpen, src[bodyOpen])
	}
	folds := FileFolds(src)
	for _, f := range folds {
		if f.Open == bodyOpen {
			return // found the fold: bug is fixed
		}
	}
	// If we get here, the fold was not found — this is the bug.
	t.Fatalf("CRLF proc body fold missing: expected fold with Open=%d ('{' at src[%d]); got folds=%+v\n"+
		"Root cause: scanner emits '\\r' after '}' as a bare word, making the proc\n"+
		"command have 5 words; childBodies checks w[len(w)-1].Kind==WordBraced\n"+
		"but w[4]='\\r' is WordBare, so the body fold is silently dropped.",
		bodyOpen, bodyOpen, folds)
}

// Broad CRLF check: any CRLF source must produce folds with valid Open/Close bytes.
func TestFileFolds_CRLF_OffsetValidity(t *testing.T) {
	src := "proc p {} {\r\n  puts hi\r\n}\r\n"
	folds := FileFolds(src)
	assertAllOpenAreOpenBraces(t, src, folds)
}

// Attack: no trailing newline — the '}' is the last byte of the source.
// Close must equal len(src)-1.
func TestFileFolds_ClosingBraceIsFinalByte(t *testing.T) {
	// No trailing newline: "}" is the very last byte.
	src := "proc p {} {\n  puts hi\n}"
	folds := FileFolds(src)
	if len(folds) == 0 {
		t.Fatal("no folds produced")
	}
	assertAllOpenAreOpenBraces(t, src, folds)
	last := len(src) - 1
	if src[last] != '}' {
		t.Fatalf("test bug: last byte = %q", src[last])
	}
	found := false
	for _, f := range folds {
		if f.Close == last {
			found = true
		}
	}
	if !found {
		t.Fatalf("no fold with Close=%d (last byte); folds=%+v", last, folds)
	}
}

// Attack: empty source — must return nil/empty without panic.
func TestFileFolds_EmptySource(t *testing.T) {
	folds := FileFolds("")
	if len(folds) != 0 {
		t.Fatalf("empty source produced folds: %+v", folds)
	}
}

// Attack: source with only whitespace.
func TestFileFolds_WhitespaceOnly(t *testing.T) {
	folds := FileFolds("   \n\t\n   ")
	if len(folds) != 0 {
		t.Fatalf("whitespace-only source produced folds: %+v", folds)
	}
}

// Attack: source with only comments.
func TestFileFolds_CommentOnly(t *testing.T) {
	folds := FileFolds("# This is a comment\n# Another comment\n")
	if len(folds) != 0 {
		t.Fatalf("comment-only source produced folds: %+v", folds)
	}
}

// BUG: Unterminated brace — the scanner is tolerant and produces a one-byte
// braced word "{"  for an unclosed body. bracedInner's fallback path fires
// (len < 2) and returns base+w.Start (not base+w.Start+1), so b.Base is off
// by one. The fold formula Open=b.Base-1 then lands on the byte BEFORE '{',
// and Close=b.Base+len("") lands on '{' itself. Both are wrong.
//
// Repro: "proc p {} {" — w[3]="{" (start=10), bracedInner fallback gives
// b.Base=10, Open=9 (a space), Close=10 (the '{').
//
// The correct behaviour for malformed input is debatable (nil folds, or
// Open=10/Close=10), but emitting a fold whose Open byte is not '{' is
// clearly wrong and could cause an index-out-of-bounds or panic in callers
// that blindly dereference the offset.
func TestFileFolds_UnbalancedBrace_OffsetsBug(t *testing.T) {
	// "proc p {} {" — body brace at offset 10, unterminated.
	src := "proc p {} {"
	folds := FileFolds(src)
	// Whatever folds are produced, no Open byte may point to a non-'{' and no
	// Close byte may point to a non-'}'.
	for _, f := range folds {
		if f.Open < 0 || f.Open >= len(src) {
			t.Errorf("Open=%d out of bounds", f.Open)
			continue
		}
		if src[f.Open] != '{' {
			t.Errorf("Open=%d -> %q, want '{'; src=%q", f.Open, src[f.Open], src)
		}
		// For unterminated input there is no '}', so Close legitimately points at
		// end-of-buffer (a valid LSP offset that buildFoldingRanges collapses). A
		// Close that lands inside the source, however, must be the matching '}'.
		if f.Close < 0 || f.Close > len(src) {
			t.Errorf("Close=%d out of range (len=%d)", f.Close, len(src))
			continue
		}
		if f.Close < len(src) && src[f.Close] != '}' {
			t.Errorf("Close=%d -> %q, want '}'; src=%q", f.Close, src[f.Close], src)
		}
	}
}

// Same bug, nested: "proc p {} {\n  if {1} {" — the outer proc body brace at
// offset 10 is the only well-formed braced word (it contains the if command).
// The if body brace at offset 21 is unterminated. FileFolds emits one fold
// (for the outer proc body, which IS terminated because it contains the `if`
// as inner content — actually in this case the proc body word "{\n  if {1} {"
// is the full word the scanner produces for the terminated outer brace that
// encloses the nested unterminated one... let's check the actual scan).
// Actually here the outer { at offset 10 IS unterminated too — the scanner
// scans until EOF with depth>0. So the same off-by-one applies.
func TestFileFolds_UnbalancedBrace_NestedOffsetsBug(t *testing.T) {
	cases := []string{
		"proc p {} {",
		"namespace eval ::foo {",
	}
	for _, src := range cases {
		folds := FileFolds(src)
		for _, f := range folds {
			if f.Open >= 0 && f.Open < len(src) && src[f.Open] != '{' {
				t.Errorf("src=%q: Open=%d -> %q, want '{'", src, f.Open, src[f.Open])
			}
			if f.Close >= 0 && f.Close < len(src) && src[f.Close] != '}' {
				t.Errorf("src=%q: Close=%d -> %q, want '}'", src, f.Close, src[f.Close])
			}
		}
	}
}

// Attack: deeply nested braces (100+ levels). Must not stack-overflow and
// must produce the correct count of folds.
func TestFileFolds_DeeplyNested(t *testing.T) {
	// Build: proc p {} { if {1} { if {1} { ... } } }
	// 50 levels of nested if bodies inside a proc.
	const depth = 50
	var b strings.Builder
	b.WriteString("proc p {} {\n")
	for i := 0; i < depth; i++ {
		b.WriteString(strings.Repeat("  ", i+1))
		b.WriteString("if {1} {\n")
	}
	for i := depth - 1; i >= 0; i-- {
		b.WriteString(strings.Repeat("  ", i+1))
		b.WriteString("}\n")
	}
	b.WriteString("}\n")
	src := b.String()

	folds := FileFolds(src)
	// Expect: 1 proc body + depth if bodies = depth+1 total.
	want := depth + 1
	if len(folds) != want {
		t.Fatalf("deeply nested: want %d folds, got %d\nfolds=%+v", want, len(folds), folds)
	}
	assertAllOpenAreOpenBraces(t, src, folds)
}

// ---- frame threading attacks ------------------------------------------------

// Attack: method defined with access modifier inside class body.
// childBodies uses memberWords to strip the modifier; if it mis-threads
// the frame or skips the body, the fold is missing.
func TestFileFolds_AccessModifierMethod(t *testing.T) {
	for _, modifier := range []string{"public", "protected", "private"} {
		src := "itcl::class C {\n  " + modifier + " method m {} {\n    puts hi\n  }\n}\n"
		folds := FileFolds(src)
		assertAllOpenAreOpenBraces(t, src, folds)
		// Locate the method body '{' (the '{' after "method m {} " inside class body).
		methodBodyOpen := strings.LastIndex(src, "{\n    puts")
		if methodBodyOpen < 0 {
			t.Fatalf("test bug: can't locate method body in %q", src)
		}
		requireOpen(t, src, folds, methodBodyOpen)
	}
}

// Attack: destructor body — minimum 2 words (destructor + body). Must fold.
func TestFileFolds_DestructorBody(t *testing.T) {
	src := "itcl::class C {\n  destructor {\n    cleanup\n  }\n}\n"
	folds := FileFolds(src)
	assertAllOpenAreOpenBraces(t, src, folds)
	// Locate destructor body open brace
	dOpen := strings.Index(src, "{\n    cleanup")
	if dOpen < 0 {
		t.Fatalf("test bug: can't locate destructor body in %q", src)
	}
	requireOpen(t, src, folds, dOpen)
}

// Attack: constructor with init block — both the init block AND the body
// should produce folds, with correct Open/Close bytes.
func TestFileFolds_ConstructorWithInitBlock(t *testing.T) {
	// "constructor {args} {Base::constructor $args} {\n  body\n}"
	src := "itcl::class D {\n  constructor {a} {Base::constructor $a} {\n    set _a $a\n  }\n}\n"
	folds := FileFolds(src)
	assertAllOpenAreOpenBraces(t, src, folds)

	// Find the init block '{' — the '{' before "Base::constructor"
	initOpen := strings.Index(src, "{Base::constructor")
	if initOpen < 0 {
		t.Fatalf("test bug: can't locate init block in %q", src)
	}
	// Find the body '{' — the '{' before "set _a"
	bodyOpen := strings.Index(src, "{\n    set _a")
	if bodyOpen < 0 {
		t.Fatalf("test bug: can't locate constructor body in %q", src)
	}

	requireOpen(t, src, folds, initOpen)
	requireOpen(t, src, folds, bodyOpen)
}

// Attack: signature-only method (forward declaration, no body). The trailing
// braced word is the parameter list — it must NOT be folded as a body.
func TestFileFolds_SignatureOnlyMethodNotFolded(t *testing.T) {
	// "method m {a b}" — only 3 words (method + name + args), no body word.
	// minMemberBodyWords returns 4 for method, so childBodies returns nil.
	src := "itcl::class C {\n  method m {a b}\n}\n"
	folds := FileFolds(src)

	// The args word '{a b}' must not appear as the Open of any fold.
	argsOpen := strings.Index(src, "{a b}")
	if argsOpen < 0 {
		t.Fatalf("test bug: can't locate args word in %q", src)
	}
	for _, f := range folds {
		if f.Open == argsOpen {
			t.Fatalf("parameter list '{a b}' at offset %d was incorrectly folded as body; folds=%+v", argsOpen, folds)
		}
	}
}

// Attack: itcl::body external method body — class is derived from the
// qualified name. Body must fold with correct offsets.
func TestFileFolds_ItclBodyExternal(t *testing.T) {
	src := "itcl::body ::C::method {args} {\n  puts external\n}\n"
	folds := FileFolds(src)
	assertAllOpenAreOpenBraces(t, src, folds)
	bodyOpen := strings.Index(src, "{\n  puts external")
	if bodyOpen < 0 {
		t.Fatalf("test bug: can't locate body in %q", src)
	}
	requireOpen(t, src, folds, bodyOpen)
}

// Attack: itcl::body with no "::" separator in name (invalid; childBodies
// should return nil and FileFolds must not panic).
func TestFileFolds_ItclBodyNoColons_NoPanic(t *testing.T) {
	src := "itcl::body method {args} {\n  puts hi\n}\n"
	folds := FileFolds(src) // must not panic
	_ = folds
}

// Attack: nested namespace inside class body (unusual but syntactically
// possible). childBodies at FrameClass should handle this via the namespace
// case.  If the class frame processing short-circuits before checking namespace,
// the inner namespace body would be missed.
func TestFileFolds_NamespaceInsideClassBody(t *testing.T) {
	// In real Itcl a namespace inside a class body is unusual but syntactically
	// parseable as a command. childBodies checks `namespace eval` BEFORE the
	// FrameClass method cases, so it should fire regardless.
	src := "itcl::class C {\n  namespace eval ::helper {\n    proc p {} {\n      puts hi\n    }\n  }\n}\n"
	folds := FileFolds(src)
	assertAllOpenAreOpenBraces(t, src, folds)
	// The proc body inside the namespace inside the class must be present.
	procBodyOpen := strings.Index(src, "{\n      puts hi")
	if procBodyOpen < 0 {
		t.Fatalf("test bug: can't locate proc body in %q", src)
	}
	requireOpen(t, src, folds, procBodyOpen)
}

// ---- control-flow body attacks ----------------------------------------------

// Attack: for command — three script bodies at indices 1 (init), 3 (next),
// 4 (body). All three must fold with Open pointing to '{'.
func TestFileFolds_ForAllThreeBodies(t *testing.T) {
	src := "proc p {} {\n  for {set i 0} {$i < 10} {incr i} {\n    puts $i\n  }\n}\n"
	folds := FileFolds(src)
	assertAllOpenAreOpenBraces(t, src, folds)

	// Locate the three '{' of the for command (within the proc body):
	// {set i 0}, {incr i}, and the multi-line {body}.
	inner := src[len("proc p {} {\n"):]
	base := len("proc p {} {\n")

	initOff := base + strings.Index(inner, "{set i 0}")
	nextOff := base + strings.Index(inner, "{incr i}")
	bodyOff := base + strings.Index(inner, "{\n    puts $i")

	// All three should appear as Open in folds.
	requireOpen(t, src, folds, initOff)
	requireOpen(t, src, folds, nextOff)
	requireOpen(t, src, folds, bodyOff)
}

// Attack: try/on/trap/finally — all handler bodies must fold.
func TestFileFolds_TryAllHandlers(t *testing.T) {
	src := "proc p {} {\n  try {\n    risky\n  } on ok {r} {\n    puts ok\n  } on error {e} {\n    puts err\n  } finally {\n    puts done\n  }\n}\n"
	folds := FileFolds(src)
	assertAllOpenAreOpenBraces(t, src, folds)

	// try body, on-ok body, on-error body, finally body — all must fold.
	for _, marker := range []string{
		"{\n    risky",
		"{\n    puts ok",
		"{\n    puts err",
		"{\n    puts done",
	} {
		off := strings.Index(src, marker)
		if off < 0 {
			t.Fatalf("test bug: can't find %q in src", marker)
		}
		requireOpen(t, src, folds, off)
	}
}

// Attack: if/elseif/else bodies — condition expressions must NOT fold, but
// all the then/else bodies must.
func TestFileFolds_IfElseifElse(t *testing.T) {
	src := "proc p {} {\n  if {$a} {\n    puts a\n  } elseif {$b} {\n    puts b\n  } else {\n    puts c\n  }\n}\n"
	folds := FileFolds(src)
	assertAllOpenAreOpenBraces(t, src, folds)

	// The condition '{$a}' and '{$b}' should NOT appear as fold Open values.
	condA := strings.Index(src, "{$a}")
	condB := strings.Index(src, "{$b}")
	for _, f := range folds {
		if f.Open == condA {
			t.Errorf("condition {$a} at offset %d incorrectly folded", condA)
		}
		if f.Open == condB {
			t.Errorf("condition {$b} at offset %d incorrectly folded", condB)
		}
	}

	// All three then/else bodies must fold.
	for _, marker := range []string{"{\n    puts a", "{\n    puts b", "{\n    puts c"} {
		off := strings.Index(src, marker)
		if off < 0 {
			t.Fatalf("test bug: can't find %q in src", marker)
		}
		requireOpen(t, src, folds, off)
	}
}

// Attack: decorated proc where body is not the last word.
// The fold must point to the actual body '{', not some other word.
func TestFileFolds_DecoratedProcBodyNotLastWord(t *testing.T) {
	src := "CACHE_PROC proc myfn {a b} {\n  puts $a\n} -ttl 60\n"
	folds := FileFolds(src)
	assertAllOpenAreOpenBraces(t, src, folds)

	bodyOpen := strings.Index(src, "{\n  puts $a")
	if bodyOpen < 0 {
		t.Fatalf("test bug: can't locate body in %q", src)
	}
	requireOpen(t, src, folds, bodyOpen)

	// The word '-ttl' is a bare word; '60' is bare. Neither should be folded.
	// There should be no fold with Close pointing at '6' or '-'.
	for _, f := range folds {
		if f.Open == bodyOpen {
			// The matching close should be the '}' before " -ttl 60".
			closeOff := strings.Index(src, "} -ttl")
			if closeOff < 0 {
				t.Fatalf("test bug: can't locate '} -ttl' in %q", src)
			}
			if f.Close != closeOff {
				t.Errorf("decorated proc: body fold Close=%d want %d; src[Close]=%q",
					f.Close, closeOff, src[f.Close])
			}
		}
	}
}

// Attack: a braced word in a non-command position (e.g. data in set) must NOT
// be folded. Only childBodies's explicit classification yields bodies.
func TestFileFolds_DataBraceNotFolded(t *testing.T) {
	// `set x {a b c}` — the braced word is data, not a script body.
	src := "proc p {} {\n  set x {a b c}\n}\n"
	folds := FileFolds(src)

	dataOpen := strings.Index(src, "{a b c}")
	if dataOpen < 0 {
		t.Fatalf("test bug: can't find data brace in %q", src)
	}
	for _, f := range folds {
		if f.Open == dataOpen {
			t.Errorf("data brace '{a b c}' at offset %d incorrectly folded as body", dataOpen)
		}
	}
}

// ---- duplicate / count attacks ---------------------------------------------

// Attack: make sure no fold is emitted twice for the same Open offset.
// A double-count would appear if childBodies and FileFolds both walked the
// same body.
func TestFileFolds_NoDuplicates(t *testing.T) {
	src := "proc p {} {\n  if {1} {\n    puts yes\n  }\n}\n"
	folds := FileFolds(src)
	seen := map[int]bool{}
	for _, f := range folds {
		if seen[f.Open] {
			t.Errorf("duplicate fold Open=%d in %+v", f.Open, folds)
		}
		seen[f.Open] = true
	}
}

// Attack: multiple procs in the same file. Each should produce exactly one
// top-level fold, not zero or more.
func TestFileFolds_MultipleProcs(t *testing.T) {
	src := "proc a {} {\n  puts a\n}\nproc b {} {\n  puts b\n}\nproc c {} {\n  puts c\n}\n"
	folds := FileFolds(src)
	assertAllOpenAreOpenBraces(t, src, folds)
	if len(folds) < 3 {
		t.Fatalf("want at least 3 folds for 3 procs, got %d: %+v", len(folds), folds)
	}
}

// ---- unicode / escape attacks -----------------------------------------------

// Attack: unicode content inside a body. The byte offsets must remain correct
// (UTF-8 multibyte sequences should not shift '{' or '}' positions).
func TestFileFolds_UnicodeInBody(t *testing.T) {
	// Emoji: 4 bytes each. Ensure { and } offsets are unaffected.
	src := "proc p {} {\n  puts \"\U0001F600\"\n}\n"
	folds := FileFolds(src)
	assertAllOpenAreOpenBraces(t, src, folds)
	bodyOpen := strings.Index(src, "{\n  puts")
	if bodyOpen < 0 {
		t.Fatalf("test bug: can't find body in %q", src)
	}
	requireOpen(t, src, folds, bodyOpen)
}

// Attack: backslash-escaped brace inside body content (\{ \}). The scanner's
// scanBraced skips these, so the body word spans correctly. Fold offsets
// must still be the REAL outer { and }.
func TestFileFolds_BackslashBracesInBody(t *testing.T) {
	src := "proc p {} {\n  set x \\{not a brace\\}\n}\n"
	folds := FileFolds(src)
	assertAllOpenAreOpenBraces(t, src, folds)
	bodyOpen := strings.Index(src, "{\n  set x")
	if bodyOpen < 0 {
		t.Fatalf("test bug: can't find body in %q", src)
	}
	requireOpen(t, src, folds, bodyOpen)
}

// Attack: body with nested braced data at multiple levels — the outer { and }
// must still be correctly identified.
func TestFileFolds_NestedDataBracesInBody(t *testing.T) {
	src := "proc p {} {\n  set x {a {b {c}} d}\n}\n"
	folds := FileFolds(src)
	assertAllOpenAreOpenBraces(t, src, folds)
	bodyOpen := strings.Index(src, "{\n  set x")
	requireOpen(t, src, folds, bodyOpen)

	// Data brace '{a {b {c}} d}' must NOT be an open of any fold.
	dataOff := strings.Index(src, "{a {b")
	if dataOff < 0 {
		t.Fatal("test bug: can't find data brace")
	}
	for _, f := range folds {
		if f.Open == dataOff {
			t.Errorf("data brace at offset %d incorrectly folded", dataOff)
		}
	}
}

// ---- RVT-translation attacks (via source.Folds indirectly) ------------------
// These call FileFolds directly on the stitched script to verify that the
// virtual offsets produced are valid positions in the stitched script —
// i.e. that doc.Script[f.Open] == '{' and doc.Script[f.Close] == '}'.

func TestFileFolds_VirtualOffsetsAreValidInStitchedScript(t *testing.T) {
	// FileFolds on a hand-constructed stitched script (mirrors what Extract
	// produces for a proc inside a <? ?> block). All fold Open/Close bytes
	// must be { and } in the stitched string.
	stitched := "namespace eval ::request {\nproc p {} {\n  puts hi\n}\n}\n"
	folds := FileFolds(stitched)
	assertAllOpenAreOpenBraces(t, stitched, folds)
}
