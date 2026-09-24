# Phase note: framing (kata paparazzi#r0zd)

Mechanism decisions for `pz_frame()` / `pz_stage_frame()` and the
`pz_screenshot(frame =)` integration. Durable requirements live in
`.agents/SPEC.md` (sections "Framing", "Directions"); this note holds
mechanism-level choices and session handoffs for framing only.

## Decisions

- **Spec representation.** `pz_frame()` returns an S3 list of class
  `paparazzi_frame` with fields `target` (NULL or an `as_loc_list()`
  loc list -- validated eagerly so type errors surface at spec build,
  resolution stays lazy), `ratio` (NULL or positive number),
  `pad` (always normalized to `c(top, right, bottom, left)`, CSS order),
  `offset` (length-2), `anchor` (the sorted token vector from the
  direction parser), `bounds` (NULL or loc list), `when`
  (`"stop"`/`"start"`, recordings-only -- stored, never read here).
  A `print()` method shows the spec. `pz_stage_frame()` builds the same
  spec through the same constructor, substituting defaults for NULL
  fields (pad 0, offset `c(0,0)`, anchor center).
- **Page default storage.** The page's reserved `private$staging_` list
  (R/context.R) gains one field, `staging_$frame`: the default
  `paparazzi_frame` spec or NULL. `page_frame(page)` /
  `page_set_frame(page, spec)` in R/frame.R are the single access
  point (R6 privates are reached through `.__enclos_env__`, which is
  why the helpers exist -- a later active binding replaces them in one
  place). The recorder reads the same helpers. `pz_stage_frame(ctx,
  NULL)` clears; zero dots sets a target-less default (target NULL =
  "use each call's target"). Unnamed dots are the default frame's
  target (one target, or several unioned as a list); named dots error.
- **Computation pipeline and coordinate spaces.** Everything runs
  viewport-relative in CSS pixels -- the space `el_rects()` returns --
  until one final conversion to document coordinates for the CDP clip:
  1. Union the content boxes: the frame's `target` if set, else the
     call's `target`, else the pinned scope (scoped context), else the
     viewport box `(0, 0, innerWidth, innerHeight)`.
  2. Expand by `pad`, then shift by `offset`.
  3. If `ratio` is set, grow the shorter side only (never shrink),
     placing the content by `anchor`: `left` grows right, `right`
     grows left, otherwise the extra width splits; `top` grows down,
     `bottom` grows up, otherwise the extra height splits.
  4. Clamp: intersect with the `bounds` box (resolved and unioned like
     any target) and with the document box -- `[0, scrollWidth] x
     `[0, scrollHeight]` in document coordinates, i.e. the
     `(-scrollX, -scrollY)`-anchored region viewport-relative. The document
     box, NOT the visible viewport: `captureBeyondViewport` renders the
     whole document, so below-fold targets stay capturable, and
     beyond-document growth would produce unrendered pixels. This is
     the SPEC's "clamp to the viewport" step.
  5. Round edges to whole pixels (stills); the recording task will pass
     an even-pixel rounding through the same step.
  Steps 2-4 are pure geometry (`frame_apply()`), unit-testable without
  a page; `frame_clip()` owns the reads (one JS evaluation for
  scroll/viewport/document size) and the final
  `+ (scrollX, scrollY)` conversion.
- **How the crop reaches captureScreenshot.** A CDP `clip` on the same
  single `Page.captureScreenshot` call -- no post-crop of a larger PNG.
  `frame =` resolution in `pz_screenshot()`: NULL means the page
  default if set, else today's behavior; a `paparazzi_frame` computes
  the clip; `FALSE` opts out for one call; anything else (including
  `TRUE`) aborts with class `paparazzi_error_unsupported` (the value
  remains unsupported, which keeps the existing test honest). The
  unframed path in R/screenshot.R is untouched -- the framed path
  lives in R/frame.R.
- **Empty/degenerate frames error** (`paparazzi_error_frame`): a frame
  box that ends up empty after clamping (outside bounds/document) or
  with non-positive width/height after rounding.
- **Direction vocabulary parser.** `parse_direction(x, valid, arg,
  call)` in R/frame.R: lowercase, split on spaces/hyphens, sort, dedupe;
  tokens outside `{top, bottom, left, right, center}` and token sets
  outside `valid` abort with the valid values listed. `valid` defaults
  to the nine direction values (sides, corners, center) -- the whole
  SPEC "Directions" vocabulary, which is exactly what `anchor` accepts;
  `pz_cursor_leave(side =)` and friends later pass a subset and reuse
  the parser unchanged.
- **File layout.** `R/frame.R` (spec, parser, page default, pipeline),
  `tests/testthat/test-frame.R`,
  `tests/testthat/fixtures/frame.html` (integer-CSS-geometry elements
  for pad/ratio/anchor/bounds/document-clamp cases),
  `tests/testthat/helper-frame.R` (fixture opener, PNG pixel reads --
  `helper-page.R` is shared and untouched). Existing
  `fixtures/screenshot.html` counts stay pinned; test-frame.R uses its
  own fixture.

## Handoff log

(newest first; three lines per session: landed / next / provisional)

- 2026-09-24 (start): claimed r0zd; blocker 18j6 closed (the `frame =`
  seam), baseline 838 tests. Decisions above resolved before code.
  Next: phase note, `R/frame.R`, fixture + `test-frame.R`, screenshot
  integration. Provisional: `when` is stored but unread until recording.
