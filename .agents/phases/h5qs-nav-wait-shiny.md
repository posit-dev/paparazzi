# Navigation wait on Shiny pages (h5qs)

Source: paparazzi#h5qs (latest scope comment), .agents/SPEC.md (Sessions and apps; Waits vs. expectations). Branch: fix/h5qs.

## Signed-off mechanism

Explicit `wait = "shiny"` in `pz_nav_goto()`, `pz_nav_reload()`, and `pz_wait_for_navigation()` keeps the existing navigation commit/load settle unchanged, then calls `pz_wait_for_shiny_idle()`. The latter uses the page default timeout for nav, or the caller's timeout for `pz_wait_for_navigation()`. `wait = "none"` still skips every settle. Back/forward (no wait argument) use auto after their existing load settle, only when a history entry was reached.

One shared `nav_settle_shiny(page, wait, timeout)` helper runs after load settles for all five entry points. For `auto`, read the page's existing private `owned_app_` or `shared_app_` reference (same internal R6 access pattern used elsewhere in the package); only if app-backed, compare the landed document's `location.origin` via one `pz_js()` read to the origin of `app$url` (the app handle builds `http://127.0.0.1:<port>/`; strip the trailing slash). A different origin (including `file://`) resolves to load; plain URL pages stay load without a JS read. Explicit shiny does not require app ownership. Keep pz_open() unchanged. Do not add a timer, queue, second ordering flag, guard for a guard, or touch init/restore; stop if one becomes necessary.

## Tests and verification

Baseline targeted `test_local(filter = "wait|nav|open")` green: FAIL 0 / WARN 0 / SKIP 0 / PASS 294. First add red integration cases in `test-nav.R` / `test-wait.R` with existing `shiny-idle` delayed-output fixture and app helpers: explicit shiny goto and post-action wait, app-backed auto, app-to-file auto, plain URL auto; cover reload and back/forward where practical. Prove red before production edits. Then implement, update only wait-behavior roxygen sentences in `R/nav.R` / `R/wait.R`, run `btw pkg document`, targeted test command and report totals. On a transient timeout rerun its file serially once and report both. Mark superseded text in expectations-waits.md and device-nav.md. Make small conventional commits with `Refs: paparazzi#h5qs` in bodies. Do not merge, push, request review, or close issue. Finish with three-line handoff and kata comment including shas and totals.

Signed off: orchestrator, per garrick's decision on h5qs.

## Handoff

- Landed: 13a9f6d adds one post-load Shiny settle helper shared by all five navigation waits, app-origin auto resolution, and red-first integration coverage; generated help and stale phase notes track the new rule.
- Next: orchestrator reviews and runs the full-suite main merge gate; do not merge, push, request roborev, or close h5qs in this worktree. Targeted test: FAIL 0 / WARN 0 / SKIP 0 / PASS 304.
- Provisional: none. An earlier test of back into a bfcache-restored Shiny document timed out twice because its socket did not reconnect; the final test checks back to a file origin instead, and no reconnect guard or scheduling mechanism was introduced.
