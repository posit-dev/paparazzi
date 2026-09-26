# Resized-viewport recording test under load (paparazzi#3gvk)

Signed off: orchestrator.

## Scope and mechanism

- Investigate the recorder read-only first; stop if the resize exposes a product bug. `pz_device()` applies the new metrics synchronously (`R/device.R:95-104,264-270`). The recorder ticks at `1/fps`, skipping while a capture is pending (`R/record.R:533-550`). Each capture queries fresh `cssVisualViewport` metrics before issuing the screenshot, with no cached clip (`R/record.R:580-625`); an already-issued capture can still return the old size, and its next tick is skipped until it settles. That capture has a page-default-timeout budget (`R/record.R:586-613`). No resize-specific pause or deterministic stale-viewport path was found. Treat the observed delay as load-sensitive rather than change product code.
- Raise the resized-frame poll's 5-second limit to the page's default timeout (normally 10 seconds), consistent with a single capture's budget.
- Ensure kept-frames directories are deleted only after active recordings stop on early test exit. Register a guarded stop defer after each relevant unlink defer (LIFO); use `page_recorder(page)` and its `active` field (`R/record.R:395-400,433,454-463`) because `pz_record_stop()` errors when inactive. Limit this to tests where failure before explicit stop can leave a live recorder.
- Force a local short poll failure on the unfixed test to reproduce the late-write warning, then repeat with the cleanup fix; do not retain the forced timeout. Run the targeted record tests twice, and check formatting/lint.

## Handoff

Pending.
