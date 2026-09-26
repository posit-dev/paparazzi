# Navigation retry errors (paparazzi#fjjr)

Signed off: orchestrator.

## Scope

Narrow the two navigation-related error handlers in `R/nav.R` and `R/wait.R`, with direct regression tests in their mirrored test files. Do not change navigation ordering or page lifecycle.

## Mechanism

- `nav_history()` retries only chromote's case-insensitive “Not attached to an active page” mid-switch error and a “timed out” chromote command error. The command uses the whole poll budget; retrying its timeout lets `pz_poll()` report its classed “waiting for history navigation” timeout. Other errors propagate.
- `nav_snapshot()` treats context-swap failures and timeouts as an in-flight snapshot, but propagates `paparazzi_error_closed` and `paparazzi_error_js`. The denylist intentionally leaves unenumerated mid-swap chromote errors recoverable.
- Test the internal helpers directly with deterministic failures, preserving existing race-sensitive control flow.

## Handoff

- Landed: `nav_history()` retries only the not-attached and command-timeout errors; `nav_snapshot()` propagates closed-page and JavaScript errors. No navigation ordering or lifecycle changes. `pz_js()` raises the two denied classes via `check_context()` and its `exceptionDetails` handling; its command timeouts come from `cdp_call()`.
- Red then green: the unfixed code failed the new unexpected-history-error and closed-page/JS snapshot assertions (`[ FAIL 3 | WARN 0 | SKIP 0 | PASS 179 ]`). After the fix, targeted `nav|wait` tests report `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 184 ]`.
- `air format --check .` and `jarl check .` passed. No further work on this branch; the orchestrator owns the full-suite merge gate.
