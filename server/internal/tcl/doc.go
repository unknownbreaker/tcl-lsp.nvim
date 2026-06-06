// Package tcl provides a tolerant, hand-written tokenizer and structural parser
// for TCL source, scoped to the needs of goto-definition and goto-reference.
//
// The tokenizer never panics on malformed input: unterminated braces, quotes,
// and brackets are scanned to end-of-input rather than treated as errors, so the
// parser can still produce best-effort results for code that is mid-edit.
package tcl
