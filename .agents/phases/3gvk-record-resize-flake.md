# Resized-viewport recording test under load (paparazzi#3gvk)

Signed off: orchestrator.

## Scope and mechanism

- Investigate the recorder read-only first; stop if the resize exposes a product bug. `pz_device()` applies the new metrics synchronously (`R/device.R:95-104,264-270`). The recorder ticks at `1/fps`, skipping while a capture is pending (`R/record.R:533-550`). Each capture queries fresh `cssVisualViewport` metrics before issuing the screenshot, with no cached clip (`R/record.R:580-625`); an already-issued capture can still return the old size, and its next tick is skipped until it settles. That capture has a page-default-timeout budget (`R/record.R:586-613`). No resize-specific pause or deterministic stale-viewport path was found. Treat the observed delay as load-sensitive rather than change product code.
- Raise the resized-frame poll's 5-second limit to twice the page's default timeout (normally 20 seconds): an old-size pending capture can consume one capture budget before a new-size capture gets its own. A first run with one default timeout (10 seconds) still timed out intermittently, so one budget was insufficient.
- Ensure kept-frames directories are deleted only after active recordings stop on early test exit. Register a guarded stop defer after each relevant unlink defer (LIFO); use `page_recorder(page)` and its `active` field (`R/record.R:395-400,433,454-463`) because `pz_record_stop()` errors when inactive. Limit this to tests where failure before explicit stop can leave a live recorder.
- Force a local short poll failure on the unfixed test to reproduce the late-write warning, then repeat with the cleanup fix; do not retain the forced timeout. Run the targeted record tests twice, and check formatting/lint.

## Handoff

- Landed: no product changes. The resized-frame poll now permits two capture budgets; all four tests that defer unlinking kept frame directories also defer a guarded recorder stop after starting, so LIFO cleanup stops the recorder before removing frames.
- Red/green: with the local uncommitted 0.01-second timeout, the unfixed cleanup produced `[ FAIL 1 | WARN 1 | SKIP 0 | PASS 423 ]` (late `writeBin()` into a deleted directory); after the cleanup change, the same forced timeout produced `[ FAIL 1 | WARN 0 | SKIP 0 | PASS 419 ]`. Restored the real timeout after this probe. The initial 10-second-budget run timed out once `[ FAIL 1 | WARN 0 | SKIP 0 | PASS 431 ]`, then passed twice `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 443 ]` and `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 438 ]`; raised the budget to two default timeouts for the potential in-flight old-size capture.
- Final targeted `test_local(filter = "record")` runs: `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 427 ]` and `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 433 ]`. `air format --check .` and `jarl check .` passed. No deterministic product bug found; the former one-budget intermittent timeout remains evidence of load sensitivity, not proof that a product path is broken. No further work planned in this task.
