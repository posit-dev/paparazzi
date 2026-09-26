# Navigation after a completed action (paparazzi#npaj)

Signed off: orchestrator, per garrick's tripwire sign-off on npaj.

## Problem and mechanism

A fast link may finish loading before `pz_wait_for_navigation()` snapshots the document. The existing snapshot/settle check then sees no navigation and times out despite the preceding click.

Superseded by `.agents/phases/xwzz-bfcache-nav.md`: the signed-off main-frame loaderId captured before each action replaces the R wall-clock timestamp comparison while retaining the wait-start snapshot evidence.

## Existing expectations and test plan

- The existing no-navigation test starts on a complete document and must time out; add a button-click-then-wait case that also times out.
- The existing delayed JS navigation (starts after wait), pending navigation (with scope reset), and clicked link (with scope reset and stale-scope error) still pass on the original wait-start evidence where applicable.
- Add a fast `nav-a.html` link to `nav-b.html`; wait until the target document is complete *before* calling `pz_wait_for_navigation()`, then assert click-then-wait succeeds and resets the scope. A second wait on the same page times out.
- First run the new test red, then implement and run `test_local(filter = "wait|actions|nav|shiny-input")`; document via `btw pkg document`, supersede the known-hole note, record totals and rerun any transient timeout file serially once.

## Handoff

- Landed: red-first regression (7b9dd0c; one expected failure), action-start comparison and documentation (2d748de); `btw pkg document` ran.
- Next: no code work pending; targeted tests: FAIL 0 / WARN 0 / SKIP 0 / PASS 433. No transient timeout file needed a serial rerun.
- Provisional: none; the wall-clock assumption is superseded by `.agents/phases/xwzz-bfcache-nav.md`.
