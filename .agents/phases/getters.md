# Phase note: pz_get_* getters (kata paparazzi#5cqf)

Mechanism decisions for the getters task, resolved before code.
Durable requirements live in `.agents/SPEC.md` (section "Getters");
this note holds mechanism-level choices and session handoffs for this
phase only. Builds on the resolution engine
(`.agents/phases/element-specs-resolution.md`) and the expectation core
(`.agents/phases/expectation-core.md`).

## Decisions

- **Driver.** Internal `get_impl(ctx, target, timeout, read, call)`:
  resolves with `loc_resolve(multiple = "all")` (auto-waits for >= 1
  match, errors after the timeout with the existing
  `paparazzi_error_timeout`), runs `read(els)` to pull values into R,
  releases the handle via `on.exit(release_elements())`. Getters never
  see an empty set, so `read` may assume a live handle.
- **Nullable reads.** `els_call()` (R/expect.R) unlists, and unlist
  silently drops NULLs -- fatal for `pz_get_attr()` (missing attr ->
  JS null) and `pz_get_value()` (non-form element -> undefined). Split
  the CDP call out of `els_call()` into `els_values(els, js, call)`
  (same timeout/error mapping, returns the raw result list);
  `els_call()` becomes `unlist(els_values(...))`. get.R converts with
  `chr_or_na()` (NULL -> NA_character_). Behavior of els_call() for
  existing callers is unchanged.
- **target = NULL.** Same provisional rule as expectations: the root
  context resolves to `document.body`. Extract the expr/description
  branch out of `expect_impl()` into `target_resolver_expr(target,
  call)` in R/resolve.R (returns list(expr, description)); both
  expect_impl() and get_impl() use it, so the scoping task revisits
  one place. expect_impl() behavior stays byte-identical.
- **pz_get_count().** No auto-wait: one `loc_resolve_once()`, return
  `els$count` (integer), release. 0 is a valid answer.
- **pz_get_text(raw = FALSE).** Default collapses with `collapse_ws()`
  from R/expect.R -- which TRIMS. The resolver's `has_text` collapse
  (R/resolve.R) does not trim; the expectation-core handoff flagged
  unifying these. Getters unify on collapse_ws(); the resolver is left
  as-is (trim-insensitive `indexOf` match makes the difference
  unobservable there) -- carried as provisional.
- **pz_get_value().** JS `el.value === undefined ? null : String(el.value)`;
  undefined (non-form elements) becomes NA_character_ via chr_or_na().
- **pz_get_attr(name).** JS `el.getAttribute(name)`; null ->
  NA_character_.
- **pz_get_html().** `el.outerHTML`, never null; els_call() is fine.
- **pz_get_elements().** One els_values() call mapping to objects
  `{tag, id, class, text}`; built into a tibble in R. tag is
  lowercased in JS; id/class are NA when the attribute is absent
  (consistent with pz_get_attr); text is collapse_ws(textContent).
- **pz_get_rect().** Thin wrapper: get_impl() with `read = el_rects`.
- **`element` list-column.** Tibble getters (rect, elements; style
  lands with the style task) carry an `element` column LAST, a list of
  NULLs here -- the SCOPING task replaces the stub with pinned
  per-match contexts and the `<pz_ctx>` pillar label. Kept as a
  factory `new_get_tibble(..., n)` so the swap touches one function.
  Documented on each getter as reserved/not yet populated.
- **pz_get_url() / pz_get_title().** Page-level, signature `(ctx)`
  only (SPEC-confirmed): thin wrappers over pz_js(ctx, "location.href")
  / pz_js(ctx, "document.title").
- **Validation.** ctx via check_context; dots empty; name via
  check_string; raw via check_bool; timeout via resolve_timeout.
- **File layout.** R/get.R (driver + nine exports); tests mirror in
  tests/testthat/test-get.R. New fixture
  tests/testthat/fixtures/getters.html; helper-page.R gains
  getters_fixture_file()/local_getters_page() by APPEND only
  (elements.html/geometry.html untouched -- their counts are pinned).
- **Fixture plan** (both the fixture author and the test author work
  from this exact shape):
  - `<title>Getters fixture</title>`; body `margin: 0`.
  - Three `p.item`: "first   item" (extra inner spaces), "second\n    item"
    (newline + indent), "third item" -- collapse tests + 3-match counts.
  - `input.field#field-a` value "alpha"; `input.field` with no value
    attribute (property is ""); `div.field` (value undefined -> NA).
  - Two `a.link`: first has `data-role="primary"`, second lacks
    data-role (NA test).
  - `div#box1` absolute at left 10 / top 20 / 100x40; `div#box2` at
    left 50 / top 100 / 200x80 (exact rect rows).
  - `div#rich` containing `<b>bold</b> and <i>italic</i>` (outerHTML
    and collapsed-text tests).
  - `p.padded` with leading/trailing whitespace inside the tags (trim
    tests); the auto-wait test schedules its own late element via
    pz_js(), so the fixture stays static.

## Handoff log

(newest first; three lines per session: landed / next / provisional)

- 2026-09-24 (close): landed phase note, fixture
  getters.html + helpers, R/get.R (all nine getters) with the
  els_values()/target_resolver_expr() seams, and test-get.R (369
  tests green). One deviation: loc_resolve() itself routes through
  target_resolver_expr(), so target = NULL works for getters too (it
  had no other callers). Roborev 1226 review fixes landed and the
  review is closed: deterministic auto-wait/count tests (no wall-clock
  assertions), p.padded trim coverage, multi-match pz_get_html() test.
  Provisional carried: has_text collapse doesn't trim; the element
  column is a NULL stub until scoping. New provisional:
  pz_get_text() at the root includes inline <script> text (spec-correct
  textContent, but if "visible page text" is ever wanted, the scoping
  task should skip script/style subtrees).
- 2026-09-24 (start): claimed 5cqf; baseline green at 3f392e7 (305
  tests). Blockers a3vj/gayb closed; primitives as promised. Decisions
  above resolved before code. Next: fixture + R/get.R in parallel,
  then test-get.R, roborev, close. Provisional: has_text collapse
  doesn't trim (see pz_get_text decision); element column is a NULL
  stub until scoping.
