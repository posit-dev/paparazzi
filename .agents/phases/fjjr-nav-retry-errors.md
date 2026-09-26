# Navigation retry errors (paparazzi#fjjr)

Signed off: orchestrator.

## Scope

Narrow the two navigation-related error handlers in `R/nav.R` and `R/wait.R`, with direct regression tests in their mirrored test files. Do not change navigation ordering or page lifecycle.

## Mechanism

- `nav_history()` retries only chromote's case-insensitive “Not attached to an active page” mid-switch error and a “timed out” chromote command error. The command uses the whole poll budget; retrying its timeout lets `pz_poll()` report its classed “waiting for history navigation” timeout. Other errors propagate.
- `nav_snapshot()` treats context-swap failures and timeouts as an in-flight snapshot, but propagates `paparazzi_error_closed` and `paparazzi_error_js`. The denylist intentionally leaves unenumerated mid-swap chromote errors recoverable.
- Test the internal helpers directly with deterministic failures, preserving existing race-sensitive control flow.

## Handoff

Pending implementation and verification.
