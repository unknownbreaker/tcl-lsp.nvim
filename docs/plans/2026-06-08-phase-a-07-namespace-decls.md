# Phase A — Plan 7: Namespace Declarations (export/import/path)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collect per-namespace `namespace export`, `namespace import`, and `namespace path` declarations so the resolver can extend command lookup and model import aliases.

**Architecture:** Small parser-layer addition (see `docs/plans/2026-06-06-goto-def-ref-design.md`). Adds `tcl.FileNamespaces(src) map[string]*NamespaceInfo`. These declarations affect *resolution*, not goto targets, so byte offsets are not tracked here. Reuses the same body-recursion shape as the context/defs walks.

**Tech Stack:** Go 1.23+ (local 1.26.4), standard `testing`.

---

## File structure

- `server/internal/tcl/nsdecl.go` — `NamespaceInfo`, `FileNamespaces`, walk + helpers.
- `server/internal/tcl/nsdecl_test.go` — table-driven tests.

Reuses `Command`/`Word` (parser.go), `Parse`, `isCmd`/`qualifyNamespace`/`bracedInner` (context.go).

**Semantics modeled (per research/02):** `namespace path` SETS the search path (last one wins). `namespace export` accumulates patterns. `namespace import` accumulates source patterns (qualified). Import flags like `-force` are skipped. Export patterns are kept verbatim (they are globs within the namespace, not qualified names).

---

## Task 1: Types + `namespace export`

**Files:**
- Create: `server/internal/tcl/nsdecl.go`
- Create: `server/internal/tcl/nsdecl_test.go`

- [ ] **Step 1: Write the failing test**

Create `server/internal/tcl/nsdecl_test.go`:

```go
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
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `server/`): `go test ./internal/tcl/ -run TestFileNamespaces`
Expected: FAIL — compile error, `undefined: FileNamespaces`, `undefined: NamespaceInfo`.

- [ ] **Step 3: Write minimal implementation**

Create `server/internal/tcl/nsdecl.go`:

```go
package tcl

// NamespaceInfo aggregates the resolution-affecting declarations of one
// namespace. Path is the command search path (set by `namespace path`); Exports
// are export glob patterns; Imports are qualified source patterns from
// `namespace import`.
type NamespaceInfo struct {
	Name    string
	Path    []string
	Exports []string
	Imports []string
}

// FileNamespaces parses src and returns per-namespace declarations, keyed by the
// fully-qualified namespace name. Only namespaces with at least one declaration
// appear in the map.
func FileNamespaces(src string) map[string]*NamespaceInfo {
	m := map[string]*NamespaceInfo{}
	walkNS(Parse(src), "::", m)
	return m
}

func walkNS(cmds []Command, ns string, m map[string]*NamespaceInfo) {
	for _, c := range cmds {
		recordNSDecl(c, ns, m)
		w := c.Words
		if isCmd(w, "namespace") && len(w) >= 4 && w[1].Text == "eval" && w[len(w)-1].Kind == WordBraced {
			child := qualifyNamespace(w[2].Text, ns)
			inner, _ := bracedInner(w[len(w)-1], 0)
			walkNS(Parse(inner), child, m)
		}
		if isCmd(w, "proc") && len(w) >= 4 && w[len(w)-1].Kind == WordBraced {
			inner, _ := bracedInner(w[len(w)-1], 0)
			walkNS(Parse(inner), ns, m)
		}
	}
}

func recordNSDecl(c Command, ns string, m map[string]*NamespaceInfo) {
	w := c.Words
	if !isCmd(w, "namespace") || len(w) < 3 || w[1].Kind != WordBare {
		return
	}
	switch w[1].Text {
	case "export":
		info := ensureNS(m, ns)
		for _, pw := range w[2:] {
			if pw.Text != "" && pw.Text[0] != '-' {
				info.Exports = append(info.Exports, unbrace(pw.Text))
			}
		}
	}
}

func ensureNS(m map[string]*NamespaceInfo, ns string) *NamespaceInfo {
	if m[ns] == nil {
		m[ns] = &NamespaceInfo{Name: ns}
	}
	return m[ns]
}

// unbrace strips a single layer of surrounding braces, if present.
func unbrace(s string) string {
	if len(s) >= 2 && s[0] == '{' && s[len(s)-1] == '}' {
		return s[1 : len(s)-1]
	}
	return s
}
```

- [ ] **Step 4: Run test to verify it passes**

Run (from `server/`): `go test ./internal/tcl/ -run TestFileNamespaces`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add server/internal/tcl/nsdecl.go server/internal/tcl/nsdecl_test.go
git commit -m "feat(tcl): collect namespace export declarations"
```

---

## Task 2: `namespace import` (with flag skipping + qualification)

**Files:**
- Modify: `server/internal/tcl/nsdecl.go`
- Modify: `server/internal/tcl/nsdecl_test.go`

- [ ] **Step 1: Write the failing test**

Add to `server/internal/tcl/nsdecl_test.go`:

```go
func TestFileNamespacesImport(t *testing.T) {
	src := "namespace eval ::c {\n  namespace import ::p::pub\n}"
	m := FileNamespaces(src)
	info := m["::c"]
	if info == nil || !reflect.DeepEqual(info.Imports, []string{"::p::pub"}) {
		t.Fatalf("imports = %#v", m["::c"])
	}
}

func TestFileNamespacesImportForceFlagSkipped(t *testing.T) {
	src := "namespace eval ::c {\n  namespace import -force ::p::x ::p::y\n}"
	m := FileNamespaces(src)
	info := m["::c"]
	if info == nil || !reflect.DeepEqual(info.Imports, []string{"::p::x", "::p::y"}) {
		t.Fatalf("imports = %#v", m["::c"])
	}
}

func TestFileNamespacesImportRelativeQualified(t *testing.T) {
	src := "namespace eval ::a {\n  namespace import sub::x\n}"
	m := FileNamespaces(src)
	info := m["::a"]
	if info == nil || !reflect.DeepEqual(info.Imports, []string{"::a::sub::x"}) {
		t.Fatalf("imports = %#v", m["::a"])
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `server/`): `go test ./internal/tcl/ -run TestFileNamespacesImport`
Expected: FAIL — `import` not yet handled.

- [ ] **Step 3: Write minimal implementation**

In `server/internal/tcl/nsdecl.go`, add an `import` case to the `switch w[1].Text` in `recordNSDecl`:

```go
	case "import":
		info := ensureNS(m, ns)
		for _, pw := range w[2:] {
			if pw.Text == "" || pw.Text[0] == '-' {
				continue // skip flags like -force
			}
			info.Imports = append(info.Imports, qualifyNamespace(unbrace(pw.Text), ns))
		}
```

- [ ] **Step 4: Run test to verify it passes**

Run (from `server/`): `go test ./internal/tcl/`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add server/internal/tcl/nsdecl.go server/internal/tcl/nsdecl_test.go
git commit -m "feat(tcl): collect namespace import declarations"
```

---

## Task 3: `namespace path`

**Files:**
- Modify: `server/internal/tcl/nsdecl.go`
- Modify: `server/internal/tcl/nsdecl_test.go`

- [ ] **Step 1: Write the failing test**

Add to `server/internal/tcl/nsdecl_test.go`:

```go
func TestFileNamespacesPathList(t *testing.T) {
	src := "namespace eval ::u {\n  namespace path {::lib ::other}\n}"
	m := FileNamespaces(src)
	info := m["::u"]
	if info == nil || !reflect.DeepEqual(info.Path, []string{"::lib", "::other"}) {
		t.Fatalf("path = %#v", m["::u"])
	}
}

func TestFileNamespacesPathSingleRelative(t *testing.T) {
	src := "namespace eval ::a {\n  namespace path b\n}"
	m := FileNamespaces(src)
	info := m["::a"]
	if info == nil || !reflect.DeepEqual(info.Path, []string{"::a::b"}) {
		t.Fatalf("path = %#v", m["::a"])
	}
}

func TestFileNamespacesPathLastWins(t *testing.T) {
	src := "namespace eval ::a {\n  namespace path ::x\n  namespace path ::y\n}"
	m := FileNamespaces(src)
	info := m["::a"]
	if info == nil || !reflect.DeepEqual(info.Path, []string{"::y"}) {
		t.Fatalf("path (last wins) = %#v", m["::a"])
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run (from `server/`): `go test ./internal/tcl/ -run TestFileNamespacesPath`
Expected: FAIL — `path` not yet handled.

- [ ] **Step 3: Write minimal implementation**

In `server/internal/tcl/nsdecl.go`, add a `path` case to the `switch`, and add `parsePathList`:

```go
	case "path":
		info := ensureNS(m, ns)
		info.Path = parsePathList(w[2], ns) // `namespace path` sets (replaces) the path
```

```go
// parsePathList resolves the entries of a `namespace path` list argument
// (braced `{a b}` or a single name) into qualified namespace names.
func parsePathList(w Word, ns string) []string {
	var out []string
	for _, c := range Parse(unbrace(w.Text)) {
		for _, word := range c.Words {
			name := unbrace(word.Text)
			if name != "" {
				out = append(out, qualifyNamespace(name, ns))
			}
		}
	}
	return out
}
```

- [ ] **Step 4: Run test to verify it passes**

Run (from `server/`): `go test ./internal/tcl/`
Expected: PASS (all tests).

- [ ] **Step 5: Commit**

```bash
git add server/internal/tcl/nsdecl.go server/internal/tcl/nsdecl_test.go
git commit -m "feat(tcl): collect namespace path (set semantics, qualified)"
```

---

## Task 4: Integration — nested namespaces and combined declarations

**Files:**
- Modify: `server/internal/tcl/nsdecl_test.go`

- [ ] **Step 1: Write the test**

Add to `server/internal/tcl/nsdecl_test.go`:

```go
func TestFileNamespacesCombinedNested(t *testing.T) {
	src := "namespace eval ::a {\n" +
		"  namespace export api*\n" +
		"  namespace path {::lib}\n" +
		"  namespace eval b {\n" +
		"    namespace import ::p::tool\n" +
		"  }\n" +
		"}"
	m := FileNamespaces(src)

	a := m["::a"]
	if a == nil {
		t.Fatalf("no ::a in %#v", m)
	}
	if !reflect.DeepEqual(a.Exports, []string{"api*"}) {
		t.Fatalf("::a exports = %#v", a.Exports)
	}
	if !reflect.DeepEqual(a.Path, []string{"::lib"}) {
		t.Fatalf("::a path = %#v", a.Path)
	}

	b := m["::a::b"]
	if b == nil {
		t.Fatalf("no ::a::b in %#v", m)
	}
	if !reflect.DeepEqual(b.Imports, []string{"::p::tool"}) {
		t.Fatalf("::a::b imports = %#v", b.Imports)
	}
}
```

- [ ] **Step 2: Run the full suite**

Run (from `server/`): `go vet ./...`
Then: `go test ./...`
Expected: clean vet; all tests PASS (Plans 1–7).

- [ ] **Step 3: Commit**

```bash
git add server/internal/tcl/nsdecl_test.go
git commit -m "test(tcl): combined nested namespace declarations"
```

---

## Done criteria for Plan 7

- `go vet ./...` clean; `go test ./...` all pass.
- `tcl.FileNamespaces(src)` returns per-namespace `NamespaceInfo` with `Exports` (verbatim patterns), `Imports` (qualified source patterns, flags skipped), and `Path` (qualified, set-semantics / last-wins), recursing into nested namespaces and proc bodies.

**Next:** Plan 8 — workspace indexer: glob `**/*.tcl`, run `FileDefs`/`FileRefs`/`FileNamespaces` per file, build the workspace-wide fully-qualified symbol table (two-phase), with incremental per-file update. Then Plan 9 — the resolver + goto-def/ref core; Plan 10 — LSP shell + clients.
