# Array-element Resolution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve goto-definition and goto-references for Tcl array variables (`set arr(i)`, `$arr(k)`) — proc-local and namespace/global — by keying on the array base name.

**Architecture:** The use side (`$arr(i)` → base `arr`) and the resolver already work; the only change is the definition walker. A new `arrayBaseName` helper extracts the base name from a `name(index)` target, applied at the existing variable-definition emit sites (`FrameProc` `set`/`incr`/`append`/`lappend` → `DefLocal`; `FrameNamespace` `set` → `DefNamespaceVar`). Namespace array defs then match through the unchanged workspace index.

**Tech Stack:** Go, standard `testing`. Tests run with `go -C server test ./internal/<pkg>/`.

## Global Constraints

- An array element access resolves to its **base variable** (`arr(i)` → `arr`), keyed `(file, scope, "arr")` for a proc-local or by FQ name (e.g. `::app::arr`) through the index for a namespace/global var.
- `arrayBaseName`: the base is the text before the first `(`; it must be substitution-free (no `$`/`[` in the base); the index after `(` may contain anything (so `arr($i)` works). No `(` → the whole word (existing scalar behavior).
- goto-def returns the **first (lowest-offset) binding** (the declaration) — arrays inherit the scalar rule already implemented; do NOT re-implement it.
- **No resolver changes** and **no refactor** (e.g. do not extract a shared `localBindings` helper) — out of scope for this plan.
- `array set arr {…}` is **not** a binding. Namespace-frame `incr`/`append`/`lappend` are not definition sites (unchanged).
- Run tests with `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ...` (no `cd`). One command per Bash call — no `&&`/`;`/`|`.
- Commit messages: conventional commits; end with the `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` and `Claude-Session: …` trailers used throughout this repo.

---

## File Structure

- `server/internal/tcl/defs.go` — add `arrayBaseName`; rewrite the `set`/`incr`/`append`/`lappend` emit sites to use it (Task 1).
- `server/internal/tcl/defs_test.go` — def-emission unit tests (Task 1).
- `server/internal/resolve/resolve_test.go` — resolve-level array tests (Task 2).
- `server/internal/rvt/testdata/corpus/array_local.rvt` — `.rvt` fixture (Task 2).
- `server/internal/resolve/corpus_test.go` — `.rvt` golden (Task 2).

---

### Task 1: Base-name extraction in the definition walker

**Files:**
- Modify: `server/internal/tcl/defs.go` (add `arrayBaseName`; change the `FrameNamespace set`, `FrameProc set`, and `FrameProc incr/append/lappend` emit sites in `emitDefs`)
- Test: `server/internal/tcl/defs_test.go`

**Interfaces:**
- Consumes: `Word` (`.Kind`, `.Text`, `.Start`, `.End`), `isPlainName(w Word) bool`, `qualifyName(name, ns string) string`, `Definition` (with `Scope`), existing test helpers `defsNamed`/`findDef`. `defs.go` already imports `strings`.
- Produces: `arrayBaseName(w Word) (name string, start, end int, ok bool)` — `start`/`end` are parse-base-relative (callers add `base`).

- [ ] **Step 1: Write the failing tests**

Add to `server/internal/tcl/defs_test.go`:

```go
func TestFileDefsArrayElementLocals(t *testing.T) {
	src := "proc f {} {\n" +
		"  set arr(a) 0\n" +
		"  incr arr(b)\n" +
		"  append str(x) hi\n" +
		"  lappend items(k) v\n" +
		"  set dyn($i) 1\n" +
		"}"
	defs := FileDefs(src)
	for _, name := range []string{"arr", "str", "items", "dyn"} {
		ds := defsNamed(defs, name)
		if len(ds) == 0 {
			t.Fatalf("no def named %q; got %#v", name, defs)
		}
		d := ds[0]
		if d.Kind != DefLocal || d.Scope == 0 {
			t.Fatalf("%q: want DefLocal in nonzero scope, got %#v", name, d)
		}
		if src[d.NameStart:d.NameEnd] != name {
			t.Fatalf("%q: range slices %q, want the base name", name, src[d.NameStart:d.NameEnd])
		}
	}
	// The parenthesized form must NOT be emitted as a name.
	if d := findDef(defs, "arr(a)"); d != nil {
		t.Fatalf("should not emit parenthesized name arr(a): %#v", d)
	}
	// A plain scalar target is unaffected.
	if d := findDef(FileDefs("proc f {} {\n  set plain 1\n}"), "plain"); d == nil {
		t.Fatalf("scalar set should still emit a DefLocal named plain")
	}
}

func TestFileDefsArrayElementNamespaceVar(t *testing.T) {
	src := "namespace eval ::app {\n  set cfg(host) x\n}"
	defs := FileDefs(src)
	d := findDef(defs, "::app::cfg")
	if d == nil || d.Kind != DefNamespaceVar {
		t.Fatalf("want DefNamespaceVar ::app::cfg, got %#v", defs)
	}
	if src[d.NameStart:d.NameEnd] != "cfg" {
		t.Fatalf("range slices %q, want cfg", src[d.NameStart:d.NameEnd])
	}
	if findDef(defs, "::app::cfg(host)") != nil {
		t.Fatalf("should not emit ::app::cfg(host)")
	}
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/tcl/ -run 'TestFileDefsArrayElement' -v`
Expected: FAIL — `arr`/`str`/`items`/`dyn` not found (today `set arr(a)` emits `"arr(a)"`, `set dyn($i)` emits nothing); namespace test finds `::app::cfg(host)` not `::app::cfg`.

- [ ] **Step 3: Add the `arrayBaseName` helper**

In `server/internal/tcl/defs.go`, add (e.g. just below `isPlainName`):

```go
// arrayBaseName returns the variable name a definition target word binds, with a
// byte range relative to the parse base (callers add `base`). For an array
// element target like `arr(i)` or `arr($i)` it returns the base name `arr` and a
// range covering just `arr`; for a plain scalar target it returns the whole word.
// ok is false when the target is not a usable bare name (empty, a leading `(`, or
// a base containing a substitution). The index after `(` may be anything.
func arrayBaseName(w Word) (name string, start, end int, ok bool) {
	if w.Kind != WordBare || w.Text == "" {
		return "", 0, 0, false
	}
	p := strings.IndexByte(w.Text, '(')
	if p < 0 {
		if !isPlainName(w) {
			return "", 0, 0, false
		}
		return w.Text, w.Start, w.End, true
	}
	baseText := w.Text[:p]
	if baseText == "" {
		return "", 0, 0, false
	}
	for i := 0; i < len(baseText); i++ {
		if baseText[i] == '$' || baseText[i] == '[' {
			return "", 0, 0, false
		}
	}
	return baseText, w.Start, w.Start + p, true
}
```

- [ ] **Step 4: Rewrite the three emit sites in `emitDefs`**

Replace the `FrameNamespace set` block (currently gated on `isPlainName(w[1])`) with:

```go
	if isCmd(w, "set") && frame == FrameNamespace && len(w) >= 2 {
		if name, s, e, ok := arrayBaseName(w[1]); ok {
			*out = append(*out, Definition{
				Kind:      DefNamespaceVar,
				Name:      qualifyName(name, ns),
				Namespace: ns,
				NameStart: base + s,
				NameEnd:   base + e,
				Scope:     scope,
			})
		}
	}
```

Replace the `FrameProc set` block with:

```go
	if isCmd(w, "set") && frame == FrameProc && len(w) >= 2 {
		if name, s, e, ok := arrayBaseName(w[1]); ok {
			*out = append(*out, Definition{
				Kind: DefLocal, Name: name, Namespace: ns,
				NameStart: base + s, NameEnd: base + e, Scope: scope,
			})
		}
	}
```

Replace the `FrameProc incr/append/lappend` block with:

```go
	if frame == FrameProc && len(w) >= 2 {
		switch {
		case isCmd(w, "incr"), isCmd(w, "append"), isCmd(w, "lappend"):
			if name, s, e, ok := arrayBaseName(w[1]); ok {
				*out = append(*out, Definition{
					Kind: DefLocal, Name: name, Namespace: ns,
					NameStart: base + s, NameEnd: base + e, Scope: scope,
				})
			}
		}
	}
```

Leave the `variable`, `global`, `upvar`, `proc`, decorated-proc, and `emitLoopVarDefs` blocks unchanged.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/tcl/`
Expected: PASS — new tests green; all existing `tcl` tests still pass (scalar targets unchanged because `arrayBaseName` falls back to the whole word via `isPlainName`).

- [ ] **Step 6: Commit**

```
git add server/internal/tcl/defs.go server/internal/tcl/defs_test.go
git commit -m "feat(tcl): index array element writes under the base variable name" -m "<one-line body>" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01CTr66PbFqDEiS6DXxVy8JV"
```

---

### Task 2: Resolution coverage (proc-local, namespace cross-file, `.rvt`)

**Files:**
- Test: `server/internal/resolve/resolve_test.go`
- Create: `server/internal/rvt/testdata/corpus/array_local.rvt`
- Modify: `server/internal/resolve/corpus_test.go`

**Interfaces:**
- Consumes: `New(ix)`, `index.New()`, `(*Resolver).Definition`, `(*Resolver).References`, `(*Index).IndexFile`, and `corpusFile(t, name)` (existing). No production code changes — Task 1 already implements the behavior; these tests prove the end-to-end resolve/index/`.rvt` paths.

- [ ] **Step 1: Write the resolve-level tests**

Add to `server/internal/resolve/resolve_test.go`:

```go
func TestReferencesProcLocalArray(t *testing.T) {
	r := New(index.New())
	src := "proc f {} {\n  set arr(a) 0\n  set arr(b) 1\n  return [list $arr(a) $arr(b)]\n}"
	useOff := strings.Index(src, "$arr(a)") + 1
	// goto-def from a use lands on the first element write (the declaration).
	defs := r.Definition("a.tcl", src, useOff)
	if len(defs) != 1 || defs[0].NameStart != strings.Index(src, "set arr(a)")+len("set ") {
		t.Fatalf("array goto-def = %#v", defs)
	}
	if src[defs[0].NameStart:defs[0].NameEnd] != "arr" {
		t.Fatalf("range slices %q, want arr", src[defs[0].NameStart:defs[0].NameEnd])
	}
	// find-refs gathers both element writes + both uses, current file only.
	refs := r.References("a.tcl", src, useOff)
	if len(refs) != 4 {
		t.Fatalf("want 4 occurrences (2 writes + 2 uses), got %#v", refs)
	}
	for _, l := range refs {
		if l.File != "a.tcl" {
			t.Fatalf("leaked to %s: %#v", l.File, refs)
		}
	}
}

func TestReferencesProcLocalArrayScopeIsolation(t *testing.T) {
	r := New(index.New())
	src := "proc f {} {\n  set m(x) 1\n  puts $m(x)\n}\nproc g {} {\n  set m(y) 2\n}"
	useOff := strings.Index(src, "$m(x)") + 1
	defs := r.Definition("a.tcl", src, useOff)
	if len(defs) != 1 || defs[0].NameStart != strings.Index(src, "set m(x)")+len("set ") {
		t.Fatalf("crossed scope or wrong target: %#v", defs)
	}
}

func TestDefinitionArrayNamespaceCrossFile(t *testing.T) {
	ix := index.New()
	lib := "namespace eval ::app {\n  set cfg(host) localhost\n}"
	page := "namespace eval ::app {\n  puts $cfg(host)\n}"
	ix.IndexFile("lib.tcl", lib)
	ix.IndexFile("use.tcl", page)
	r := New(ix)

	off := strings.Index(page, "$cfg(host)") + 1
	locs := r.Definition("use.tcl", page, off)
	if len(locs) != 1 || locs[0].File != "lib.tcl" || locs[0].Name != "::app::cfg" {
		t.Fatalf("namespace array cross-file goto-def = %#v", locs)
	}

	defOff := strings.Index(lib, "cfg(host)")
	refs := r.References("lib.tcl", lib, defOff)
	found := false
	for _, l := range refs {
		if l.File == "use.tcl" {
			found = true
		}
	}
	if !found {
		t.Fatalf("references missing the ::app::cfg use in use.tcl: %#v", refs)
	}
}
```

- [ ] **Step 2: Run the resolve tests**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/resolve/ -run 'Array' -v`
Expected: PASS (Task 1 implemented the behavior). If a proc-local case fails, the bug is in Task 1's emission; if the cross-file case fails, investigate the index/`variableCandidates` path — do NOT weaken the test.

- [ ] **Step 3: Create the `.rvt` fixture**

`server/internal/rvt/testdata/corpus/array_local.rvt`:

```
<? proc build_row {cells} {
    set cell(count) 0
    foreach c $cells {
        incr cell(count)
    }
    return $cell(count)
} ?>
<p><?= build_row $data ?></p>
```

- [ ] **Step 4: Write the `.rvt` golden test**

Add to `server/internal/resolve/corpus_test.go`:

```go
// Proc-local array inside an .rvt <? ?> block: goto-def on a $arr(idx) use lands
// on the first element write within the same proc, and find-refs stays in-page.
func TestCorpusArrayLocalInRVT(t *testing.T) {
	page := corpusFile(t, "array_local.rvt")
	ix := index.New()
	ix.IndexFile("array_local.rvt", page)
	r := New(ix)

	off := strings.Index(page, "return $cell(count)") + len("return $")
	defs := r.Definition("array_local.rvt", page, off)
	if len(defs) != 1 || defs[0].File != "array_local.rvt" ||
		page[defs[0].NameStart:defs[0].NameEnd] != "cell" {
		t.Fatalf("rvt array goto-def = %#v", defs)
	}

	refs := r.References("array_local.rvt", page, off)
	if len(refs) < 2 {
		t.Fatalf("expected >=2 occurrences of cell, got %#v", refs)
	}
	for _, l := range refs {
		if l.File != "array_local.rvt" {
			t.Fatalf("ref leaked to %s", l.File)
		}
	}
}
```

- [ ] **Step 5: Run the full suite + vet + gofmt**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./...`
Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server vet ./...`
Run: `gofmt -l server/internal/tcl server/internal/resolve`
Expected: all PASS; gofmt prints nothing.

- [ ] **Step 6: Rebuild + install the binary**

Run: `make -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server install`
Expected: installs to `~/.local/bin/tcl-lsp`. (Where the LSP actually runs, rebuild there + `:LspRestart` / `:TclLspRebuild`.)

- [ ] **Step 7: Commit**

```
git add server/internal/rvt/testdata/corpus/array_local.rvt server/internal/resolve/resolve_test.go server/internal/resolve/corpus_test.go
git commit -m "test(resolve,rvt): array goto-def/refs across proc-local, namespace, and .rvt" -m "<one-line body>" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01CTr66PbFqDEiS6DXxVy8JV"
```

---

## Self-Review

**Spec coverage:**
- Base-name keying, `arr(i)`/`arr($i)`, substitution-free base → Task 1 `arrayBaseName`. ✅
- Proc-local emit sites (set/incr/append/lappend) → Task 1. ✅
- Namespace `set` → `DefNamespaceVar` base name → Task 1. ✅
- Use side / resolver unchanged → no task (verified working); asserted by Task 2. ✅
- goto-def first-binding (arrays inherit scalar rule) → Task 2 asserts; not re-implemented. ✅
- `array set` excluded, namespace incr/append/lappend unchanged → not implemented (correct). ✅
- Proc-local + namespace cross-file + `.rvt` tests → Task 2. ✅

**Placeholder scan:** Commit `-m "<one-line body>"` is intentional shorthand for the implementer to expand; all code steps contain complete code.

**Type consistency:** `arrayBaseName(w Word) (name string, start, end int, ok bool)` is defined in Task 1 and not referenced by name in Task 2 (Task 2 is tests only). Emit sites all use the same `(name, s, e, ok)` shape and `base + s`/`base + e` offsets. Test helpers `defsNamed`/`findDef`/`corpusFile` already exist in the repo.
