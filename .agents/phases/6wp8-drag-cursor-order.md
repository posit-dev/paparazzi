# Drag cursor order (paparazzi#6wp8)

Signed off: orchestrator.

## Scope

In `R/actions.R`, separate destination actionability measurement from cursor movement so `pz_drag(to =)` measures the destination before the source (preserving scroll and final drop re-probe), but moves the cursor to the source first. Keep other pointer-action callers unchanged. Add a discriminating drag cursor-order regression in `tests/testthat/test-actions.R`; retain the existing destination drop test.

## Mechanism

Extract the existing scroll/actionability poll and obstruction/timeout mapping into `el_actionable_point(ctx, els, call)`, returning the point without moving the cursor. Keep `el_pointer_point()` calling that helper followed by `stage_move_cursor()`; the destination-first measurement in `pz_drag()` calls the measuring helper instead. Do not add a flag, reorder measurements or scroll staging, or change `R/stage.R`. Keep the staging-seam and destination-first comments accurate. Verify all other `el_pointer_point()` callers still use the moving wrapper.

## Handoff

- Landed a regression that captures cursor staging during `pz_drag(to =)` and compares its first move with the source's measured center. The pre-fix targeted run failed on both cursor-order assertions: `[ FAIL 2 | WARN 0 | SKIP 0 | PASS 403 ]` (first staged point was the destination, and there were two staged moves).
- Extracted `el_actionable_point()` for destination-first measurement without cursor movement; `el_pointer_point()` still stages movement after measuring. The source, `by` drag path, and the other pointer action callers still use `el_pointer_point()`. Source scroll and destination re-probe remain in their previous order.
- The targeted `actions|stage|cursor` run, including the existing test that verifies the dragged box lands at the destination, passed: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 405 ]`. `air format --check .` and `jarl check .` passed. No full suite run (or roborev review) here; the orchestrator owns the full gate.
