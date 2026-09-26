# Hold recorder captures during device metrics changes

Signed off: orchestrator, per garrick's decision on paparazzi#7n3j.

## Scope and mechanism

- `device_apply_override()` wraps both clear and set metrics calls in a lazy record-side hold. A capture restores the metrics it saw at start, so the hold blocks new captures while the current one settles and the override is sent.
- The recorder initializes `held = FALSE`. `record_tick()` skips capture when held but continues re-arming; the hold never changes pause state or virtual time.
- The helper forces code directly without an active recorder; otherwise it holds until exit, waits for an in-flight capture on the page child loop within the page timeout, and on timeout clears pending and reports via `record_error()`, consistent with stop.
- Test the live in-flight resize before fixing (repeat red runs), plus a unit test for tick suppression and hold cleanup on success/error. Keep the existing viewport resize test's 5-second budget; no NEWS entry in this first development version. Screencast and page init/restore are out of scope.

## Verification

- Run red regression tests under `.agents/chrome-lock.sh`, then targeted `record|device|inspect` tests twice after the fix. Run `air format --check .` and `jarl check .` before final commit.

## Handoff

To be filled after implementation.
