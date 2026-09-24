# Phase note: pz_screenshot viewport/target/union (kata paparazzi#18j6)

Mechanism decisions for the basic screenshot task, resolved before code.
Durable requirements live in `.agents/SPEC.md` (sections "Chaining"
argument table, "Framing"); this note holds mechanism-level choices and
session handoffs for this phase only. Framing itself is r0zd; here
`frame =` accepts only NULL/FALSE.

## Decisions

- **CDP call.** One `Page.captureScreenshot(format = "png", clip = ...,
  fromSurface = TRUE, captureBeyondViewport = TRUE)` per screenshot,
  with per-command `timeout_ = ctx$page$default_timeout` (same rule as
  the resolver). The result's base64 `data` is decoded with
  `jsonlite::base64_dec()` and written with `writeBin()`. No promise
  chaining -- a direct synchronous call, like `loc_resolve_once()`.
- **Clip coordinates are document-relative.** With
  `captureBeyondViewport = TRUE` Chrome interprets the clip in page
  coordinates (chromote relies on this: it feeds `DOM.getContentQuads`
  bounds straight into the clip without scrolling). So the clip is
  `el_rects()` output (viewport-relative) plus `window.scrollX/scrollY`,
  and off-viewport targets need **no scroll** -- `el_scroll_into_view()`
  is not called.
- **Device pixel ratio.** With `fromSurface = TRUE` the surface is
  already rendered at the page's dpr, so `clip.scale = 1` yields a PNG
  at exactly the current dpr (chromote passes `scale/pixel_ratio` for
  the same reason). Default capture is therefore "current dpr" with no
  extra argument; the `scale =` user argument arrives with `pz_device()`.
  PNG pixel dimensions are `round(css_size * dpr)`; fixtures use integer
  CSS geometry so tests assert exact dimensions (dpr is 1 in headless
  CI, but tests compute expectations from the live dpr anyway).
- **Union math (the blog bug).** Computed in R from the `el_rects()`
  tibble, never in JS and never by mutating a rect mid-computation:
  `x0 = min(x)`, `y0 = min(y)`, `x1 = max(x + width)`,
  `y1 = max(y + height)`, clip = (x0, y0, x1 - x0, y1 - y0). The blog's
  `union_png()` updated `x` before computing `width`; here the four
  edges are pure reductions over the tibble columns. Pinned by a
  multi-element fixture test where the second element is right of *and*
  below the first, so the buggy order produces a wrong width.
- **`target = NULL`.** Root context: clip is the viewport --
  `(scrollX, scrollY, innerWidth, innerHeight)` read in one JS
  evaluation. Scoped context (no `pz_find*()` yet, so untestable): the
  union of `el_rects()` of the innermost pinned scope set. This is the
  seam; revisit if scoping settles on intersect-instead-of-union.
- **Multi-match.** `loc_resolve(..., multiple = "all")` -- a
  multi-element target is a union, per the task; there is no `strict`
  argument. Every resolved handle is released with
  `release_elements()` (via `withr::defer` / `on.exit`).
- **`frame =` seam.** `NULL` (default) and `FALSE` both mean "no
  framing" today; the distinction matters once `pz_stage_frame()`
  exists. Anything else (including `TRUE`) aborts with class
  `paparazzi_error_unsupported` and a "not yet implemented" message
  pointing at the framing task. No `pz_frame` class exists yet, so the
  check is structural, not class-based.
- **Validation.** `path` via `check_string()`; `...` via
  `check_dots_empty()`; context via `check_context()`. `pz_screenshot()`
  returns the context invisibly (chainable, per SPEC "Chaining").
- **No scrollbar hiding, no clamping.** chromote hides scrollbars and
  clamps to the document box; v1 does neither. A faithful viewport
  capture includes scrollbars, and clamping to bounds is the framing
  task's job (SPEC "Framing" step 4). Clip origin is clamped to `>= 0`
  only, since CDP rejects negative offsets.
- **PNG dimensions in tests.** The `png` package is unavailable, so
  tests parse the IHDR manually: `readBin()` the first 24 bytes, width
  = bytes 17-20, height = bytes 21-24, big-endian uint32. A
  `png_dimensions()` helper lives in `helper-page.R` (shared test
  helpers file) next to a `local_screenshot_page()` fixture opener.
- **File layout.** `R/screenshot.R` (`pz_screenshot()` + internal clip
  helpers), `tests/testthat/test-screenshot.R`,
  `tests/testthat/fixtures/screenshot.html`. The fixture carries
  integer-CSS-geometry elements (known x/y/width/height, distinct
  colors), several `.shot` repeats for multi-match unions, and a
  below-fold element for the beyond-viewport path. `elements.html` and
  `geometry.html` are untouched (their counts are pinned).

## Handoff log

(newest first; three lines per session: landed / next / provisional)

- 2026-09-24 (start): claimed 18j6; blockers a3vj (resolution) and
  gayb (geometry) closed, baseline 302 tests. Parallel worktree effort
  with 5cqf (getters) and 2fc0 (actions); 5cqf merges first, expect a
  rebase. Decisions above resolved before code. Next: fixture +
  `R/screenshot.R` + tests. Provisional: scoped-context `target = NULL`
  is union-of-innermost-scope, untestable until `pz_find*()`.
