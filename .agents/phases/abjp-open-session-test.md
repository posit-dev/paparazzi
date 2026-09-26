# Flaky open-session cleanup test (paparazzi#abjp)

Signed off: orchestrator.

## Scope and mechanism

- Change tests only: the registry of Chromote sessions can lose a closed session when `Target.detachedFromTarget` is dispatched via `later()`. Its membership is not evidence that `pz_open()` did or did not close the page.
- Compare browser `Target.getTargets()` page target IDs before the failed `pz_open()` and after cleanup. Keep the invalid-timezone error assertion: it proves the session and page were created before failure. If target removal is asynchronous, use a brief bounded poll to allow cleanup to appear; never inspect the private session registry.
- First show the revised test fails with the deferred `page$close()` in `R/open.R` temporarily disabled, then restore that line and show it passes. Do not commit a production-code change.
- Inspect `test-open.R` and `test-device.R` for the same registry assumption and repair any matching race. Stress the targeted open tests with five serialized Chrome runs; record per-run totals.

## Handoff

- Landed: `test-open.R` checks browser `Target.getTargets()$targetInfos` page target IDs before and after a failed timezone setting, with a three-second bounded poll for asynchronous target removal. The invalid-timezone assertion remains. Removed the false claim that Chromote keeps closed sessions in its private registry. No production code changed.
- Discrimination: with only the deferred `page$close()` line in `R/open.R` temporarily commented out, targeted open tests failed `[ FAIL 2 | WARN 0 | SKIP 0 | PASS 151 ]`; the revised test failed at `expect_length(new_ids, 0L)` (actual length 1). The other failure was the existing owned-app cleanup test. Restored the line before committing; `R/open.R` has no diff.
- Verification: baseline before edits `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 154 ]`. After restoring cleanup, five consecutive serialized open-test runs each reported `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 153 ]`. `air format --check .` and `jarl check .` passed.
- Audited `test-open.R` and `test-device.R`: no other test reads Chromote's private `sessions` registry; no change needed in `test-device.R`. Nothing else remains in this task; the orchestrator will run the full main gate.
