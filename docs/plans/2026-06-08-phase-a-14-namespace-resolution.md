# Phase A — Plan 14: namespace path + import resolution

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Resolve unqualified command references through `namespace path` and `namespace import`, so a command brought into a namespace via those mechanisms links to its real definition.

**Architecture:** Extends the `index` and `resolve` packages. The index already parses per-file namespace declarations capability (`tcl.FileNamespaces`, Plan 7) but doesn't store them; this plan stores them and exposes a merged per-namespace view. The resolver's command candidates then include, in TCL precedence order: current namespace → imported names → `namespace path` entries → global.

**Resolution rules (from `research/02-namespace-resolution.md`):**
- `namespace path {a b}` in namespace N → an unqualified command in N is also searched in `a`, `b` (in order).
- `namespace import ::p::pub` → `pub` referenced in N resolves to the source `::p::pub`. A glob `::p::*` → `name` in N resolves to `::p::name` (if defined).
- Variables are unaffected (`namespace path`/`import` apply to commands only — research F-E).

**Tech Stack:** Go 1.23+ (local 1.26.4), `testing`.

---

## File structure

- Modify: `server/internal/index/index.go` — store per-file namespace info; add `Namespace(ns)` accessor.
- Modify: `server/internal/index/index_test.go`
- Modify: `server/internal/resolve/resolve.go` — command candidates use path + imports.
- Modify: `server/internal/resolve/resolve_test.go`

---

## Task 1: Store and merge namespace declarations in the index

**Files:**
- Modify: `server/internal/index/index.go`
- Modify: `server/internal/index/index_test.go`

- [ ] **Step 1: Write the failing test**

Add to `server/internal/index/index_test.go`:

```go
func TestIndexNamespacePathAndImports(t *testing.T) {
	ix := New()
	ix.IndexFile("a.tcl", "namespace eval ::app {\n  namespace path ::lib\n  namespace import ::p::pub\n}")
	path, imports := ix.Namespace("::app")
	if !reflect.DeepEqual(path, []string{"::lib"}) {
		t.Fatalf("path = %#v, want [::lib]", path)
	}
	if !reflect.DeepEqual(imports, []string{"::p::pub"}) {
		t.Fatalf("imports = %#v, want [::p::pub]", imports)
	}
}

func TestIndexNamespaceMergedAcrossFiles(t *testing.T) {
	ix := New()
	ix.IndexFile("a.tcl", "namespace eval ::app { namespace import ::p::a }")
	ix.IndexFile("b.tcl", "namespace eval ::app { namespace import ::q::b }")
	_, imports := ix.Namespace("::app")
	if !reflect.DeepEqual(imports, []string{"::p::a", "::q::b"}) {
		t.Fatalf("imports = %#v, want union sorted by file", imports)
	}
}

func TestIndexNamespaceClearedWithFile(t *testing.T) {
	ix := New()
	ix.IndexFile("a.tcl", "namespace eval ::app { namespace path ::lib }")
	ix.RemoveFile("a.tcl")
	if path, _ := ix.Namespace("::app"); path != nil {
		t.Fatalf("namespace info should be gone after RemoveFile: %#v", path)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/index/ -run TestIndexNamespace`
Expected: FAIL — `Namespace` undefined.

- [ ] **Step 3: Write minimal implementation**

In `server/internal/index/index.go`:

(a) Add a field to the `Index` struct (after `src`):

```go
	fileNS map[string]map[string]*tcl.NamespaceInfo // file -> (ns name -> decls)
```

(b) Initialize it in `New`:

```go
	return &Index{
		defsByName: map[string][]Location{},
		fileDefs:   map[string][]string{},
		src:        map[string]string{},
		fileNS:     map[string]map[string]*tcl.NamespaceInfo{},
	}
```

(c) In `IndexFile`, after `ix.src[path] = content`, store the namespace decls:

```go
	ix.fileNS[path] = tcl.FileNamespaces(content)
```

(d) In `RemoveFile`, add a delete alongside the others:

```go
	delete(ix.fileNS, path)
```

(e) Add the accessor (near `Source`):

```go
// Namespace returns the merged command-search path and import source patterns
// declared for ns across the workspace, deduplicated and ordered by file then
// declaration order. Used for command resolution (namespace path / import).
// Variables are unaffected by these declarations.
func (ix *Index) Namespace(ns string) (path []string, imports []string) {
	files := make([]string, 0, len(ix.fileNS))
	for f := range ix.fileNS {
		files = append(files, f)
	}
	sort.Strings(files)

	seenP, seenI := map[string]bool{}, map[string]bool{}
	for _, f := range files {
		info := ix.fileNS[f][ns]
		if info == nil {
			continue
		}
		for _, p := range info.Path {
			if !seenP[p] {
				seenP[p] = true
				path = append(path, p)
			}
		}
		for _, im := range info.Imports {
			if !seenI[im] {
				seenI[im] = true
				imports = append(imports, im)
			}
		}
	}
	return path, imports
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/index/`
Expected: PASS (all index tests).

- [ ] **Step 5: Commit**

```bash
git add server/internal/index/
git commit -m "feat(index): store and expose merged namespace path/import declarations"
```

---

## Task 2: Command resolution through namespace path + imports

**Files:**
- Modify: `server/internal/resolve/resolve.go`
- Modify: `server/internal/resolve/resolve_test.go`

- [ ] **Step 1: Write the failing test**

Add to `server/internal/resolve/resolve_test.go`:

```go
func TestDefinitionViaNamespacePath(t *testing.T) {
	ix := index.New()
	ix.IndexFile("lib.tcl", "namespace eval ::lib {\n  proc helper {} {}\n}")
	src := "namespace eval ::user {\n  namespace path ::lib\n  helper\n}"
	ix.IndexFile("user.tcl", src)
	r := New(ix)

	off := strings.Index(src, "\n  helper") + 3 // the `helper` call
	locs := r.Definition("user.tcl", src, off)
	if len(locs) != 1 || locs[0].Name != "::lib::helper" {
		t.Fatalf("via namespace path = %#v", locs)
	}
}

func TestDefinitionViaNamespaceImport(t *testing.T) {
	ix := index.New()
	ix.IndexFile("p.tcl", "namespace eval ::provider {\n  namespace export pub\n  proc pub {} {}\n}")
	src := "namespace eval ::consumer {\n  namespace import ::provider::pub\n  pub\n}"
	ix.IndexFile("c.tcl", src)
	r := New(ix)

	off := strings.Index(src, "\n  pub\n") + 3 // the bare `pub` call
	locs := r.Definition("c.tcl", src, off)
	if len(locs) != 1 || locs[0].Name != "::provider::pub" {
		t.Fatalf("via namespace import = %#v", locs)
	}
}

func TestDefinitionViaGlobImport(t *testing.T) {
	ix := index.New()
	ix.IndexFile("p.tcl", "namespace eval ::provider {\n  namespace export *\n  proc tool {} {}\n}")
	src := "namespace eval ::consumer {\n  namespace import ::provider::*\n  tool\n}"
	ix.IndexFile("c.tcl", src)
	r := New(ix)

	off := strings.Index(src, "\n  tool\n") + 3
	locs := r.Definition("c.tcl", src, off)
	if len(locs) != 1 || locs[0].Name != "::provider::tool" {
		t.Fatalf("via glob import = %#v", locs)
	}
}

func TestDefinitionCurrentNamespaceBeatsPath(t *testing.T) {
	ix := index.New()
	ix.IndexFile("lib.tcl", "namespace eval ::lib { proc helper {} {} }")
	src := "namespace eval ::user {\n  namespace path ::lib\n  proc helper {} {}\n  helper\n}"
	ix.IndexFile("user.tcl", src)
	r := New(ix)

	off := strings.LastIndex(src, "helper") // the call, after the local proc def
	locs := r.Definition("user.tcl", src, off)
	if len(locs) != 1 || locs[0].Name != "::user::helper" {
		t.Fatalf("current ns should beat path: %#v", locs)
	}
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/resolve/ -run "TestDefinitionVia|TestDefinitionCurrentNamespaceBeats"`
Expected: FAIL — command candidates ignore namespace path/imports today.

- [ ] **Step 3: Write minimal implementation**

In `server/internal/resolve/resolve.go`:

(a) Change `candidates` to call the new method, and replace the free `commandCandidates` function with a method that consults the index. Replace the existing `candidates` and `commandCandidates`:

```go
// candidates returns the fully-qualified names to look up for a reference.
func (r *Resolver) candidates(ref *tcl.ContextRef) []string {
	name := ref.Ref.Name
	ns := ref.Namespace
	if ref.Ref.Kind == tcl.RefCommand {
		return r.commandCandidates(name, ns)
	}
	return variableCandidates(name, ns, ref.Frame)
}

// commandCandidates returns the FQ command names to try, in TCL precedence
// order: current namespace, imported names, namespace-path entries, then global.
// A qualified name resolves directly.
func (r *Resolver) commandCandidates(name, ns string) []string {
	if isQualified(name) {
		return []string{qualify(name, ns)}
	}
	cands := []string{qualify(name, ns)} // current namespace

	path, imports := r.ix.Namespace(ns)
	// Imported commands behave like commands in the current namespace.
	for _, imp := range imports {
		if srcNs, last, ok := splitLastSegment(imp); ok && (last == name || last == "*") {
			if srcNs == "::" {
				cands = append(cands, "::"+name)
			} else {
				cands = append(cands, srcNs+"::"+name)
			}
		}
	}
	// namespace path entries (already fully qualified).
	for _, p := range path {
		cands = append(cands, p+"::"+name)
	}
	// global fallback.
	if ns != "::" {
		cands = append(cands, "::"+name)
	}
	return dedup(cands)
}

// splitLastSegment splits a qualified name into (namespace, lastSegment), e.g.
// "::p::pub" -> ("::p", "pub") and "::pub" -> ("::", "pub"). Returns ok=false
// when there is no "::" separator.
func splitLastSegment(qname string) (nsPart, last string, ok bool) {
	i := strings.LastIndex(qname, "::")
	if i < 0 {
		return "", "", false
	}
	nsPart = qname[:i]
	if nsPart == "" {
		nsPart = "::"
	}
	return nsPart, qname[i+2:], true
}

func dedup(in []string) []string {
	seen := make(map[string]bool, len(in))
	out := in[:0]
	for _, s := range in {
		if !seen[s] {
			seen[s] = true
			out = append(out, s)
		}
	}
	return out
}
```

(Keep `isQualified`, `qualify`, and `variableCandidates` as they are. Delete the old free `commandCandidates` function — its logic is now in the method.)

- [ ] **Step 4: Run test to verify it passes**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./internal/resolve/`
Expected: PASS (all resolve tests, including the pre-existing ones — current-ns/global behavior is preserved).

- [ ] **Step 5: Commit**

```bash
git add server/internal/resolve/
git commit -m "feat(resolve): resolve commands via namespace path and imports"
```

---

## Task 3: References through namespace path/import + integration

**Files:**
- Modify: `server/internal/resolve/resolve_test.go`

- [ ] **Step 1: Write the test**

Add to `server/internal/resolve/resolve_test.go`:

```go
func TestReferencesViaNamespaceImport(t *testing.T) {
	ix := index.New()
	pSrc := "namespace eval ::provider {\n  namespace export pub\n  proc pub {} {}\n}"
	ix.IndexFile("p.tcl", pSrc)
	ix.IndexFile("c.tcl", "namespace eval ::consumer {\n  namespace import ::provider::pub\n  pub\n}")
	r := New(ix)

	// From the definition of ::provider::pub, references should include the
	// imported call in c.tcl (which resolves to ::provider::pub).
	off := strings.Index(pSrc, "proc pub") + 5 // the `pub` proc name
	locs := r.References("p.tcl", pSrc, off)
	found := false
	for _, l := range locs {
		if l.File == "c.tcl" {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected the imported call in c.tcl among references: %#v", locs)
	}
}
```

- [ ] **Step 2: Run the full suite**

Run: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server vet ./...`
Then: `go -C /Users/robertyang/Repos/FlightAware/2tcl-lsp.nvim/server test ./...`
Expected: clean vet; all tests PASS (tcl + index + resolve + lsp + cmd).

- [ ] **Step 3: Commit**

```bash
git add server/internal/resolve/
git commit -m "test(resolve): references resolve through namespace imports"
```

---

## Done criteria for Plan 14

- `go vet ./...` clean; `go test ./...` all pass.
- Unqualified command references resolve through `namespace path` (each entry searched, in order) and `namespace import` (exact and glob `*`), in TCL precedence order (current namespace → imports → path → global), for both goto-definition and goto-references. Variables are unaffected.

**Note:** `namespace import` resolution targets the source command (`::provider::pub`); it does not require the source to be re-exported, and export-pattern matching for globs is approximated by "the source command exists in the index". Chained re-imports are not followed (a documented limitation).

