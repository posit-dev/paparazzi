# Phase note: cursor and staging (kata paparazzi#rvj4)

Mechanism decisions for `pz_stage()`, the cursor functions, and the
staged (animated) variants of pointer actions, typing, and scrolling.
Durable requirements live in `.agents/SPEC.md` (section "Cursor and
staging" -- its behavior matrix is normative); this note holds
mechanism-level choices and session handoffs for this phase only.
Builds on the action pipeline (`actions.md`: `el_pointer_point()`,
`dispatch_click()`, `dispatch_mouse()`), the scroll/selection seams
(`advanced-interactions.md`: `scroll_apply_js`), the direction parser
(`framing.md`: `parse_direction()`), the recorder (`recording.md`:
`page_recorder()`, the child-loop tick), and the overlay host +
resolution exclusion seam (`#paparazzi-overlay-root`, R/inspect.R,
R/resolve.R).

## Probed browser behavior (scratch sessions, before code)

- `Input.dispatchMouseEvent type = "mouseWheel"` scrolls by EXACTLY
  `deltaY`/`deltaX` CSS pixels (fractional deltas accumulate), as
  trusted events (`isTrusted: true`). The scroll lands asynchronously
  (the dispatch returns first), so each wheel step needs a pump before
  the position is re-read.
- Wheel latching: a wheel over a nested scroller scrolls the scroller;
  once it hits its max, later wheels scroll the window. The cursor
  position therefore chooses the container.
- `elementFromPoint()` ignores `pointer-events: none` content, so the
  overlay never shadows the "element under the cursor" read.
- CSS transitions on overlay content (shadow DOM, `position: fixed`)
  are captured mid-animation by `Page.captureScreenshot` -- page-side
  animation plus an R-side loop pump is all a glide needs; no R-side
  frame stepping.
- CSS `zoom`: the overlay host is appended to `documentElement`, so a
  `zoom` on `<html>` scales it (probe: `left: 100px` rendered at 200
  under `zoom: 2`); `zoom` on `<body>` does not reach it.
  `getBoundingClientRect()` and CDP pointer coordinates both live in
  the zoomed (visual) space, so counter-zooming the cursor layer by
  `1 / zoom(documentElement)` keeps the cursor aligned with pointer
  coordinates. dpr needs no handling: the overlay is DOM and scales
  with the capture surface like the rest of the page.
- `Page.addScriptToEvaluateOnNewDocument` runs on every later document
  (http AND file://) once `Page.enable()` has been called on the
  session; without `Page.enable()` it silently never runs.
  Re-registering (remove + add) swaps the source.

## Decisions

- **Staging state on the page.** Two fields in the page's reserved
  `private$staging_` list (R/context.R, untouched; the
  `page_frame()`/`page_set_frame()` pattern in R/frame.R is the access
  model): `staging_$stage`, the settings list merged by `pz_stage()`
  (fields `cursor` NULL/TRUE/FALSE, `cursor_speed` px/s, `enter` NULL
  or side tokens, `typing` "natural"/"instant", `typing_speed`
  chars/s, `pause` seconds; defaults below), and `staging_$cursor`, a
  mutable environment with the cursor runtime state (`visibility`
  "auto"/"shown"/"hidden", `x`/`y` viewport CSS px or NULL, `shape`
  "arrow"/"hand", `off_frame` NULL or the side tokens the cursor left
  through, `init_id` the registered new-document script id or NULL).
  Access only through `page_stage()` / `page_cursor()` and their
  setters in R/stage.R / R/cursor.R. Defaults: `cursor = NULL`,
  `cursor_speed = 1500`, `enter = NULL`, `typing = "natural"`,
  `typing_speed = 16`, `pause = 0`.

- **Recording detection.** "While recording" is
  `page_recorder(page)` non-NULL and `active` (paused still counts as
  recording; the capture cadence is the recorder's problem). One
  helper `stage_recording(page)` in R/stage.R; nothing else reads the
  recorder from staging code.

- **Effective cursor visibility.**
  `cursor = FALSE` (setting) hides, always. Otherwise the `visibility`
  state wins: `"shown"` (after pz_cursor_show/move) and `"hidden"`
  (after pz_cursor_hide) are explicit; `"auto"` (the default) is
  visible while recording or when `cursor = TRUE`. `pz_cursor_leave()`
  keeps the cursor visible but off-frame. A hook in
  `pz_record_stop()` hides an `"auto"` cursor when the setting is NULL
  (recording over: no cursor in later stills); an explicitly shown
  cursor stays.

- **Overlay structure.** The cursor lives under the EXISTING
  `#paparazzi-overlay-root` host (its shadow root), as a sibling layer
  of the inspect layer: a `.pz-cursor` wrapper (`position: fixed`,
  counter-zoomed), holding an outer glide div (`transform:
  translate(x, y)`, transition set per move) holding an inner
  scale/opacity div (press scale-down, fade-in) holding two inline
  SVGs (arrow, hand), toggled by a class. Two nested divs keep the
  glide transform and the press/fade transforms independent. Living
  under the same host is what excludes the cursor from `pz_find()`
  (the resolver filters `closest('#paparazzi-overlay-root')`, which
  matches the host itself) and from every bounding-box/union
  computation, with no change to R/resolve.R. `pointer-events: none`
  everywhere in the layer, so hit-testing and `elementFromPoint()`
  pass through (probed).

- **Screenshots hide only the inspect layer.** `overlay_hide()` /
  `overlay_restore()` (R/inspect.R) currently hide the whole host for
  the CDP capture; they are rescoped to hide only `.pz-inspect`
  layers, so inspect outlines still never reach a screenshot but a
  visible cursor does (the SPEC matrix: `cursor = TRUE` shows a static
  cursor in stills). The contract of the functions (hide for one
  capture, restore after) is unchanged; recordings never hid anything.

- **Animation driver: page-side CSS + R-side pump.** Glides, fades,
  and the press are CSS transitions on the overlay; the R side sets
  the end state in one JS call and then pumps the child loop for the
  duration (`pump_loop()`, the `pz_wait()` mechanism -- no new timer
  system). While the loop pumps, the recorder's ticks fire and capture
  the intermediate frames: the animation belongs to the recording
  clock by construction. Not recording, the same calls set the end
  state with no transition and skip the pump, so the chain runs
  straight to the final state.

- **Glide math.** `duration = clamp(0.25 + distance / cursor_speed,
  0.3, 1.2)` seconds over the straight-line distance, CSS
  `cubic-bezier(0.42, 0, 0.58, 1)` (ease-in-out). An explicit
  `duration =` (pz_cursor_move) wins. Off-frame entry/exit points are
  computed from the viewport box and the side tokens: 40px past the
  named edge(s), at the target's coordinate on the other axis.

- **Pointer-action staging (the `el_pointer_point()` seam).**
  `el_pointer_point()` keeps its signature and its poll; inside the
  poll, the instant `el_scroll_into_view()` becomes
  `stage_scroll_into_view(ctx, els)`: recording -> probed wheel
  scrolling (below); not recording -> the existing instant scroll,
  unchanged. On success (point found), the seam calls
  `stage_move_cursor(ctx, point, els)`: recording -> fade in at the
  point (never-shown cursor, no `enter`), glide in from the `enter`
  side (never-shown, `enter = <side>`), glide back in from the
  `off_frame` side (after pz_cursor_leave), or glide from the last
  position (visible cursor); not recording -> jump the cursor to the
  point only when it is visible (the SPEC's "with cursor = TRUE, the
  cursor jumps to the pointer"). The hand-vs-arrow shape is synced
  from the element under the destination in the same JS call that
  lands the cursor (walk up from `elementFromPoint()` to the first
  computed `cursor` other than `auto`; `pointer` -> hand, the only
  shape rule in v1). Click pauses live in `dispatch_click()`:
  ~0.15s before the press, the scale-down press around
  pressed/released, ~0.2s after; all no-ops when not recording.
  `pz_stage(pause =)` is applied once per exported action (click,
  hover, type, scroll by/to), never between the sub-steps of one
  action. Drag/select_text stay instant in v1: they route through
  `el_pointer_point()`, so the cursor lands on their endpoints, but
  their intermediate moves are not animated (the
  advanced-interactions note names those seams; they are follow-ups).

- **Natural typing.** `insert_text()` splits: recording +
  `typing = "natural"` -> one `Input.insertText` per character with a
  pumped delay between characters, `delay = runif(1, 0.5, 1.5) /
  typing_speed` (uniform jitter around the mean interval; no typo
  simulation); otherwise (including `typing = "instant"` while
  recording, and everything not recording) the existing single
  `Input.insertText`. Per-char insertText reaches inputs, textareas,
  and contenteditable the same way the one-shot call does (the
  focus-via-click pipeline is unchanged).

- **Smooth scrolling with real wheels.** One JS probe returns, for an
  element (or the by/to container): the nearest scrollable
  ancestor-or-self (falling back to `document.scrollingElement`), its
  viewport center (cursor placement), and the pixel delta that brings
  the element to the `scrollIntoView(block: "nearest")` position
  (same math, computed without scrolling). R then glides the cursor
  over the container and dispatches `mouseWheel` events in ~100px
  steps with a short pump between them (~60 steps/second; total time
  clamped like a glide), re-reading the position every few steps;
  latching (probed) means the cursor's container gets the scroll.
  Convergence guard: if two probe rounds make no progress, fall back
  to the instant scroll -- correctness of the final state always wins
  over the animation. `pz_scroll(by =)`/`pz_scroll(to =)` take the
  same wheel path while recording (delta computed from current to
  target scroll position), the instant `scroll_apply_js` path
  otherwise.

- **Navigation robustness.** On first cursor use the page registers a
  new-document script (`Page.enable()` first -- probed requirement)
  whose source is the overlay boot JS plus the last cursor state as
  JSON; every later cursor state change re-registers (remove + add)
  so a navigation re-injects the overlay at its last position.
  `init_id` lives in the cursor state. Every cursor JS command is
  additionally create-if-missing, so an injected-or-not page can
  always be driven forward.

- **`pz_inspect()` contract.** `inspect_recording_state()` (the named
  seam in R/inspect.R) reads the real state: recording
  "on"/"paused"/"off" from `page_recorder()`, cursor
  "visible"/"off-frame"/"hidden" from the effective visibility. The
  printed line stays `{recording} · cursor {cursor}`.

- **File layout.** `R/stage.R` (`pz_stage()`, settings storage,
  recording detection, animation/pump drivers, staged scroll and
  typing internals, action hooks), `R/cursor.R` (cursor functions,
  overlay boot/state JS, shape sync, new-document registration).
  Edits: `R/actions.R` (`el_pointer_point()` scroll/cursor seam,
  `dispatch_click()` press/pause hooks, per-action `pause`,
  `insert_text()` split, `pz_scroll()` wheel branch), `R/inspect.R`
  (the state seam + `overlay_hide()` rescope), `R/record.R` (the
  record-stop cursor hook). Tests mirror: `tests/testthat/test-stage.R`,
  `tests/testthat/test-cursor.R`, `fixtures/cursor.html`,
  `helper-cursor.R` (fixture opener, PNG cursor-location reads modeled
  on helper-frame.R's pixel reads).

- **Frame-content assertions.** The fixture keeps a clean white band
  across the glide path (no dark content); a test helper decodes a
  captured PNG in the page (helper-frame.R's canvas technique) and
  returns the x-centroid of near-black pixels in the band -- the arrow
  cursor is the only near-black content there. Glide frames then
  assert the centroid moves left to right; the press asserts the
  cursor's bounding box shrinks; typing asserts the fixture's input
  event count (one per character natural, one total instant) and the
  recorded duration covers the typed stretch; smooth scroll asserts
  trusted wheel events reached the page and intermediate frames show
  intermediate scroll offsets.

## Review-fix round (roborev 1263)

All seven findings accepted; one commit per finding.

1. (HIGH) The into-view probe only computed the delta for the NEAREST
   scrollable ancestor, so a target visible inside a container that is
   itself below the fold probed zero and a recorded click dispatched
   off-screen. Fix: the probe walks every scrollable ancestor plus the
   viewport, computes each level's `scrollIntoView('nearest')` delta
   (inner deltas are invariant under outer scrolls), and the R loop
   wheels the OUTERMOST container with a nonzero delta first -- outer
   clips contain the inner ones, so the wheeled container is on screen
   before its wheel fires. Stalls are detected by unchanged scroll
   positions (not by comparing deltas across rounds, which now span
   different containers).
2. (HIGH) Root scrolling wheeled at the viewport center; a nested
   scroller covering that point consumed the wheels and the instant
   repair then left the scroller changed, so recorded and unrecorded
   chains could end in DIFFERENT states. Fix: hit-test the dispatch
   point before any wheel fires -- `elementFromPoint()` (which passes
   through the overlay's `pointer-events: none`) walks up to the
   nearest scrollable that can consume the delta, and the wheel only
   fires when that is the intended container; otherwise the instant
   application runs FIRST. Real-wheel semantics are preserved: a valid
   point always gets real wheels, never a silent JS scroll.
3. (MEDIUM) `pz_stage()` treated explicit `NULL` as omitted, so
   `cursor = FALSE` could never be undone. Fix: `missing()` is the only
   way to leave a setting alone; a supplied `NULL` removes the
   override (back to the default).
4. (MEDIUM) A recorded scoped scroll brought an off-screen scope into
   view with an instant `scrollIntoView()`. Fix: the scope goes through
   `stage_scroll_into_view()` like every other pre-action scroll.
5. (MEDIUM) The stage `pause` missed `pz_press()`, `pz_select_text()`,
   and `pz_drag()`. Fix: `stage_action_pause()` after each successful
   exported action (the three missing call sites in R/actions.R; no
   common action-exit point exists).
6. (MEDIUM) The demo asserted glide frames only. Fix: frame-content
   assertions for the press (cursor ink height shrinks at the button),
   the growing text (ink count in an input rect that excludes the
   cursor), and intermediate scroll positions (the fixed-point pixel
   takes >= 3 distinct values across the scroll stretch).
7. (LOW) `pz_cursor_hide()` stickiness is BY DESIGN: an explicit hide
   stays hidden until `pz_cursor_show()`/`pz_cursor_move()` re-shows
   it -- that is what distinguishes it from `pz_cursor_leave()` (the
   documented "glides back in on the next action" variant). Fixed by
   documentation: the roxygen and this note now promise exactly that;
   no behavior change.

## Handoff log

(newest first; three lines per session: landed / next / provisional)

- 2026-09-25 (review fix): landed all seven roborev 1263 findings, one
  commit each (739bfa6 planned them first): the into-view probe walks
  every scrollable ancestor and wheels outermost-first with a
  position-based stall check (f174d57), both wheel paths hit-test the
  dispatch point and fall back to instant BEFORE any wheel fires
  (a15c410), pz_stage() treats supplied NULL as override removal
  (f5070db), a scoped scroll's scope goes through the staged into-view
  (986b3ef), the stage pause now holds after pz_press/select_text/
  drag (bc5fa58), the demo frames assert the press, the growing text,
  and intermediate scroll positions (b10adbc), and pz_cursor_hide()'s
  stickiness is documented as designed (faef416, roxygen + man regen).
  Full suite green at faef416: 1627 PASS / 0 FAIL / 0 SKIP (baseline
  ~1600). Next: review/merge decision stays with garrick; roborev
  1263 is ready to close once the fixes are reviewed; drag/select_text
  intermediate-move staging and ripple/cursor styles stay the named
  follow-ups. Provisional: the wait.R man pages that had drifted on
  main were deliberately left out of the regen.
- 2026-09-25 (finish): landed the keystone (pz_stage + overlay cursor
  + staged pointer actions, 46850d8), natural typing and
  wheel scrolling (73bc194), the test suite with the frame-content
  demo (fixture cursor.html, helper-cursor.R, band pixel scans), the
  scoped pz_cursor_show() (55fef53), and the bounded wheel probe loop
  (da18261). Tests surfaced and fixed: static draws skip the opacity
  transition (stills were catching mid-fade cursors), the new-document
  script defers boot until documentElement exists, scoped containers
  scroll into view before wheeling, wheel points clamp to the
  viewport. Full suite green at da18261 (baseline 1464 -> 1568, 0
  failures/skips); an earlier suite run wedged on machine contention
  (three concurrent suites, dozens of orphaned Chrome processes from
  killed runs), not on a code hang -- the rerun on a quiet machine
  passed cleanly. roborev was
  requested three times (1257-1260, branch range) but BOTH agents fail
  on environment issues (codex: AWS credentials; claude-code:
  openai.gpt-6-sol model_not_found) -- rerun `roborev review --branch`
  when the infra is fixed. Next: review + merge decision stays with
  garrick; drag/select_text intermediate-move staging and ripple /
  cursor styles are the named follow-ups. Provisional: wheel scrolling
  handles one scroll container per probe round and falls back to
  instant on stalls; nested-container choreography and mid-glide hand
  shape updates are v2 material.
- 2026-09-25 (pause, mid-session): landed only the mechanism note
  (22f319e); orientation and browser probes complete, NO package code
  written yet -- R/stage.R, R/cursor.R, fixtures, and tests are all
  still to do, and the full-suite baseline run had not reported back
  when the session paused (main was green at ~1460). Next: keystone
  first -- staging state + cursor overlay + one recorded animated
  click end-to-end, then widen per the decisions above. Provisional:
  drag/select_text endpoint-only staging in v1; nested-scroll
  convergence falls back to instant after two wheel rounds.
- 2026-09-25 (start): claimed rvj4; blockers 2fc0 and pat5 closed,
  baseline suite running green at ~1460. Probed CDP semantics before
  code: exact asynchronous wheel deltas with container latching,
  elementFromPoint passing through pointer-events:none, shadow-DOM CSS
  transitions visible in captureScreenshot, html-zoom counter-zoom on
  the overlay, and Page.enable() being the requirement for
  addScriptToEvaluateOnNewDocument (file:// included). Decisions above
  resolved before code. Next: keystone first -- staging state + cursor
  overlay + one recorded animated click end-to-end, then widen to
  cursor functions, typing, scroll, navigation. Provisional:
  drag/select_text endpoint-only staging in v1; nested-scroll
  convergence falls back to instant after two wheel rounds.
