# Resized-viewport recording test under load (paparazzi#3gvk)

Signed off: orchestrator.

## Scope and mechanism

- Investigate the recorder read-only first; stop if the resize exposes a product bug. `pz_device()` applies the new metrics synchronously (`R/device.R:95-104,264-270`). The recorder ticks at `1/fps`, skipping while a capture is pending (`R/record.R:533-550`). Each capture queries fresh `cssVisualViewport` metrics before issuing the screenshot, with no cached clip (`R/record.R:580-625`); an already-issued capture can still return the old size, and its next tick is skipped until it settles. That capture has a page-default-timeout budget (`R/record.R:586-613`). No resize-specific pause or deterministic stale-viewport path was found. Treat the observed delay as load-sensitive rather than change product code.
- ~~Raise the resized-frame poll's 5-second limit to twice the page's default timeout (normally 20 seconds): an old-size pending capture can consume one capture budget before a new-size capture gets its own. A first run with one default timeout (10 seconds) still timed out intermittently, so one budget was insufficient.~~ Superseded by the orchestrator's root cause below. The budget stays at 5 s.
- Ensure kept-frames directories are deleted only after active recordings stop on early test exit. Register a guarded stop defer after each relevant unlink defer (LIFO); use `page_recorder(page)` and its `active` field (`R/record.R:395-400,433,454-463`) because `pz_record_stop()` errors when inactive. Limit this to tests where failure before explicit stop can leave a live recorder.
- Force a local short poll failure on the unfixed test to reproduce the late-write warning, then repeat with the cleanup fix; do not retain the forced timeout. Run the targeted record tests twice, and check formatting/lint.

## Handoff

- Landed: no product changes. The resized-frame poll now permits two capture budgets; all four tests that defer unlinking kept frame directories also defer a guarded recorder stop after starting, so LIFO cleanup stops the recorder before removing frames.
- Red/green: with the local uncommitted 0.01-second timeout, the unfixed cleanup produced `[ FAIL 1 | WARN 1 | SKIP 0 | PASS 423 ]` (late `writeBin()` into a deleted directory); after the cleanup change, the same forced timeout produced `[ FAIL 1 | WARN 0 | SKIP 0 | PASS 419 ]`. Restored the real timeout after this probe. The initial 10-second-budget run timed out once `[ FAIL 1 | WARN 0 | SKIP 0 | PASS 431 ]`, then passed twice `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 443 ]` and `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 438 ]`; raised the budget to two default timeouts for the potential in-flight old-size capture.
- Final targeted `test_local(filter = "record")` runs: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 427 ]` and `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 433 ]`. `air format --check .` and `jarl check .` passed. No deterministic product bug found; the former one-budget intermittent timeout remains evidence of load sensitivity, not proof that a product path is broken. No further work planned in this task.

## Root cause (orchestrator, supersedes the load-only reading above)

The resize is not late. It is reverted. With diagnostics in the failing branch, a heavily loaded run failed 5 of 8 times: after `pz_device(width = 800, height = 600)`, the page still reported the old viewport (`innerWidth` 640 at DPR 2 for css zoom, 320 at DPR 4 for viewport zoom), and 49 more frames were captured at the old size with no capture errors. A deterministic repro without the recorder: issue a clipped `Page.captureScreenshot(fromSurface = TRUE, wait_ = FALSE)`, call `Emulation.setDeviceMetricsOverride` with the new size while it is in flight, and let the capture settle. The page returns to the pre-capture metrics in 20 of 20 runs. Chrome's clipped capture saves the device metrics and restores them afterward, so any metrics override issued during a recorder capture (`R/record.R` `record_capture()`) is silently undone. Load only widens the overlap window. This is a product bug in the recorder/device seam, and the fix needs an ordering decision, so it went to a new issue instead of being patched here.

## Handoff (orchestrator)

- Landed on this branch: only the cleanup-order fix, factored into `defer_record_stop()` in `helper-record.R`. The poll budget is back to 5 s, because a longer wait can't recover a reverted override. Targeted `record` run: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 439 ]`.
- Next: the product fix in the follow-up issue. Until it lands, this test still flakes under load. The flake is real evidence of the bug.
