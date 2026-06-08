package lsp

import (
	"unicode/utf16"
	"unicode/utf8"
)

// ByteOffset converts an LSP (line, character) position — where character counts
// UTF-16 code units — to a byte offset in src. Positions past the end of a line
// clamp to the line end; lines past the end clamp to len(src).
func ByteOffset(src string, line, character int) int {
	off := 0
	for curLine := 0; off < len(src) && curLine < line; off++ {
		if src[off] == '\n' {
			curLine++
		}
	}
	u16 := 0
	for off < len(src) && src[off] != '\n' && u16 < character {
		r, size := utf8.DecodeRuneInString(src[off:])
		u16 += utf16.RuneLen(r)
		off += size
	}
	return off
}

// LSPPosition converts a byte offset in src to an LSP (line, character) position,
// where character counts UTF-16 code units. Offsets past len(src) clamp to it.
// A mid-rune offset is treated as pointing just past that rune; pass only rune-boundary offsets.
func LSPPosition(src string, offset int) (line, character int) {
	if offset > len(src) {
		offset = len(src)
	}
	lineStart := 0
	for i := 0; i < offset; i++ {
		if src[i] == '\n' {
			line++
			lineStart = i + 1
		}
	}
	for i := lineStart; i < offset; {
		r, size := utf8.DecodeRuneInString(src[i:])
		character += utf16.RuneLen(r)
		i += size
	}
	return line, character
}
