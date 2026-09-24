# Phase note: element specs + resolution engine (kata paparazzi#a3vj)

Mechanism decisions for the element-spec/resolution task, resolved before
code. Durable requirements live in `.agents/SPEC.md` (sections "Element
specs", "Scoping > Resolution", "Multiple matches"); this note holds
mechanism-level choices and session handoffs for this phase only.

## Decisions

- **Spec object.** `pz_loc(css, ..., has_text = NULL, which = NULL,
  within = NULL)` returns an S3 object of class `paparazzi_loc`: a
  list with fields `css`, `has_text`, `which`, `within` (`within` is
  itself a `paparazzi_loc` or `NULL`). Page-independent; nothing about a
  session is captured. `print` method shows the target description
  (below).
- **Validation.** `css`/`has_text` via `check_string()`; `which` is
  `NULL`, `"first"`, `"last"`, or a positive whole number
  (`check_number_whole(min = 1)`); `within` is promoted with `as_loc()`
  (spec or bare string). `...` checked empty.
- **Promotion.** Internal `as_loc(target, arg, call)`: bare string ->
  `pz_loc(string)`, `paparazzi_loc` -> as-is, anything else ->
  `stop_input_type()`. Internal `as_loc_list()`: a bare spec/string
  becomes a one-element list; a list may mix specs and strings. Lists
  are the union form (screenshots land in a later task; the machinery
  accepts unions now).
- **`has_text` semantics (provisional).** Substring match on
  `textContent` with whitespace collapsed (same rule the SPEC gives
  `pz_expect_text()`), case-sensitive. If the expectations task settles
  on case-insensitivity, change it there and here together.
- **`which` semantics.** Applied after css + has_text filtering.
  `"first"` = 1, `"last"` = n, integer = that 1-based position. An
  out-of-range `which` means *no match*, not an error — lazy resolution
  keeps auto-waiting until timeout, same as any unmatched spec.
- **`within` semantics.** The element must be a descendant of *any*
  element matched by the `within` spec, resolved recursively (a `within`
  spec may itself have `has_text`/`which`/`within`) in the same scope.
  If the `within` spec matches nothing, the whole spec matches nothing
  (auto-wait continues).
- **Resolution is lazy.** Internal `loc_resolve(ctx, target, ...,
  timeout = NULL, multiple = c("error", "all"))` promotes `target`
  (spec, string, or list), then auto-waits: poll resolve-once until at
  least one element matches or the timeout elapses. Polling uses
  `pz_poll()` (child-loop pump). Each individual JS call passes
  `timeout_ = ctx$page$default_timeout` explicitly — never chromote's
  implicit default — and NOT the remaining wait budget: retry budget
  and per-command timeout stay separate (design note from
  roborev 1217 / paparazzi#8kxx). A chromote command timeout is
  re-raised as `paparazzi_error_timeout` naming the target, with the
  chromote error as parent (same mapping as `pz_js()`). `timeout = 0`
  is "check once":
  `pz_poll()` already evaluates `fn()` once before the deadline check,
  so this falls out naturally — add a test pinning it down.
- **Resolve-once.** `loc_resolve_once(ctx, expr, description, call)`
  performs one resolution attempt and returns a possibly-empty
  `paparazzi_elements` (count 0, no handle) — zero matches is a valid
  result, which `pz_get_count()` and the expectation retry core
  (8kxx) need. `loc_resolve()` polls it. The resolver JS returns
  `null` for an empty set, so an empty poll costs one CDP round trip
  and never holds an empty remote object.
- **Result handle.** One resolution = one JS evaluation returning an
  array of elements with `returnByValue = FALSE`, i.e. a single remote
  object (objectId) for the whole matched set. R side stores an S3
  `paparazzi_elements`: the objectId, the match count, the formatted
  target description, and the page. Individual element handles are
  fetched later by actions via `Runtime.callFunctionOn` on the array.
  `release_elements()` frees the objectId via
  `Runtime$releaseObjectById`; tests must release what they resolve.
  The per-page object-group lifecycle wrapper is the `pz_find*()`
  pinning task's problem — do not build it here.
- **Scope seam.** The resolver JS takes its roots as an argument, so
  the same function object covers every rooting. Today the only root
  is `document`, reached via `Runtime$evaluate`; scoped contexts
  (non-empty `ctx$scope`, arriving with the pinning task) will invoke
  the same JS through `Runtime$callFunctionOn` with pinned element
  handles as the root argument.
- **Overlay exclusion (forward contract).** The recording overlay will
  live in a shadow root whose host element is
  `<div id="paparazzi-overlay-root">`. The resolver excludes the host
  and anything inside it: filter `el.closest("#paparazzi-overlay-root")
  !== null`. The overlay itself lands later; the fixture carries a
  decoy `#paparazzi-overlay-root` element now to prove exclusion.
- **Multi-match machinery.** `loc_resolve(..., multiple = "error")`
  aborts with class `paparazzi_error_multiple` when the resolved set
  has more than one element: message shows the count and the full
  target description, with a hint to narrow via `has_text`/`which`/
  `within`. `multiple = "all"` returns the whole set. Each future
  action/getter picks its mode; there is no `strict` argument (SPEC).
- **Timeout error.** Class `paparazzi_error_timeout` (existing): after
  the budget, abort with the time waited and the full target
  description.
- **Target description.** Internal `format_loc(loc) -> string`, e.g.
  `` `.shiny-tool-request` (has_text: "get_weather", which: last,
  within: `.chat`) `` — backticked css, qualifiers in fixed order
  has_text/which/within, `within` formatted recursively. Reused by the
  timeout error, the multi-match error, the `paparazzi_loc` print
  method, and (later) expectation failure messages and the
  detached-scope error (which is why the format follows the SPEC's
  scope-error example).
- **File layout.** `R/loc.R` (`pz_loc()`, `as_loc()`, `as_loc_list()`,
  `format_loc()`, print method). `R/resolve.R` (JS resolver source,
  `loc_resolve()`, `release_elements()`). Tests mirror:
  `tests/testthat/test-loc.R` (construction, validation, promotion,
  description formatting — no browser needed) and
  `tests/testthat/test-resolve.R` (resolution against a fixture, via
  the existing `local_page()` helper).
- **Fixture.** New `tests/testthat/fixtures/elements.html`: nested
  containers, repeated classes, text variants, and a
  `#paparazzi-overlay-root` decoy containing elements that would
  otherwise match — enough to exercise css/has_text/which/within,
  unions, multi-match, overlay exclusion, and timeout.

## Handoff log

(newest first; three lines per session: landed / next / provisional)

- 2026-09-24 (close): landed pz_loc + promotion/unions (138cf79),
  the lazy resolution engine (0244b73), and review fixes (1ec3c36:
  plain-text timeout messages, loc_resolve_once + null-for-empty,
  explicit per-command timeout_ + classed mapping, empty-list/format
  guards, DOM-change laziness tests). 201 tests green. roborev jobs
  1219 (claude-code) and 1220 (codex) both closed; dispositions on
  the kata issue. Next: 8kxx (expectation core) per the epic order —
  it should build its retry on loc_resolve_once(). Provisional:
  `has_text` case-sensitivity is pinned by tests but may be revisited
  with pz_expect_text semantics.
- 2026-09-24 (start): claimed a3vj; harness green at cb5570c (111
  tests, devtools::test). Blocker qtpz closed. Decisions above resolved
  before code. Next: implement `R/loc.R` + `R/resolve.R` + tests.
  Provisional: `has_text` case-sensitive; default timeout stays 10s.
