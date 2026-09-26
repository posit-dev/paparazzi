# Keep CSS zoom bookkeeping retryable (paparazzi#ves6)

Signed off: orchestrator.

## Scope and mechanism

In `R/device.R`, disable must not return early when the desired zoom and cached zoom are both NULL but a new-document script is still registered. Preserve `css_zoom_saved` until the inline restore eval succeeds. Do not add rollback, flags, queues, or timers. The existing `device_css_reapply()` and `wait_nav_reset()` navigation path must continue to reapply active zoom.

## Verification

In `tests/testthat/test-device.R`, inject a failed first inline apply and immediately disable before navigating; inject a failed inline restore on a page with its own zoom and retry disable. Confirm each test fails before the fix and passes after it. Run locked `test_local(filter = "device")` and `test_local(filter = "wait|nav")`; capture their exact totals. Run `air format --check .` and `jarl check .`.

## Execution

Commit this note before code changes. Commit the regression tests, record their red results, make the two scoped bookkeeping edits, then verify and commit the fix. Fill and commit the handoff, and comment on the claimed issue. Do not push, merge, request reviews, or close the issue.

## Handoff

- Landed two regression tests: a failed first inline apply followed by immediate disable and navigation; a failed restore followed by a disable retry that must recover the page's inline zoom of 1.5.
- Before the fix, locked `test_local(filter = "device")` failed both assertions: `[ FAIL 2 | WARN 0 | SKIP 0 | PASS 91 ]` (exit 1; computed zoom was 2 after navigation, and restored inline zoom was empty).
- After the fix, locked device tests: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 93 ]` (exit 0); locked wait/nav tests: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 184 ]` (exit 0). `air format --check .` and `jarl check .` passed after formatting `R/device.R`.
- The early return now checks for a registered script on disable, and saved inline zoom is cleared after a successful restore. No rollback or new state was added. No further implementation is planned; leave the issue open for the orchestrator.
