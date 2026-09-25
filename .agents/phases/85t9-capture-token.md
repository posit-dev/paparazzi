# Late recorder callback after capture timeout

Signed off:

## Problem and mechanism

`pz_record_stop()` in `R/record.R` waits for the existing capture, but on poll timeout clears `rec$in_flight` and starts the final capture. `record_capture()` then replaces `rec$pending` with the final capture's timestamp and path. An old `getLayoutMetrics` / `captureScreenshot` callback can still call `record_frame_done()` after this replacement; that function currently clears `in_flight`, consumes whichever pending slot exists, and writes the old image with the final capture's timestamp/path. When the final callback arrives it finds no pending slot and records an error. This can lose the final page state promised by `.agents/SPEC.md` § Recording; it can also end stop's final poll early. Both CDP stages use a common timeout budget, but a late callback remains possible after the stop poll times out.

Replace the two representations of occupancy (`rec$in_flight` and `rec$pending`) with one: `rec$pending` is `NULL` when idle, or a fresh environment holding `vt` and `file` for one capture. `record_capture()` creates this environment and captures it in every success/error callback (including synchronous error paths) in the metrics → screenshot chain. `record_frame_done(rec, pending, res = NULL, err = NULL)` first checks `identical(rec$pending, pending)`: if false, return without clearing the slot, recording an error, writing a file, or touching frame vectors. If true, clear `rec$pending` before processing the result; this preserves the current callback/error handling without a separate ordering flag. The environment is the identity token itself, so even identical vt/file values on consecutive captures cannot alias. `record_tick()` and both stop polls use `!is.null(rec$pending)` as their occupancy predicate. On either stop timeout, set `rec$pending <- NULL` before continuing, explicitly retiring the timed-out capture. Existing errors still pass through `record_error()` and use the existing `paparazzi_error_timeout`/`paparazzi_error_record` classes; introduce no user-facing errors or messages. No JS probes or browser script changes.

The old metrics callback may still issue its screenshot after stop times out; its completion is ignored by the identity check. Avoid adding a separate metrics-stage guard unless evidence shows it is needed: the issue is misattribution of the pending result, not duplicate CDP traffic.

## Alternatives and tripwires

An incrementing integer kept beside `pending` would identify callbacks but adds bookkeeping; a list of vt/file alone is not a reliable identity (both can recur after a timeout). A fresh environment **as the pending value** provides unique identity without a counter or a second flag. Retaining `in_flight` with another token works but leaves two synchronized occupancy states, especially awkward at timeout. No timer, queue, new ordering flag, init/restore window, display-shaped storage, or second guard for a guard is involved. The identity comparison protects the single result slot; it does not serialize captures or change scheduling.

## Red-first test plan

Add a deterministic test in `tests/testthat/test-record.R`, close to the existing final-frame test. Build a `new_recorder()` with a temporary frame directory and a fake page whose mocked `Page$getLayoutMetrics()` and `Page$captureScreenshot()` retain their callbacks (no Chrome/time-based sleeps). Drive the first metrics callback to obtain capture callback A, mimic the existing in-flight stop poll timeout by retiring the pending slot, issue the stop-time capture and drive its metrics callback to obtain B. Invoke A with a distinct base64 PNG payload while B is pending; assert B is still pending, the slot is still occupied, no file/time/error was recorded from A. Invoke B and assert exactly B's bytes/file and final vt are retained, no spurious error, and the slot is idle. The same test should exercise a late error callback (or a second subcase), verifying it cannot consume B or increment the error tally. On the current code, A consumes B's slot and B errors, so the test is discriminating even without timing. Avoid direct access to a new token counter; compare the slot to the captured pending object instead.

Run red-first with `/tmp/pz-chrome-lock.sh Rscript -e 'testthat::test_local(filter = "record")'`, then implement and rerun that filter under the same lock. Run `btw pkg document` only if public docs change (none planned); do not run the full suite here. Report exact FAIL/WARN/SKIP/PASS totals.

## Handoff

- Landed: phase note only; no production or test change in this stage.
- Next: orchestrator sign-off, then red-first test, implementation, and targeted verification.
- Provisional: callback identity via the pending environment replaces rather than adds occupancy/order state.
