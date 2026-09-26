# Close test workers' Chrome browsers (paparazzi#yqm8)

Signed off: orchestrator.

## Scope and mechanism

Fix only the test-suite profile leak: add `tests/testthat/setup-chrome.R` to register a `testthat::teardown_env()` deferred close of the default chromote browser. Guard with `chromote::has_default_chromote_object()` so idle workers never start Chrome, and use `try(..., silent = TRUE)` around close. Verify chromote 0.5.1's actual API; its `Chromote$close(wait = TRUE)` can wait up to 10 seconds.

Do not change `PaparazziPage$close()` or `pz_open()` behavior: closing the shared default browser in package code is a user-facing decision outside this issue. Correct the `PaparazziPage$close()` roxygen wording to describe closing the tab/session, retain "Idempotent.", regenerate `man/` with `btw pkg document`.

## Verification

The regression is process-level, not a unit expectation: under one Chrome lock per run, compare headless `scoped_dir*` profile directories before and five seconds after targeted parallel `test_local(filter = "open|device|js")`; inspect orphan PPID-1 Chrome processes and the test totals. Measure first without teardown, then with it. Testthat's parallel workers allow only about one second for deferred teardown before termination; if `Browser.close` is too slow, report that rather than adding ordering/timing workarounds. Consider a test-only known `--user-data-dir` only if needed and simple; do not implement otherwise.

## Execution

Commit this phase note before changing code. Record the unfixed process-level red measurement, then add the teardown and repeat under the Chrome lock. Check `air format --check .` and `jarl check .`, commit the implementation and final handoff separately, and comment on the claimed kata issue without closing it.

## Handoff

Pending verification and implementation.
