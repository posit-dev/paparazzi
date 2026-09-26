# Drag cursor order (paparazzi#6wp8)

Signed off: orchestrator.

## Scope

In `R/actions.R`, separate destination actionability measurement from cursor movement so `pz_drag(to =)` measures the destination before the source (preserving scroll and final drop re-probe), but moves the cursor to the source first. Keep other pointer-action callers unchanged. Add a discriminating drag cursor-order regression in `tests/testthat/test-actions.R`; retain the existing destination drop test.

## Mechanism

Extract the existing scroll/actionability poll and obstruction/timeout mapping into `el_actionable_point(ctx, els, call)`, returning the point without moving the cursor. Keep `el_pointer_point()` calling that helper followed by `stage_move_cursor()`; the destination-first measurement in `pz_drag()` calls the measuring helper instead. Do not add a flag, reorder measurements or scroll staging, or change `R/stage.R`. Keep the staging-seam and destination-first comments accurate. Verify all other `el_pointer_point()` callers still use the moving wrapper.

## Handoff

To be filled after implementation and targeted checks.
