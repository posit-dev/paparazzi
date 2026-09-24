# Phase note: pz_inspect, print methods, overlay outlines (kata paparazzi#5wdj)

Mechanism decisions for the inspection task, resolved before code. Durable
requirements live in `.agents/SPEC.md` (section "Escape hatches and
debugging", the `pz_inspect()` example output); this note holds
mechanism-level choices and session handoffs for this phase only.

## Summary assembly

Every line of the console summary is composed as a plain string and emitted
with `cli::cat_line()` (stdout, no cli markup), because scope/target
descriptions carry user-derived CSS selectors whose braces would break cli
templates; page-derived strings interpolate as values, never templates.
Labels are left-justified to an 11-char column (`sprintf("%-11s")`),
matching the SPEC example (`Recording  off · cursor hidden`).

- **Header**: `── paparazzi page ` + `─` repeated to `getOption("width")`
  (what `cli::cli_rule()` renders; composed by hand for exact control).
- **URL**: one `pz_js()` read of `location.href`.
- **Device**: `1440 × 900 @2x · light` — live `innerWidth × innerHeight`,
  `devicePixelRatio` (integer renders `@2x`), and
  `matchMedia('(prefers-color-scheme: dark)')`, in one JS read. Not stored
  state; `pz_device()` doesn't exist yet, so the page is what it is.
- **Scope**: `root › desc (n) › …`. One `callFunctionOn` per pinned scope
  returns the count of still-`isConnected` elements; a partial loss renders
  `(live of pinned)` and a `cli_inform(c("!" = …))` warning; a released
  object group (post-navigation context) renders `(gone)` + warning — the
  summary warns on stale scopes, it never aborts. The which-qualifier is
  compacted for display only: `` `.item` (which: last) `` → `` `.item` last ``
  (numeric → `#2`), per the SPEC example.
- **Target** (only when `target` is given): resolved with
  `loc_resolve_once()` — a single pass, no retry, per SPEC — relative to the
  current scope behind the usual one-use detach probe. Headline
  `Target     desc → n match(es)` / `→ no matches`. One `callFunctionOn` on
  the resolved array returns per match: opening tag (`<button class="…">`,
  attributes rendered, truncated at 60 chars), `checkVisibility({checkVisibilityCSS})`
  (same predicate as `pz_expect_visible()`), enabled
  (`!(el.disabled === true || el.hasAttribute('disabled'))`; the enabled
  expectation task can adopt this), and the bounding rect rounded to ints.
  Rows `  1  <tag>` / `     visible · enabled · at 812,344 · 24 × 24`
  (words: hidden/disabled); after 10 rows, `… and k more`.
- **Recording**: `off · cursor hidden` from `inspect_recording_state(page)`,
  the ONE seam for subsystem state — neither the recorder nor the cursor
  exists, so it reads off/hidden; those tasks replace this accessor in one
  place.

`print()` on a page or context (R/context.R) renders the same summary minus
the target section, via the shared `inspect_print_summary()`; the closed
page keeps its one-line `<PaparazziPage: closed>`. The old print-format
assertions in test-open.R / test-scope.R are coupled to these methods and
were updated minimally (see deviations below).

## Overlay outlines

Outline elements live under a host `div#paparazzi-overlay-root` (created on
demand, appended to `documentElement`, `position: absolute; top/left: 0;
width/height: 0; pointer-events: none; z-index: 2^31-1`) with an open shadow
root; `loc_resolver_js()` already excludes everything under the host id, and
the shadow DOM keeps the outlines invisible to `querySelectorAll` anyway.
All boxes are document-coordinate (viewport rect + `scrollX/scrollY`, same
math as `clip_rects_union()`), so they stay aligned with the
document-coordinate CDP clip at capture time.

- **Scope**: one dashed amber (`#f59e0b`, 2px) outline per element of the
  top pinned scope — the active scope targets resolve against. Deeper
  stack levels stay summary-only.
- **Target matches**: one solid rose (`#e11d48`, 2px) outline per match,
  numbered left-aligned above it by a rose badge (white monospace digits);
  the badge numbers match the summary's row numbers.
- `overlay_draw(ctx, scope_rects, target_rects)` injects/clears a
  `.pz-inspect` layer in the shadow root (JSON payload, one JS call);
  `overlay_clear(ctx)` removes it; drawing again replaces the layer.

## Capture-and-remove protocol (`show = "screenshot"`)

Draw → `screenshot_capture()` (the internal CDP call in R/screenshot.R, NOT
`pz_screenshot()`, whose guard would hide the outlines) → write PNG →
`overlay_clear()` → viewer or path. The capture region follows
`pz_screenshot()` conventions: viewport at the root; otherwise the union of
scope + target rects padded 16px (so outlines/badges aren't clipped),
falling back to the viewport when nothing readable remains. `path = NULL`
(after `...`, following the `pz_find_nth()` precedent) writes a tempfile;
`show = "browser"` draws the same layer, leaves it, and calls the page's
`$view()`. `show = "auto"` is `"screenshot"` when `interactive()`. The
annotated PNG shows in the rstudioapi viewer (gated
`rlang::is_installed("rstudioapi")`, HTML wrapper) and its path is always
printed; rstudioapi is NOT added to Suggests (DESCRIPTION is off-limits
this phase).

## Hide-during-capture guard in `pz_screenshot()`

Two lines in `R/screenshot.R` around the capture call: `overlay_hide(ctx)`
returns the host's previous inline display (or NULL when no host — the
common case, still one cheap JS read), `on.exit(overlay_restore())` puts it
back. The annotated capture bypasses the guard by calling
`screenshot_capture()` directly.

## Handoff log

(newest first; three lines per session: landed / next / provisional)

- 2026-09-25 (close): landed pz_inspect() + overlay draw/clear/hide
  helpers (R/inspect.R), the print summaries (R/context.R), the capture
  guard (R/screenshot.R), fixture + tests (PASS 909 / FAIL 0 on this
  branch), and minimally updated the print assertions in test-open.R /
  test-scope.R that pinned the old print format. Next: recording (grat?
  child tasks) replaces inspect_recording_state() with a real page
  state read and owns the persistent re-injected overlay host. Provisional:
  path sits after ... (picking a path positionally doesn't work), the
  enabled predicate is inspect-local until pz_expect_enabled lands, and
  pz_inspect() with a target on a stale scope aborts with the classed
  detach error (consistent one-use probe) rather than warning; rstudioapi
  stays out of Suggests (DESCRIPTION off-limits this phase).
