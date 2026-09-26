# Drag destination clipped by a scroll container (paparazzi#8cz1)

Signed off: orchestrator, mechanism prescribed in the 8cz1 prompt.

## Problem and mechanism

`pz_drag()` in `R/actions.R` first scrolls the destination, then the source, and re-reads the destination rectangle with `dest_point_js`. An ancestor scroll container can clip the destination after the source's scroll while `checkVisibility()` and the rectangle still report visible and non-empty. The final drop then lands on an unrelated element (e.g. the input above the list). Keep the existing early destination actionability poll and the final invisible/empty and outside-viewport errors.

Compose `pointer_hit_test_js` into `dest_point_js`, as `pointer_actionable_js` does. Return the existing visibility/rectangle/viewport data plus the raw blocker at the final center; use the existing composed-descendant predicate and `format_pointer_blocker()`, not a second shadow-tree algorithm. After the source's scroll, abort immediately if the destination does not receive pointer events at the final drop center. Use `c("paparazzi_error_obstructed", "paparazzi_error_target")`: this is a destination target failure and the same specific obstruction category as source actionability. Name `dest$description` and the formatted blocking element, and tell the caller: "Both endpoints must be visible at once, like a real drag; scroll or scope so they are." No retry: nothing in a retry would scroll the destination back into view.

The destination probe currently precedes the source probe; each `el_pointer_point()` calls `stage_move_cursor()`. Recording can therefore glide to the destination and then back to the source before the drag starts. Report this finding only; it is separate from preventing a misdelivered drop.

## Alternatives and tripwires

Autoscroll of the destination during a held drag is declined: it changes the drag's mechanics and is outside this issue's small scope. Do not scroll the destination again after the source (that would invalidate the now-staged source). No init/restore hook, timer, queue, extra ordering flag, display-shaped stored state, or guard for a guard. A single final hit-test on the same destination element handle directly proves the required drop receiver.

## Red-first test plan

Add an isolated scroll-list fixture under `tests/testthat/fixtures/`: an input above a short max-height overflow-y:auto list with several draggable items. Bring the last item into view as the source, clipping the first destination so its bounding-box center lies on the input. Cover HTML5 draggable and plain mouse source cheaply with fixture variants. In `tests/testthat/test-actions.R`, assert the specific class, destination and input in the message, and no dragenter/drop or mouse press is dispatched before the error (log real browser events). Run `actions` under `/tmp/pz-chrome-lock.sh` before implementation to verify discrimination; then implement, update `pz_drag()` roxygen and regenerate with `btw pkg document` (revert unrelated `man/paparazzi-package.Rd` link drift). Run locked `actions` and `cursor|stage|example` filters. Report example/vignette workarounds and the recording cursor-glide observation without changing prose.

## Handoff

Pending implementation and verification.
