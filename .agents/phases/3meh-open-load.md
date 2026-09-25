# Open-page load navigation (3meh)

Source: paparazzi#3meh, linked n4f2 review 1269, .agents/SPEC.md (Sessions and apps), .agents/phases/device-nav.md. Ownership: `R/open.R`, `tests/testthat/test-open.R`, this note. Base: task/3meh; main's post-dbzt full test gate is still running.

## Mechanism decision (before code)

`pz_open()` creates a new session whose outgoing `about:blank` document can already report `readyState = "complete"` when `Page.navigate` returns. For the new-session `wait = "load"` path, register `Page.frameNavigated(wait_ = FALSE)` before `Page.navigate`, as the Shiny branch already does. After the existing `errorText` check, await the returned destination commit with the existing `nav_await(page, navigated, what = "page navigation")` only when `nav$loaderId` exists, then call `wait_for_load()` and retain `device_css_reapply()`. Share the single registration and conditional await between load and Shiny; leave `wait = "none"` and the wrapped-session branch unchanged. Fragment/same-document navigations without a loaderId must not wait for an event that will never arrive; navigation errors must still fail before awaiting. No timer, queue, extra flag, or init/restore-window edit.

## Test seam and gate

After the coordinator explicitly releases work: add a real `pz_open(nav_fixture_url("slow"), wait = "load")` regression in `test-open.R`. Confirm an independent fresh session's `about:blank` is complete; wrap the real `nav_await` with `local_mocked_bindings`, capture the navigation-history URL immediately after the await, and assert the committed URL equals the slow fixture. Also assert destination `readyState = "complete"`; title alone cannot discriminate the timing race. Verify the new test red before changing `R/open.R`, then green using `btw pkg test -f 'open|nav'` from this worktree. Existing Shiny explicit/auto commit test, open none/auto/wrapped/error tests and nav fragment/error tests are cross-path checks. Only run `btw pkg document` if roxygen changes (none planned); no full suite here.

Gate: coordinator released work after main's post-dbzt gate passed (1978 pass, zero fail/warn/skip). Do not add a timer, queue, extra flag, or init/restore-window edit; stop and consult if any project tripwire appears. Make one conventional commit with the kata ref in the body; report results and handoff on the issue. Do not merge, push, review with roborev, or close this issue.

Signed off: teammate-2, before code or tests.

## Handoff

- Landed: real slow-file open regression failed on original `R/open.R` with the two committed destination URLs missing (203 pass, 1 fail); then shared the existing Shiny commit anchor with load without changing none/wrapped paths.
- Next: coordinator owns merge and any broader gate; task is ready for handoff after the scoped commit. Targeted `btw pkg test -f 'open|nav' --reporter minimal` passed twice with 204 pass, zero fail/warn/skip; one intermediate run had a non-Shiny-page failure in the existing shared-handle Shiny test, which passed on immediate rerun without changes to that path.
- Provisional: no new ordering mechanism; the existing Shiny test's intermittent failure was not modified under this task.
