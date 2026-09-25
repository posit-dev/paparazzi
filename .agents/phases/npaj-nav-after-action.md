# Navigation after a completed action (paparazzi#npaj)

Signed off: orchestrator, per garrick's tripwire sign-off on npaj.

## Problem and mechanism

A fast link may finish loading before `pz_wait_for_navigation()` snapshots the document. The existing snapshot/settle check then sees no navigation and times out despite the preceding click.

Use the signed-off R timestamp fallback (b). `PaparazziPage` holds one private last-action-start field, exposed through a page active binding. A shared `action_start(ctx)` helper records `as.numeric(Sys.time()) * 1000` before each user-level action's first browser interaction; each exported action calls it (including the root/no-target branches of press, blur, type and scroll, and `pz_set_shiny_input`). Browser-side token capture (a) would require an extra CDP evaluation for the CDP-only press/click/scroll paths, or invasive changes to their dispatch and heterogeneous JS probes. The fallback relies on R and Chrome using the same machine wall clock; `performance.timeOrigin` is the document's epoch milliseconds. The settled document passes when it is newer than the last action start OR when the existing wait-start snapshot indicates a new/in-flight document. Keep the existing load and settle requirements. A successful wait clears the field in `wait_nav_reset()` so a second wait without another action times out; `wait = 'none'` and navigation resets clear it too. `pz_nav_*()` and `pz_js()` do not record actions.

## Existing expectations and test plan

- The existing no-navigation test starts on a complete document and must time out; add a button-click-then-wait case that also times out.
- The existing delayed JS navigation (starts after wait), pending navigation (with scope reset), and clicked link (with scope reset and stale-scope error) still pass on the original wait-start evidence where applicable.
- Add a fast `nav-a.html` link to `nav-b.html`; wait until the target document is complete *before* calling `pz_wait_for_navigation()`, then assert click-then-wait succeeds and resets the scope. A second wait on the same page times out.
- First run the new test red, then implement and run `test_local(filter = "wait|actions|nav|shiny-input")`; document via `btw pkg document`, supersede the known-hole note, record totals and rerun any transient timeout file serially once.
