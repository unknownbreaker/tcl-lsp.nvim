# Phase A — Plan 8: Workspace Indexer Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a workspace-wide, fully-qualified symbol table of definitions over many files, with incremental per-file update and filesystem directory indexing.

**Architecture:** New `index` package (see `docs/plans/2026-06-06-goto-def-ref-design.md`). Runs `tcl.FileDefs` per file and stores workspace-visible definitions (procs + namespace variables) keyed by FQ name → all definition sites. Stores each file's source so the resolver (Plan 9) can compute references/namespaces on demand. Locals and `global` links are NOT workspace-indexed (resolved frame-locally later). Incremental: re-indexing a file replaces its contributions.

**Tech Stack:** Go 1.23+ (local 1.26.4), standard library (`os`, `io/fs`, `path/filepath`, `sort`, `strings`), `testing`.

---

## File structure

- `server/internal/index/index.go` — `Index`, `Location`, `New`, `IndexFile`, `RemoveFile`, `Lookup`, `Files`, `Source`, `IndexDir`.
- `server/internal/index/index_test.go` — tests (including a `t.TempDir()` filesystem test).

Imports `github.com/unknownbreaker/tcl-lsp/internal/tcl`.

---

## Task 1: Index type + IndexFile + Lookup

**Files:**
- Create: `server/internal/index/index.go`
- Create: `server/internal/index/index_test.go`

- [ ] **Step 1: Write the failing test**

Create `server/internal/index/index_test.go`:

```go
package index

import (
	"testing"

	"github.com/unknownbreaker/tcl-lsp/internal/tcl"
)

func TestIndexLookupProcAndVar(t *testing.T) {
	ix := New()
	ix.IndexFile("a.tcl", "namespace eval ::app {\n  variable count 0\n  proc run {} {}\n}")

	run := ix.Lookup("::app::run")
	if len(run) != 1 || run[0].Kind != tcl.DefProc || run[0].File != "a.tcl" {
		t.Fatalf("::app::run lookup = %#v", run)
	}
	count := ix.Lookup("::app::count")
	if len(count) != 1 || count[0].Kind != tcl.DefNamespaceVar {
		t.Fatalf("::app::count lookup = %#v", count)
	}
}

func TestIndexSkipsLocals(t *testing.T) {
	ix := New()
	ix.IndexFile("a.tcl", "proc f {a} { set b 1 }")
	if locs := ix.Lookup("a"); len(locs) != 0 {
		t.Fatalf("param local should not be indexed: %#v", locs)
	}
	if locs := ix.Lookup("b"); len(locs) != 0 {
		t.Fatalf("set local should not be indexed: %#v", locs)
	}
	if locs := ix.Lookup("::f"); len(locs) != 1 {
		t.Fatalf("::f proc should be indexed: %#v", locs)
	}
}

func TestIndexLookupMissing(t *testing.T) {
	ix := New()
	if locs := ix.Lookup("::nope"); locs != nil {
		t.Fatalf("missing lookup should be nil, got %#v", locs)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/index/`
Expected: FAIL — compile error, the `index` package does not exist.

- [ ] **Step 3: Write minimal implementation**

Create `server/internal/index/index.go`:

```go
// Package index builds a workspace-wide, fully-qualified symbol table of TCL
// definitions across files, with incremental per-file updates.
package index

import "github.com/unknownbreaker/tcl-lsp/internal/tcl"

// Location is a single definition site.
type Location struct {
	File      string
	Name      string // fully-qualified name
	Kind      tcl.DefKind
	NameStart int
	NameEnd   int
}

// Index holds workspace-visible definitions (procs and namespace variables)
// keyed by fully-qualified name, plus each file's source for later analysis.
type Index struct {
	defsByName map[string][]Location // FQ name -> all definition sites
	fileDefs   map[string][]string   // file -> FQ names it defines (for removal)
	src        map[string]string     // file -> source text
}

// New returns an empty Index.
func New() *Index {
	return &Index{
		defsByName: map[string][]Location{},
		fileDefs:   map[string][]string{},
		src:        map[string]string{},
	}
}

// IndexFile records the workspace-visible definitions in src under path. Locals
// and global links are skipped (resolved frame-locally, not via the workspace
// table).
func (ix *Index) IndexFile(path, src string) {
	ix.src[path] = src
	for _, d := range tcl.FileDefs(src) {
		if d.Kind != tcl.DefProc && d.Kind != tcl.DefNamespaceVar {
			continue
		}
		ix.defsByName[d.Name] = append(ix.defsByName[d.Name], Location{
			File: path, Name: d.Name, Kind: d.Kind, NameStart: d.NameStart, NameEnd: d.NameEnd,
		})
		ix.fileDefs[path] = append(ix.fileDefs[path], d.Name)
	}
}

// Lookup returns all definition sites for a fully-qualified name (nil if none).
func (ix *Index) Lookup(name string) []Location {
	return ix.defsByName[name]
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/index/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add server/internal/index/
git commit -m "feat(index): workspace definition table with FQ-name lookup"
```

---

## Task 2: Incremental update — RemoveFile and idempotent re-index

**Files:**
- Modify: `server/internal/index/index.go`
- Modify: `server/internal/index/index_test.go`

- [ ] **Step 1: Write the failing test**

Add to `server/internal/index/index_test.go`:

```go
func TestIndexMultipleFilesSameName(t *testing.T) {
	ix := New()
	ix.IndexFile("a.tcl", "proc dup {} {}")
	ix.IndexFile("b.tcl", "proc dup {} {}")
	if locs := ix.Lookup("::dup"); len(locs) != 2 {
		t.Fatalf("expected 2 def sites for ::dup, got %#v", locs)
	}
}

func TestIndexReindexReplaces(t *testing.T) {
	ix := New()
	ix.IndexFile("a.tcl", "proc old {} {}")
	ix.IndexFile("a.tcl", "proc new {} {}") // re-index the same path
	if locs := ix.Lookup("::old"); len(locs) != 0 {
		t.Fatalf("old def should be gone after re-index: %#v", locs)
	}
	if locs := ix.Lookup("::new"); len(locs) != 1 {
		t.Fatalf("new def should be present: %#v", locs)
	}
}

func TestIndexRemoveFile(t *testing.T) {
	ix := New()
	ix.IndexFile("a.tcl", "proc dup {} {}")
	ix.IndexFile("b.tcl", "proc dup {} {}")
	ix.RemoveFile("a.tcl")
	locs := ix.Lookup("::dup")
	if len(locs) != 1 || locs[0].File != "b.tcl" {
		t.Fatalf("after removing a.tcl, expected only b.tcl: %#v", locs)
	}
	// fully removing the last definer deletes the key
	ix.RemoveFile("b.tcl")
	if locs := ix.Lookup("::dup"); locs != nil {
		t.Fatalf("expected nil after all definers removed, got %#v", locs)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/index/ -run "TestIndexReindex|TestIndexRemoveFile"`
Expected: FAIL — `RemoveFile` undefined; `TestIndexReindexReplaces` fails (old def still present, since IndexFile appends without clearing).

- [ ] **Step 3: Write minimal implementation**

In `server/internal/index/index.go`, add `RemoveFile` and make `IndexFile` clear the file first. Replace the start of `IndexFile`'s body so its first line is `ix.RemoveFile(path)`:

```go
func (ix *Index) IndexFile(path, src string) {
	ix.RemoveFile(path)
	ix.src[path] = src
	for _, d := range tcl.FileDefs(src) {
		if d.Kind != tcl.DefProc && d.Kind != tcl.DefNamespaceVar {
			continue
		}
		ix.defsByName[d.Name] = append(ix.defsByName[d.Name], Location{
			File: path, Name: d.Name, Kind: d.Kind, NameStart: d.NameStart, NameEnd: d.NameEnd,
		})
		ix.fileDefs[path] = append(ix.fileDefs[path], d.Name)
	}
}

// RemoveFile drops all definitions and stored source contributed by path.
func (ix *Index) RemoveFile(path string) {
	for _, name := range ix.fileDefs[path] {
		locs := ix.defsByName[name]
		kept := locs[:0]
		for _, l := range locs {
			if l.File != path {
				kept = append(kept, l)
			}
		}
		if len(kept) == 0 {
			delete(ix.defsByName, name)
		} else {
			ix.defsByName[name] = kept
		}
	}
	delete(ix.fileDefs, path)
	delete(ix.src, path)
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/index/`
Expected: PASS (all index tests).

- [ ] **Step 5: Commit**

```bash
git add server/internal/index/
git commit -m "feat(index): incremental RemoveFile and idempotent re-index"
```

---

## Task 3: File enumeration and source access

**Files:**
- Modify: `server/internal/index/index.go`
- Modify: `server/internal/index/index_test.go`

- [ ] **Step 1: Write the failing test**

Add to `server/internal/index/index_test.go`:

```go
import (
	"reflect"
	"testing"

	"github.com/unknownbreaker/tcl-lsp/internal/tcl"
)
```

(Replace the existing import block with the one above — it adds `reflect`.)

```go
func TestIndexFilesAndSource(t *testing.T) {
	ix := New()
	ix.IndexFile("b.tcl", "proc b {} {}")
	ix.IndexFile("a.tcl", "proc a {} {}")

	if files := ix.Files(); !reflect.DeepEqual(files, []string{"a.tcl", "b.tcl"}) {
		t.Fatalf("Files() = %#v, want sorted [a.tcl b.tcl]", files)
	}
	if got := ix.Source("a.tcl"); got != "proc a {} {}" {
		t.Fatalf("Source(a.tcl) = %q", got)
	}
	ix.RemoveFile("a.tcl")
	if got := ix.Source("a.tcl"); got != "" {
		t.Fatalf("Source after remove = %q, want empty", got)
	}
	if files := ix.Files(); !reflect.DeepEqual(files, []string{"b.tcl"}) {
		t.Fatalf("Files() after remove = %#v", files)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/index/ -run TestIndexFilesAndSource`
Expected: FAIL — `Files`/`Source` undefined.

- [ ] **Step 3: Write minimal implementation**

In `server/internal/index/index.go`, add `import "sort"` (grouped with the existing import) and the accessors:

```go
// Files returns the indexed file paths, sorted for deterministic iteration.
func (ix *Index) Files() []string {
	out := make([]string, 0, len(ix.src))
	for p := range ix.src {
		out = append(out, p)
	}
	sort.Strings(out)
	return out
}

// Source returns the stored source for a file ("" if not indexed).
func (ix *Index) Source(path string) string {
	return ix.src[path]
}
```

The import block becomes:

```go
import (
	"sort"

	"github.com/unknownbreaker/tcl-lsp/internal/tcl"
)
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/index/`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add server/internal/index/
git commit -m "feat(index): file enumeration and source access"
```

---

## Task 4: Directory indexing (filesystem walk)

**Files:**
- Modify: `server/internal/index/index.go`
- Modify: `server/internal/index/index_test.go`

- [ ] **Step 1: Write the failing test**

Add to `server/internal/index/index_test.go`:

```go
import (
	"os"
	"path/filepath"
	"reflect"
	"testing"

	"github.com/unknownbreaker/tcl-lsp/internal/tcl"
)
```

(Replace the import block again to add `os` and `path/filepath`.)

```go
func writeFile(t *testing.T, dir, rel, content string) {
	t.Helper()
	p := filepath.Join(dir, rel)
	if err := os.MkdirAll(filepath.Dir(p), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestIndexDir(t *testing.T) {
	dir := t.TempDir()
	writeFile(t, dir, "x.tcl", "proc x {} {}")
	writeFile(t, dir, "sub/y.tcl", "namespace eval ::n { proc y {} {} }")
	writeFile(t, dir, "readme.md", "not tcl")

	ix := New()
	if err := ix.IndexDir(dir); err != nil {
		t.Fatalf("IndexDir error: %v", err)
	}
	if locs := ix.Lookup("::x"); len(locs) != 1 {
		t.Fatalf("::x not indexed from dir: %#v", locs)
	}
	if locs := ix.Lookup("::n::y"); len(locs) != 1 {
		t.Fatalf("::n::y not indexed from subdir: %#v", locs)
	}
	if files := ix.Files(); len(files) != 2 {
		t.Fatalf("expected 2 .tcl files indexed (md skipped), got %#v", files)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/index/ -run TestIndexDir`
Expected: FAIL — `IndexDir` undefined.

- [ ] **Step 3: Write minimal implementation**

In `server/internal/index/index.go`, expand the imports and add `IndexDir`:

```go
import (
	"io/fs"
	"os"
	"path/filepath"
	"sort"
	"strings"

	"github.com/unknownbreaker/tcl-lsp/internal/tcl"
)
```

```go
// IndexDir walks root and indexes every *.tcl file found (recursively). It
// returns the first error encountered while walking or reading.
func (ix *Index) IndexDir(root string) error {
	return filepath.WalkDir(root, func(p string, d fs.DirEntry, err error) error {
		if err != nil {
			return err
		}
		if d.IsDir() || !strings.HasSuffix(p, ".tcl") {
			return nil
		}
		b, err := os.ReadFile(p)
		if err != nil {
			return err
		}
		ix.IndexFile(p, string(b))
		return nil
	})
}
```

- [ ] **Step 4: Run the full suite**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server vet ./...`
Then: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./...`
Expected: clean vet; all tests PASS (tcl + index packages).

- [ ] **Step 5: Commit**

```bash
git add server/internal/index/
git commit -m "feat(index): recursive directory indexing of *.tcl files"
```

---

## Done criteria for Plan 8

- `go vet ./...` clean; `go test ./...` all pass.
- `index.Index` provides: `IndexFile(path, src)` (records procs + namespace vars by FQ name; idempotent re-index), `RemoveFile(path)`, `Lookup(fqName) []Location` (all sites; nil if none), `Files()` (sorted), `Source(path)`, and `IndexDir(root)` (recursive `*.tcl` walk). Locals/global-links are excluded.

**Next:** Plan 9 — the resolver + goto-definition / goto-reference core: classify the symbol at a position (reusing the parser), compute its FQ candidates (command vs variable algorithms, namespace path, frame-local handling), look up definitions in the index, and for references scan the workspace. Then Plan 10 — LSP shell + editor clients + binaries.
