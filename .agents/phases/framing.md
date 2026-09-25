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
     any target) and with the document box -- the document's REAL
     span `[document_left, document_left + scrollWidth] x
     `[0, scrollHeight]` in document coordinates (`document_left`
     is 0 except on RTL pages wider than the viewport, where it is
     negative), i.e. the scroll-anchored region viewport-relative. The
     document box, NOT the visible viewport: `captureBeyondViewport`
     renders the whole document, so below-fold targets stay
     capturable, and beyond-document growth would produce unrendered
     pixels. This is the SPEC's "clamp to the viewport" step.
  5. Round edges to whole pixels (stills); the recording task will pass
     an even-pixel rounding through the same step. Edges a clamp fixed
     in place round inward (left/top up, right/bottom down) so the
     pixel clip stays within the CSS bounds; free edges round to the
     nearest pixel (or nearest even pixel for video).
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

## Review fixes (roborev 1245)

One commit per accepted finding. The document-vs-viewport clamp
finding was declined (the document clamp for stills is intended; SPEC
"Framing" step 4 amended on main to say "capture surface"), so the
current clamp semantics stay.

- **Geometry read order.** `frame_clip()` resolves and measures targets
  and bounds first, then reads page geometry: resolution auto-waits,
  so a target appearing mid-wait can expand the document, and the
  clamp must see the expanded document. The viewport fallback box is
  filled from that fresh read.
- **RTL negative-scrollX narrowing.** Empirical Chrome model: an RTL
  document wider than the viewport overflows to the LEFT, so the
  scrollable canvas spans document coordinates `[-(scrollWidth -
  innerWidth), innerWidth]`, not `[0, scrollWidth]`, and
  `window.scrollX` goes negative to reveal it. Two changes in
  `frame_clip()`: the page clamp anchors to the real document span (a
  new `document_left` read in `page_geometry()`: `-(scrollWidth -
  innerWidth)` when the root element is RTL and wider than the
  viewport, else 0 -- LTR unchanged), and a clip whose document origin
  went negative shifts to x = 0 preserving its size (CDP clip origins
  must be non-negative; the region shifts with it, mirroring
  `clip_viewport()`). Identity `pz_frame()` then matches the unframed
  screenshot's dimensions. New fixture `frame-rtl.html`; dimension
  assertions only -- Chrome's `captureBeyondViewport` resize
  re-lays-out the page, so pixel placement in RTL captures is
  browser-dependent and not asserted.
- **Rounding vs fractional bounds.** Edges a clamp fixed in place
  ("pinned") round INWARD (left/top up, right/bottom down; even mode
  doubles the same rule) so the rounded pixel clip stays within the
  CSS bounds; free edges keep nearest-pixel (stills) or nearest-even
  (video) rounding, preserving the documented ratio-growth behavior.
  Pinned-ness is derived in `frame_clip()` by comparing the clamped
  edges with the clamp boxes (bit-equal when a clamp bound the edge;
  conservative when the values merely coincide). A fractional
  `#fractional` element joins `frame.html` as a bounds target.

## Handoff log

(newest first; three lines per session: landed / next / provisional)

- 2026-09-24 (close): landed the phase note (7d8425b), framing specs
  `pz_frame()`/`pz_stage_frame()` + direction parser + page default
  (370f18a), the `pz_screenshot(frame =)` integration (fe60253), and
  the fixture + crop-geometry tests (a49bc81). 954 expectations green,
  0 failures; R CMD check 0/0/4 (all notes pre-existing/environmental).
  Next: fx4z (recording) consumes `frame_clip(ctx, target, spec,
  even =)` -- the `paparazzi_frame` spec stored on the page
  (`page_frame()`/`page_set_frame()`) is THE seam recording reads, with
  `when` stored but still unread; pass `even = TRUE` for video dims and
  the visible viewport as the recorder's clamp instead of the
  document box. Provisional: the cursor/staging task reuses
  `parse_direction(valid = <subset>)` unchanged.
- 2026-09-24 (start): claimed r0zd; blocker 18j6 closed (the `frame =`
  seam), baseline 838 tests. Decisions above resolved before code.
  Next: phase note, `R/frame.R`, fixture + `test-frame.R`, screenshot
  integration. Provisional: `when` is stored but unread until recording.
