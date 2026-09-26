# Flaky open-session cleanup test (paparazzi#abjp)

Signed off: orchestrator.

## Scope and mechanism

- Change tests only: the registry of Chromote sessions can lose a closed session when `Target.detachedFromTarget` is dispatched via `later()`. Its membership is not evidence that `pz_open()` did or did not close the page.
- Compare browser `Target.getTargets()` page target IDs before the failed `pz_open()` and after cleanup. Keep the invalid-timezone error assertion: it proves the session and page were created before failure. If target removal is asynchronous, use a brief bounded poll to allow cleanup to appear; never inspect the private session registry.
- First show the revised test fails with the deferred `page$close()` in `R/open.R` temporarily disabled, then restore that line and show it passes. Do not commit a production-code change.
- Inspect `test-open.R` and `test-device.R` for the same registry assumption and repair any matching race. Stress the targeted open tests with five serialized Chrome runs; record per-run totals.

## Handoff

Pending.
