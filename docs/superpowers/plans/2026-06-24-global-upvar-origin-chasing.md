# global / upvar Origin-Chasing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** goto-definition on a `global`/`upvar`-linked proc-local jumps to the variable's origin (where it's actually defined), falling back to the link statement when the origin is undefined.

**Architecture:** Record the statically-known origin on a new `tcl.Definition.Origin` field at emit time (`global NAME` → `::NAME`; `upvar #0 NAME` / qualified target → the global/qualified name; frame-relative → empty). Then in `localDefinition`, if the chosen binding has a non-empty `Origin`, look it up in the workspace index and return that; otherwise return the link statement as today.

**Tech Stack:** Go, standard `testing`. Tests run with `go -C server test ./internal/<pkg>/`.

## Global Constraints

- Origin values: `global NAME` → `"::"+NAME` (or `NAME` if already `::`-qualified). `upvar`: target's base name; qualified (`::…`) → as-is; else level `#0` → `"::"+base`; else `""`.
- goto-def chases to the origin via the index **only when the origin resolves**; otherwise falls back to the link statement (never a dead end). Single location.
- `Origin` is non-positional: it passes through the `source` seam unchanged and never enters the index (`DefLocal`/`DefGlobalLink` aren't indexed).
- No new `DefKind`. `isLocalBinding`, `localReferences`, `localAt` are unchanged. find-references is unchanged.
- Frame-relative `upvar` (default level / `1` / `#N` for N>0) with a bare target is NOT chaseable.
- Run tests with `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ...` (no `cd`). One command per Bash call — no `&&`/`;`/`|`.
- Commit messages: conventional commits; end with the `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` and `Claude-Session: …` trailers used throughout this repo.

---

## File Structure

- `server/internal/tcl/defs.go` — add `Origin` field to `Definition`; add `globalOrigin`/`upvarOrigin` helpers; set `Origin` in the `global` and `upvar` emit blocks (Task 1).
- `server/internal/tcl/defs_test.go` — `Origin`-emission unit tests (Task 1).
- `server/internal/resolve/resolve.go` — origin-chase branch in `localDefinition` (Task 2).
- `server/internal/resolve/resolve_test.go` — resolve-level chase/fallback tests (Task 2).

---

### Task 1: Record `Origin` on global/upvar definitions

**Files:**
- Modify: `server/internal/tcl/defs.go` (add `Definition.Origin`; add `globalOrigin`, `upvarOrigin`; set `Origin` in the `global` and `upvar` blocks of `emitDefs`)
- Test: `server/internal/tcl/defs_test.go`

**Interfaces:**
- Consumes: `Word` (`.Text`, `.Start`, `.End`, `.Kind`), `isPlainName`, `isUpvarLevel`, `arrayBaseName(w Word) (name string, start, end int, ok bool)`, existing test helper `findDef`. `defs.go` already imports `strings`.
- Produces: `Definition.Origin string`; `globalOrigin(name string) string`; `upvarOrigin(level string, target Word) string`.

- [ ] **Step 1: Write the failing test**

Add to `server/internal/tcl/defs_test.go`:

```go
func TestFileDefsGlobalUpvarOrigin(t *testing.T) {
	cases := []struct{ src, name, wantOrigin string }{
		{"proc f {} {\n  global config\n}", "config", "::config"},
		{"proc f {} {\n  global ::app::x\n}", "::app::x", "::app::x"},
		{"proc f {} {\n  upvar #0 sessions s\n}", "s", "::sessions"},
		{"proc f {} {\n  upvar 0 ::app::cfg c\n}", "c", "::app::cfg"},
		{"proc f {} {\n  upvar 1 caller v\n}", "v", ""},
		{"proc f {} {\n  set local 1\n}", "local", ""},
	}
	for _, tc := range cases {
		d := findDef(FileDefs(tc.src), tc.name)
		if d == nil {
			t.Fatalf("src %q: no def named %q in %#v", tc.src, tc.name, FileDefs(tc.src))
		}
		if d.Origin != tc.wantOrigin {
			t.Fatalf("src %q: Origin = %q, want %q", tc.src, d.Origin, tc.wantOrigin)
		}
	}
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/tcl/ -run TestFileDefsGlobalUpvarOrigin -v`
Expected: compile error — `Definition` has no field `Origin`.

- [ ] **Step 3: Add the `Origin` field to `Definition`**

In `server/internal/tcl/defs.go`, add the field to the `Definition` struct (after `Scope`):

```go
type Definition struct {
	Kind      DefKind
	Name      string
	Namespace string
	NameStart int
	NameEnd   int
	Scope     int
	// Origin is the fully-qualified variable a global/upvar link points at
	// (e.g. `global config` -> "::config"), or "" when there is none or it is
	// not statically known. Used by goto-definition to chase past the link.
	Origin string
}
```

- [ ] **Step 4: Add the origin helpers**

In `server/internal/tcl/defs.go` (e.g. near `arrayBaseName`):

```go
// globalOrigin returns the fully-qualified global variable a `global NAME` links
// to: the global namespace always, so a bare name is qualified with "::".
func globalOrigin(name string) string {
	if strings.HasPrefix(name, "::") {
		return name
	}
	return "::" + name
}

// upvarOrigin returns the fully-qualified origin an `upvar` alias points at, or ""
// when it is not statically resolvable. A qualified target (`::x`) is absolute; a
// bare target is the global variable of that name only when the level is "#0"
// (the global frame). Frame-relative levels (default/`1`/`#N>0`) name a variable
// in another call frame and are dynamic -> "".
func upvarOrigin(level string, target Word) string {
	base, _, _, ok := arrayBaseName(target)
	if !ok {
		return "" // dynamic/substituted target (e.g. $name)
	}
	if strings.HasPrefix(base, "::") {
		return base
	}
	if level == "#0" {
		return "::" + base
	}
	return ""
}
```

- [ ] **Step 5: Set `Origin` in the `global` block**

Replace the `global` block in `emitDefs` with (adds `Origin`):

```go
	if isCmd(w, "global") && frame == FrameProc {
		for _, gw := range w[1:] {
			if isPlainName(gw) {
				*out = append(*out, Definition{
					Kind: DefGlobalLink, Name: gw.Text, Namespace: ns,
					NameStart: base + gw.Start, NameEnd: base + gw.End, Scope: scope,
					Origin: globalOrigin(gw.Text),
				})
			}
		}
	}
```

- [ ] **Step 6: Capture the level and set `Origin` in the `upvar` block**

Replace the `upvar` block in `emitDefs` with (captures `level`, pairs target with alias, sets `Origin`):

```go
	if isCmd(w, "upvar") && frame == FrameProc && len(w) >= 3 {
		args := w[1:]
		// Optional leading level (e.g. 1 or #0); the rest are (otherVar, alias)
		// pairs. The alias names are static locals; a target is chaseable only
		// when qualified or reached via the #0 (global) frame -- see upvarOrigin.
		level := ""
		if len(args) > 0 && isUpvarLevel(args[0]) {
			level = args[0].Text
			args = args[1:]
		}
		for i := 1; i < len(args); i += 2 {
			alias := args[i]
			if isPlainName(alias) {
				*out = append(*out, Definition{
					Kind: DefLocal, Name: alias.Text, Namespace: ns,
					NameStart: base + alias.Start, NameEnd: base + alias.End, Scope: scope,
					Origin: upvarOrigin(level, args[i-1]),
				})
			}
		}
	}
```

(The `args[i-1]` is the target paired with the alias at `args[i]`.)

- [ ] **Step 7: Run the test to verify it passes**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/tcl/`
Expected: PASS — new test green; all existing `tcl` tests still pass (the new field defaults to `""`, so existing `Definition` literal comparisons are unaffected).

- [ ] **Step 8: Commit**

```
git add server/internal/tcl/defs.go server/internal/tcl/defs_test.go
git commit -m "feat(tcl): record global/upvar link origin on Definition" -m "<one-line body>" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01CTr66PbFqDEiS6DXxVy8JV"
```

---

### Task 2: Chase the origin in `localDefinition`

**Files:**
- Modify: `server/internal/resolve/resolve.go` (`localDefinition` — capture the chosen binding's `Origin`, chase it via the index, fall back to the link)
- Test: `server/internal/resolve/resolve_test.go`

**Interfaces:**
- Consumes: `Definition.Origin` (Task 1), `source.Defs`, `isLocalBinding`, `(*Resolver).lookupScoped(name, file string) []index.Location`, `index.Location`, `tcl.DefLocal`. Test helpers `New`, `index.New`, `IndexFile` (existing); `resolve_test.go` imports `strings` and `index`.
- Produces: no new exported symbols.

- [ ] **Step 1: Write the failing tests**

Add to `server/internal/resolve/resolve_test.go`:

```go
func TestDefinitionGlobalChasesToOrigin(t *testing.T) {
	ix := index.New()
	ix.IndexFile("lib.tcl", "set ::config 1")
	use := "proc f {} {\n  global config\n  return $config\n}"
	ix.IndexFile("use.tcl", use)
	r := New(ix)

	off := strings.Index(use, "return $config") + len("return $")
	locs := r.Definition("use.tcl", use, off)
	if len(locs) != 1 || locs[0].File != "lib.tcl" || locs[0].Name != "::config" {
		t.Fatalf("global chase = %#v", locs)
	}
}

func TestDefinitionGlobalFallsBackToLink(t *testing.T) {
	r := New(index.New())
	src := "proc f {} {\n  global config\n  return $config\n}"
	off := strings.Index(src, "return $config") + len("return $")
	locs := r.Definition("a.tcl", src, off)
	if len(locs) != 1 || locs[0].File != "a.tcl" {
		t.Fatalf("want fallback to link in a.tcl, got %#v", locs)
	}
	// ::config is undefined in the workspace -> land on the `global config` line.
	if locs[0].NameStart != strings.Index(src, "global config")+len("global ") {
		t.Fatalf("expected the `global config` link, got %#v", locs)
	}
}

func TestDefinitionUpvarHashZeroChasesToOrigin(t *testing.T) {
	ix := index.New()
	ix.IndexFile("lib.tcl", "set ::sessions {}")
	use := "proc f {} {\n  upvar #0 sessions s\n  return $s\n}"
	ix.IndexFile("use.tcl", use)
	r := New(ix)

	off := strings.Index(use, "return $s") + len("return $")
	locs := r.Definition("use.tcl", use, off)
	if len(locs) != 1 || locs[0].File != "lib.tcl" || locs[0].Name != "::sessions" {
		t.Fatalf("upvar #0 chase = %#v", locs)
	}
}

func TestDefinitionUpvarFrameRelativeStaysOnLink(t *testing.T) {
	r := New(index.New())
	src := "proc f {} {\n  upvar 1 caller v\n  return $v\n}"
	off := strings.Index(src, "return $v") + len("return $")
	locs := r.Definition("a.tcl", src, off)
	if len(locs) != 1 || locs[0].File != "a.tcl" {
		t.Fatalf("want link in a.tcl, got %#v", locs)
	}
	// frame-relative target is dynamic -> land on the upvar alias `v`.
	if locs[0].NameStart != strings.Index(src, "caller v")+len("caller ") {
		t.Fatalf("expected the upvar alias v, got %#v", locs)
	}
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/resolve/ -run 'TestDefinitionGlobal|TestDefinitionUpvar' -v`
Expected: the chase tests FAIL (today goto-def returns the link line, not `lib.tcl`'s `::config`/`::sessions`). The two fallback/frame-relative tests may already pass (they assert today's link behavior).

- [ ] **Step 3: Add the origin-chase branch to `localDefinition`**

Replace `localDefinition` in `server/internal/resolve/resolve.go` with:

```go
func (r *Resolver) localDefinition(file, src, name string, scope int) []index.Location {
	firstStart, firstEnd, firstOrigin, have := 0, 0, "", false
	for _, d := range source.Defs(file, src) {
		if !isLocalBinding(d.Kind) || d.Name != name || d.Scope != scope {
			continue
		}
		if !have || d.NameStart < firstStart {
			firstStart, firstEnd, firstOrigin, have = d.NameStart, d.NameEnd, d.Origin, true
		}
	}
	if !have {
		return nil
	}
	// Origin-chase: a global/upvar link points at a variable in another scope.
	// Jump to that origin's definition when it exists in the workspace index;
	// otherwise fall back to the link statement.
	if firstOrigin != "" {
		if locs := r.lookupScoped(firstOrigin, file); len(locs) > 0 {
			return locs
		}
	}
	return []index.Location{{File: file, Name: name, Kind: tcl.DefLocal, NameStart: firstStart, NameEnd: firstEnd}}
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/resolve/`
Expected: PASS — all four new tests green; existing proc-local/array goto-def and find-references tests unchanged (they have no `Origin`, so the chase branch is skipped).

- [ ] **Step 5: Run the full suite + vet + gofmt**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./...`
Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server vet ./...`
Run: `gofmt -l server/internal/tcl server/internal/resolve`
Expected: all PASS; gofmt prints nothing.

- [ ] **Step 6: Rebuild + install the binary**

Run: `make -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server install`
Expected: installs to `~/.local/bin/tcl-lsp`. (Where the LSP actually runs, rebuild there + `:TclLspRebuild` / `:LspRestart`.)

- [ ] **Step 7: Commit**

```
git add server/internal/resolve/resolve.go server/internal/resolve/resolve_test.go
git commit -m "feat(resolve): chase global/upvar links to the variable origin in goto-def" -m "<one-line body>" -m "Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>" -m "Claude-Session: https://claude.ai/code/session_01CTr66PbFqDEiS6DXxVy8JV"
```

---

## Self-Review

**Spec coverage:**
- `Origin` field, set for global/upvar at emit time → Task 1. ✅
- Origin rules (global `::name`; upvar qualified / `#0` / else `""`) → Task 1 `globalOrigin`/`upvarOrigin`. ✅
- Chase via index, fall back to link → Task 2 `localDefinition`. ✅
- Cross-file origin lookup → Task 2 (uses `lookupScoped`, index-backed). ✅
- find-references unchanged, frame-relative not chaseable → not implemented (correct); asserted by Task 1/2 tests (`upvar 1` → `Origin ""`; frame-relative stays on link). ✅
- `Origin` passes through `source` seam, not indexed → no change needed (value-copied; locals/links filtered from index). ✅

**Placeholder scan:** Commit `-m "<one-line body>"` is intentional shorthand for the implementer to expand; all code steps contain complete code.

**Type consistency:** `Definition.Origin string` (Task 1) is read as `d.Origin` in Task 2. `globalOrigin(name string) string` and `upvarOrigin(level string, target Word) string` are defined and called in Task 1 only. `arrayBaseName(w Word) (name string, start, end int, ok bool)` (existing) is consumed by `upvarOrigin`. `lookupScoped(name, file string)` matches its definition in resolve.go.
