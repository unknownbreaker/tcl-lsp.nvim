# Phase A — Plan 9: Resolver + goto-definition (index cases)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Given a cursor byte offset in a file, resolve the symbol to its definition site(s) using the resolution algorithms and the workspace index.

**Architecture:** New `resolve` package (see `docs/plans/2026-06-06-goto-def-ref-design.md`). Finds the reference at the offset (via `tcl.FileRefs`), classifies it (command vs variable), computes fully-qualified candidate names (command: current ns → global; variable: qualified / namespace-top), and looks them up in the `index`. Returns all matching `index.Location`s.

**Scope of this plan (and deferrals):** Handles command references (current-namespace then global) and namespace/qualified variable references. **Deferred to the next plan:** bare proc-local variables (frame-local resolution), `namespace path` command search, and goto-*references* (reverse scan). Bare proc-locals return no result here.

**Tech Stack:** Go 1.23+ (local 1.26.4), `strings`, `testing`.

---

## File structure

- `server/internal/resolve/resolve.go` — `Resolver`, `New`, `Definition`, candidate helpers.
- `server/internal/resolve/resolve_test.go` — tests.

Imports `github.com/unknownbreaker/tcl-lsp/internal/index` and `.../internal/tcl`.

---

## Task 1: Resolver + command goto-definition

**Files:**
- Create: `server/internal/resolve/resolve.go`
- Create: `server/internal/resolve/resolve_test.go`

- [ ] **Step 1: Write the failing test**

Create `server/internal/resolve/resolve_test.go`:

```go
package resolve

import (
	"strings"
	"testing"

	"github.com/unknownbreaker/tcl-lsp/internal/index"
)

func TestDefinitionCommandSameNamespace(t *testing.T) {
	ix := index.New()
	ix.IndexFile("lib.tcl", "namespace eval ::app {\n  proc run {} {}\n}")
	r := New(ix)

	mainSrc := "namespace eval ::app {\n  run\n}"
	off := strings.Index(mainSrc, "\n  run") + 3 // on the `run` call
	locs := r.Definition("main.tcl", mainSrc, off)
	if len(locs) != 1 || locs[0].Name != "::app::run" || locs[0].File != "lib.tcl" {
		t.Fatalf("definition = %#v", locs)
	}
}

func TestDefinitionCommandQualified(t *testing.T) {
	ix := index.New()
	ix.IndexFile("lib.tcl", "namespace eval ::app {\n  proc run {} {}\n}")
	r := New(ix)

	locs := r.Definition("main.tcl", "::app::run", 3)
	if len(locs) != 1 || locs[0].Name != "::app::run" {
		t.Fatalf("definition = %#v", locs)
	}
}

func TestDefinitionCommandGlobalFallback(t *testing.T) {
	ix := index.New()
	ix.IndexFile("lib.tcl", "proc greet {} {}")
	r := New(ix)

	// A bare `greet` call from inside ::app falls back to global ::greet.
	mainSrc := "namespace eval ::app {\n  greet\n}"
	off := strings.Index(mainSrc, "\n  greet") + 3
	locs := r.Definition("main.tcl", mainSrc, off)
	if len(locs) != 1 || locs[0].Name != "::greet" {
		t.Fatalf("definition = %#v", locs)
	}
}

func TestDefinitionUnknownCommand(t *testing.T) {
	r := New(index.New())
	if locs := r.Definition("a.tcl", "doesnotexist", 0); len(locs) != 0 {
		t.Fatalf("unknown command should resolve to nothing, got %#v", locs)
	}
}

func TestDefinitionNoSymbolAtOffset(t *testing.T) {
	r := New(index.New())
	if locs := r.Definition("a.tcl", "set x 1", 100); locs != nil {
		t.Fatalf("out-of-range offset should be nil, got %#v", locs)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/resolve/`
Expected: FAIL — the `resolve` package does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `server/internal/resolve/resolve.go`:

```go
// Package resolve maps a cursor position to definition sites using the workspace
// index and TCL's name-resolution rules.
package resolve

import (
	"strings"

	"github.com/unknownbreaker/tcl-lsp/internal/index"
	"github.com/unknownbreaker/tcl-lsp/internal/tcl"
)

// Resolver resolves symbols to definitions against a workspace index.
type Resolver struct {
	ix *index.Index
}

// New returns a Resolver over the given index.
func New(ix *index.Index) *Resolver {
	return &Resolver{ix: ix}
}

// Definition returns the definition site(s) for the symbol at byte offset in the
// file with the given source. Returns nil if there is no symbol at the offset or
// it resolves to nothing.
func (r *Resolver) Definition(file, src string, offset int) []index.Location {
	ref := refAt(src, offset)
	if ref == nil {
		return nil
	}
	var out []index.Location
	for _, name := range r.candidates(ref) {
		out = append(out, r.ix.Lookup(name)...)
	}
	return out
}

// refAt returns the innermost reference whose byte range contains offset.
func refAt(src string, offset int) *tcl.ContextRef {
	refs := tcl.FileRefs(src)
	var best *tcl.ContextRef
	for i := range refs {
		rg := refs[i].Ref
		if offset >= rg.Start && offset < rg.End {
			if best == nil || (rg.End-rg.Start) < (best.Ref.End-best.Ref.Start) {
				best = &refs[i]
			}
		}
	}
	return best
}

// candidates returns the fully-qualified names to look up for a reference.
func (r *Resolver) candidates(ref *tcl.ContextRef) []string {
	name := ref.Ref.Name
	ns := ref.Namespace
	if ref.Ref.Kind == tcl.RefCommand {
		return commandCandidates(name, ns)
	}
	return variableCandidates(name, ns, ref.Frame)
}

// commandCandidates: a qualified name resolves directly; a bare name is searched
// in the current namespace then the global namespace.
func commandCandidates(name, ns string) []string {
	if isQualified(name) {
		return []string{qualify(name, ns)}
	}
	if ns == "::" {
		return []string{"::" + name}
	}
	return []string{ns + "::" + name, "::" + name}
}

// variableCandidates is completed in the next task; commands work now.
func variableCandidates(name, ns string, frame tcl.FrameKind) []string {
	return nil
}

func isQualified(name string) bool { return strings.Contains(name, "::") }

// qualify resolves name against ns: a leading "::" is absolute; otherwise the
// name is qualified into ns.
func qualify(name, ns string) string {
	if strings.HasPrefix(name, "::") {
		return name
	}
	if ns == "::" {
		return "::" + name
	}
	return ns + "::" + name
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/resolve/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add server/internal/resolve/
git commit -m "feat(resolve): goto-definition for command references via index"
```

---

## Task 2: Variable goto-definition (qualified + namespace-top)

**Files:**
- Modify: `server/internal/resolve/resolve.go`
- Modify: `server/internal/resolve/resolve_test.go`

- [ ] **Step 1: Write the failing test**

Add to `server/internal/resolve/resolve_test.go`:

```go
func TestDefinitionNamespaceVariable(t *testing.T) {
	ix := index.New()
	ix.IndexFile("lib.tcl", "namespace eval ::app {\n  variable count 0\n}")
	r := New(ix)

	mainSrc := "namespace eval ::app {\n  puts $count\n}"
	off := strings.Index(mainSrc, "$count") + 1 // on `count`
	locs := r.Definition("main.tcl", mainSrc, off)
	if len(locs) != 1 || locs[0].Name != "::app::count" {
		t.Fatalf("definition = %#v", locs)
	}
}

func TestDefinitionQualifiedVariable(t *testing.T) {
	ix := index.New()
	ix.IndexFile("lib.tcl", "namespace eval ::app {\n  variable count 0\n}")
	r := New(ix)

	mainSrc := "puts $::app::count"
	off := strings.Index(mainSrc, "$::app::count") + 5
	locs := r.Definition("main.tcl", mainSrc, off)
	if len(locs) != 1 || locs[0].Name != "::app::count" {
		t.Fatalf("definition = %#v", locs)
	}
}

func TestDefinitionProcLocalDeferred(t *testing.T) {
	// A bare variable inside a proc body is local-only; resolving it is deferred
	// to the frame-local resolution plan. For now it returns nothing.
	r := New(index.New())
	src := "proc f {x} { puts $x }"
	off := strings.Index(src, "$x") + 1
	if locs := r.Definition("a.tcl", src, off); locs != nil {
		t.Fatalf("bare proc-local should be unresolved (deferred), got %#v", locs)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/resolve/ -run "TestDefinitionNamespaceVariable|TestDefinitionQualifiedVariable"`
Expected: FAIL — `variableCandidates` currently returns nil.

- [ ] **Step 3: Write minimal implementation**

In `server/internal/resolve/resolve.go`, replace `variableCandidates` with:

```go
// variableCandidates: a qualified variable resolves directly; a bare variable at
// namespace-eval top level is the current namespace's own variable. A bare
// variable inside a proc body is local-only and not resolvable via the workspace
// index (frame-local resolution is a later plan) — returns nil.
func variableCandidates(name, ns string, frame tcl.FrameKind) []string {
	if isQualified(name) {
		return []string{qualify(name, ns)}
	}
	if frame == tcl.FrameNamespace {
		if ns == "::" {
			return []string{"::" + name}
		}
		return []string{ns + "::" + name}
	}
	return nil // bare proc-local — deferred
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/resolve/`
Expected: PASS (all resolve tests).

- [ ] **Step 5: Commit**

```bash
git add server/internal/resolve/
git commit -m "feat(resolve): goto-definition for namespace/qualified variables"
```

---

## Task 3: Multiple definition sites + integration

**Files:**
- Modify: `server/internal/resolve/resolve_test.go`

- [ ] **Step 1: Write the test**

Add to `server/internal/resolve/resolve_test.go`:

```go
func TestDefinitionMultipleSites(t *testing.T) {
	ix := index.New()
	ix.IndexFile("a.tcl", "proc dup {} {}")
	ix.IndexFile("b.tcl", "proc dup {} {}")
	r := New(ix)

	locs := r.Definition("main.tcl", "dup", 0)
	if len(locs) != 2 {
		t.Fatalf("expected 2 def sites for ::dup, got %#v", locs)
	}
	files := map[string]bool{}
	for _, l := range locs {
		files[l.File] = true
	}
	if !files["a.tcl"] || !files["b.tcl"] {
		t.Fatalf("expected both a.tcl and b.tcl: %#v", locs)
	}
}

func TestDefinitionNestedCommandSubstitution(t *testing.T) {
	// goto-definition on a command used inside a [command substitution].
	ix := index.New()
	ix.IndexFile("lib.tcl", "proc helper {} {}")
	r := New(ix)

	mainSrc := "set x [helper]"
	off := strings.Index(mainSrc, "helper")
	locs := r.Definition("main.tcl", mainSrc, off)
	if len(locs) != 1 || locs[0].Name != "::helper" {
		t.Fatalf("definition = %#v", locs)
	}
}
```

- [ ] **Step 2: Run the full suite**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server vet ./...`
Then: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./...`
Expected: clean vet; all tests PASS (tcl + index + resolve packages).

- [ ] **Step 3: Commit**

```bash
git add server/internal/resolve/
git commit -m "test(resolve): multiple definition sites and command-substitution"
```

---

## Done criteria for Plan 9

- `go vet ./...` clean; `go test ./...` all pass.
- `resolve.Resolver.Definition(file, src, offset)` returns the definition `Location`(s) for: command references (current namespace then global, qualified names directly, including inside `[command substitution]`), and namespace/qualified variable references — all via the workspace index, returning every matching site. Bare proc-local variables and `namespace path` command search are documented deferrals returning nil.

**Next:** Plan 10 — frame-local variable resolution (bare `$x` in a proc → its param/`set`/`upvar`/`global`/`variable` declaration), `namespace path` command search, and goto-**references** (reverse scan over the workspace). Then the LSP shell (JSON-RPC/stdio) + editor clients + binaries.
