# Phase note: expectation core + first catalog (kata paparazzi#8kxx)

Mechanism decisions for the expectation task, resolved before code.
Durable requirements live in `.agents/SPEC.md` (section "Expectations");
this note holds mechanism-level choices and session handoffs for this
phase only. Builds on the resolution engine from
`.agents/phases/element-specs-resolution.md` (loc_resolve_once() is the
resolve primitive).

## Decisions

- **Retry core.** Internal `expect_retry(fn, timeout, loop)`: like
  `pz_poll()` but does NOT abort on deadline — it returns the last
  failure result so the caller can raise the rich classed error. `fn()`
  returns `list(pass = TRUE)` or `list(pass = FALSE, observed = <value
  for the error>)`. Between checks, pump chromote's child loop with
  `later::run_now()` (interval 0.1s, same as pz_poll). `timeout = 0`
  checks once, then reports. `pz_poll()` itself is untouched (the open/
  load waits still use it).
- **Driver.** Internal `expect_impl(ctx, target, not, timeout, check,
  description, call)`: resolves via `loc_resolve_once()` once per poll
  iteration (handles released after each iteration — the observed value
  is extracted to R first, so nothing pins), applies the check in R,
  retries until pass or deadline. Pass -> testthat bridge -> invisible
  ctx. Fail -> classed error. R-side comparison (not a JS predicate) so
  error messages get real last-seen values and pairwise text logic
  stays in R.
- **Observed values.** For checks needing element state, ONE
  `Runtime$callFunctionOn` on the resolved array handle maps elements
  to observed values (visibility booleans, collapsed texts, ...);
  comparison happens in R. `exists`/`count` need only the count — no
  second round trip.
- **Failure error.** `cli::cli_abort(class =
  "paparazzi_expectation_failure")` matching the SPEC's format.
  Message lines are FIXED cli templates; all dynamic parts (headline,
  target, observed, waited) interpolate as cli values, never pasted
  into templates — observed page text or a bracey regex must stay
  literal (roborev 1222 found the injection; same rule applies
  everywhere page-derived text reaches cli). The testthat bridge gets
  the same lines via `cli::format_message()`. Format:
  headline ("Expected text to contain \"otters\""), `Target:` line with
  `format_loc()` output, `Last seen:` line with the observed value
  (quoted, truncated to ~80 chars), `Waited {n}s.` Negation folds into
  the headline ("Expected no element to contain ..." / "Expected text
  not to contain ..."). The scope-chain display in the SPEC example
  lands with the pz_find() task; `within` chains already render via
  format_loc().
- **Catalog signatures.**
  - `pz_expect_exists(ctx, ..., target = NULL, not = FALSE, timeout = NULL)`
  - `pz_expect_count(ctx, n = NULL, ..., min = NULL, max = NULL,
    target = NULL, not = FALSE, timeout = NULL)` — exactly one of `n`
    or `min`/`max`; `n` is exact, `min`/`max` bound inclusive (either
    may be NULL = unbounded). min > max is a validation error.
  - `pz_expect_visible(ctx, ..., target = NULL, not = FALSE, timeout = NULL)`
  - `pz_expect_hidden(...)` — exactly `pz_expect_visible(not = TRUE)`
    (a thin wrapper, per SPEC).
  - `pz_expect_text(ctx, text, ..., match = c("contains", "exact", "regex"),
    target = NULL, not = FALSE, timeout = NULL)` — whitespace collapsed on both
    sides before comparing (same rule as `has_text`). `text` length 1 applies to
    every match; length n requires exactly n matches and compares
    pairwise in order. `regex` matches against the collapsed element
    text (R `grepl`). Negated vector text passes only when NO element
    satisfies its pairwise expectation (the SPEC's "no match
    satisfies" applied per pair); a count != length(text) mismatch
    passes the negation vacuously.
    Order aligned with value/attr during the docs API cross-check.
- **Multi-match semantics** (SPEC table, pinned by tests):
  - exists: pass if count >= 1; `not`: pass if count == 0.
  - count: pass if count satisfies n/min/max; `not`: inverse.
  - visible/text (state & content): need >= 1 match AND all matches
    satisfy; `not`: pass when NO match satisfies, including 0 matches.
- **Visibility.** JS `el.checkVisibility({ checkVisibilityCSS: true })`
  (Chrome 105+; chromote always drives Chrome) — catches display:none
  and visibility:hidden up the ancestor chain. No opacity or
  off-viewport consideration (pz_expect_in_viewport is a later catalog
  entry).
- **target = NULL (provisional).** Means "the current context". Until
  the pz_find() task lands, the only context is the root, where
  target = NULL resolves to a single implicit element: `document.body`.
  So `pz_expect_text(page, "Welcome")` checks page text;
  `pz_expect_exists(page)` trivially passes at root. Scoped contexts
  will substitute their pinned element — revisit then.
- **testthat bridge.** `testthat::is_testing()` gates it (testthat in
  Suggests; requireNamespace-guarded). Inside tests: a pass counts via
  `testthat::expect(TRUE, <failure message>)`; a failure is reported
  via `testthat::expect(FALSE, <failure message>)` (which registers the
  test failure) and then the function returns invisibly — no double
  report. Outside tests: plain `paparazzi_expectation_failure` abort.
  Tests verify the bridge with `testthat::expect_success()` /
  `testthat::expect_failure()`, and the outside path by overriding the
  TESTTHAT_IS_TESTING env var with withr.
- **File layout.** `R/expect.R` (retry core, expect_impl, the five
  exported expectations). Tests mirror: `tests/testthat/test-expect.R`.
  Fixture: extend `tests/testthat/fixtures/elements.html` with NEW
  classes only (e.g. `.ghost` display:none, `.veiled`
  visibility:hidden, a `.late`-style target if needed) — do not touch
  existing elements or their counts; test-resolve.R asserts exact
  counts.
- **Validation.** text via check_character (min_length 1); n/min/max
  via check_number_whole(min = 0); match via arg_match; not via
  check_bool; timeout via resolve_timeout. Dots checked empty.

## Handoff log

(newest first; three lines per session: landed / next / provisional)

- 2026-09-24 (close): landed the phase note (bd5416b), the core +
  catalog (cd8937a), and review fixes (facda43: cli-value
  interpolation, vector-not zero-hits, hidden's check_bool).
  288 tests green; roborev 1222 closed, dispositions on the issue.
  Next: 18j6 (getters) or 2fc0 (pz_find pinning) per kata next.
  Note for getters: collapse_ws() in R/expect.R trims while the
  resolver's has_text collapse does not — unify when pz_get_text
  lands (raw = FALSE path). Provisional carried: has_text
  case-sensitivity.
- 2026-09-24 (start): claimed 8kxx; harness green at f622f5f (201
  tests). Blocker a3vj closed; loc_resolve_once() delivered as
  promised. Decisions above resolved before code. Next: implement
  R/expect.R + tests. Provisional: target = NULL at root =
  document.body.
