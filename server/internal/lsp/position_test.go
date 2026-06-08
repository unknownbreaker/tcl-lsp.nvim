package lsp

import "testing"

func TestByteOffsetAndPositionASCII(t *testing.T) {
	src := "set x 1\nputs $x"
	// Start of line 1 ("puts") is byte 8.
	if got := ByteOffset(src, 1, 0); got != 8 {
		t.Fatalf("ByteOffset(1,0) = %d, want 8", got)
	}
	line, ch := LSPPosition(src, 8)
	if line != 1 || ch != 0 {
		t.Fatalf("LSPPosition(8) = (%d,%d), want (1,0)", line, ch)
	}
	// `$x` is at byte 13 (line 1, char 5).
	if got := ByteOffset(src, 1, 5); got != 13 {
		t.Fatalf("ByteOffset(1,5) = %d, want 13", got)
	}
}

func TestPositionUTF16Multibyte(t *testing.T) {
	// "😀" (U+1F600) is 4 UTF-8 bytes and 2 UTF-16 code units.
	src := "x😀y" // x=byte0, 😀=bytes1..4, y=byte5
	line, ch := LSPPosition(src, 5)
	if line != 0 || ch != 3 { // 1 (x) + 2 (😀) = 3 UTF-16 units
		t.Fatalf("LSPPosition(5) = (%d,%d), want (0,3)", line, ch)
	}
	if got := ByteOffset(src, 0, 3); got != 5 {
		t.Fatalf("ByteOffset(0,3) = %d, want 5", got)
	}
	// "é" (U+00E9) is 2 UTF-8 bytes and 1 UTF-16 unit.
	src2 := "é!" // é=bytes0..1, !=byte2
	if got := ByteOffset(src2, 0, 1); got != 2 {
		t.Fatalf("ByteOffset on é: %d, want 2", got)
	}
}

func TestByteOffsetClampsBeyondLine(t *testing.T) {
	src := "ab\ncd"
	// A character past the end of the line clamps to the line end (byte 2).
	if got := ByteOffset(src, 0, 99); got != 2 {
		t.Fatalf("ByteOffset(0,99) = %d, want 2", got)
	}
	// A line past the end clamps to len(src).
	if got := ByteOffset(src, 99, 0); got != len(src) {
		t.Fatalf("ByteOffset(99,0) = %d, want %d", got, len(src))
	}
}
