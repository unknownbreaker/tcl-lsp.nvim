# Real-world Itcl/Rivet fixtures

These files are **verbatim, unmodified** excerpts of real production codebases,
vendored so the resolver/index/symbol tests exercise the idioms that real TCL/RVT
code actually uses (not hand-authored synthetic shapes). Each was confirmed
structurally complete with `tclsh` (`info complete`) after copying.

Do not edit these files. Re-vendor from upstream if they need updating.

| File | Source (repo @ commit : path) | Why it's here |
| --- | --- | --- |
| `rweb_content.tcl` | `mxmanghi/rivetweb @ 13abf80e825b0a6247ad60a3f96d07c52745f3db : tcl/rweb_content.tcl` | Base Itcl class: `private variable`, `public method`/`protected method` (inline + abstract-no-body), `constructor` with a default arg, `destructor`, external `::itcl::body` definitions, `$this method` calls, `::rivet::*`/`::itcl::delete` commands. |
| `rweb_page.tcl` | `mxmanghi/rivetweb @ 13abf80e825b0a6247ad60a3f96d07c52745f3db : tcl/rweb_page.tcl` | Subclass: `inherit RWContent`, the three-part `constructor args {Base::constructor …} {body}`, `protected proc`, many `::itcl::body RWPage::m` external bodies, base-qualified `RWContent::m` calls. |
| `display_direct.rvt` | `flightaware/speedtables @ 0fe25e1569c936e2a1bb477b7afecb8a74aad976 : ctables/demos/display_direct.rvt` | The canonical Tier-3 demo page: `set display [::STDisplay #auto …]` then `$display show` / `$display field`, plus cross-file `source` and `[u_passwd create #auto]`. |

## What these proved / now guard

The survey that produced this corpus (`research/07-realworld-itcl-survey.md`)
found that the dominant real-world member form — `public method` /
`protected method` / `private variable` / `private common` — was **not parsed**
(only bare `method`/`variable` were). These fixtures pin the fix that added
access-modifier support, plus the three-part constructor's base-chain call and
the `$obj method` shape on a real page.
