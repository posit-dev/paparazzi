# Phase note: remaining expectations + waits (kata paparazzi#v6ar)

Mechanism decisions, resolved before code. Durable requirements live in
`.agents/SPEC.md` ("Expectations", "Waits"); this note holds the
mechanism-level choices for this phase only. Reuses the retry core from
`.agents/phases/expectation-core.md` (expect_retry, expect_impl, the
testthat bridge, the classed failure format) — nothing here reinvents it.

## Decisions

- **Entry points.** Every element-level expectation goes through the
  existing `expect_impl()` (resolve per attempt, check in R, retry,
  classed failure). State checks and `pz_expect_class()` reuse
  `check_visible()`'s shape via a new shared `check_state(js, not,
  seen)` closure (visible now delegates to it; behavior unchanged).
  `pz_expect_value()`/`pz_expect_attr()` reuse the text check via
  `check_text_like(js, values, match, not)` — same pairwise vector
  semantics, NA-tolerant (a missing value/attribute is NA, satisfies
  nothing). The classed-failure tail moves to `expect_report()`,
  shared by `expect_impl()` and the new page-level
  `expect_page_impl()` (url/title: no target to resolve, scope never
  probed, works from any context).
- **JS predicates.** enabled `!el.matches(':disabled')` (inherits
  disabled fieldsets), focused `document.activeElement === el`,
  checked `el.matches(':checked')`, in-viewport strict rect/viewport
  overlap (`bottom>0 && right>0 && top<innerHeight && left<innerWidth`),
  value `get_value_js` (get.R), attr `getAttribute(<json name>)`
  (jsonlite-encoded, like pz_get_attr), class
  `classList.contains(<json class>)`. `pz_expect_js()` wraps the
  user's `expr` as `const predicate = <expr>` and maps
  `!!predicate(el)` per match; a throwing predicate is a
  `paparazzi_error_js`, not a failed poll.
- **Match modes** follow the core task exactly:
  `expect_text_matches()` (contains/exact/regex) over
  whitespace-collapsed values, value and attr share text's pairwise
  vector semantics; attr defaults to `match = "exact"`, value follows
  text's `"contains"` default; url/title take a single string (no
  pairwise meaning on one page value) with text's modes and collapse.
- **wait_for_js.** `pz_poll()` around one `pz_js()` per attempt with
  per-eval timeout = the wait budget, evaluating
  `Promise.resolve(<expr>).then((v) => !!v)` so promise-returning and
  truthy-valued expressions work without an R-side truthiness table.
- **wait_for_stable sampling.** One sample per poll attempt:
  re-resolve (`loc_resolve_once`; first sample auto-waits via
  `loc_resolve()`, scoped `target = NULL` uses the pinned set probed
  per sample), read one `callFunctionOn` mapping every match to a
  string — `String(el[prop])` (null/undefined empty) or rect joined
  with rounded x/y/width/height for `prop = "rect"` — then join with
  the count. `prop` is a single JS identifier or `"rect"` (regex
  check; anything freer is `pz_wait_for_js`). The pass condition lives
  in a `pz_poll()` closure: a changed sample resets `stable_since`;
  pass when `now - stable_since >= for_ms`. Interval
  `min(0.1, max(for_ms / 2000, 0.01))`. Zero matches read as a constant
  sample. The auto-wait and the stability window each get the full
  `timeout` budget (documented).
- **wait_for_navigation sequence.** Snapshot one evaluate:
  `JSON.stringify([document.readyState, performance.timeOrigin])`.
  Poll `readyState === 'complete' && (timeOrigin differs from the
  snapshot || readyState wasn't complete at snapshot)`. The
  readyState disjunct covers a snapshot taken while the new document
  is already loading (e.g. the call came late); mid-swap evaluate
  failures are "not yet", not errors. On success: release the object
  group wholesale, then return the root context (like `pz_find_reset()`;
  the caller's context is never mutated). `wait = "none"` skips the
  poll; "auto" resolves to "load" like `pz_open()`. Known hole,
  accepted and documented: a navigation that fully commits AND loads
  before the wait starts is indistinguishable from no navigation and
  times out — post-hoc detection can't do better without the actions
  recording state (a cross-file flag; tripwire, not built).
- **No element-state wait.** The wait docs point at
  `pz_expect_visible()` / `pz_expect_hidden()` / `pz_expect_exists(not
  = TRUE)`, which already retry.
- **Fixtures.** New `tests/testthat/fixtures/state.html` (controls,
  focus targets, checkboxes, viewport positions, values/attrs/classes,
  scroll box, late-settling timers), `waits.html` (a 50 ms text ticker
  that stops after 1 s, a 300 ms × 4 keyframe bounce, an endless
  animation, a never-settling element, `#nav-link`), and
  `nav-target.html` (navigation landing page). Helper:
  `tests/testthat/helper-state-waits.R` (`local_state_page()`,
  `local_waits_page()`), built on the shared `helper-page.R` helpers.

## Handoff log

(newest first; three lines per session: landed / next / provisional)

- 2026-09-25 (review fixes): landed the dead-context mapping (d8a7a2f,
  roborev 1248): a destroyed-context CDP failure after a real
  navigation now maps to the classed paparazzi_error_detached instead
  of a raw chromote error, and both navigation tests assert the class.
  Next: none — roborev 1248's findings for this phase are all
  dispositioned (accepted ones landed here; nav-evidence and stability
  budget landed earlier on this branch).
  Provisional: none.
