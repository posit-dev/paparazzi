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

- Landed testthat setup that defers a guarded `chromote::default_chromote_object()$close()` in `teardown_env()`, swallowing shutdown errors. Verified installed chromote 0.5.1 exposes `has_default_chromote_object()` and `Chromote$close(wait = TRUE)` (up to 10 seconds). No package runtime behavior changed.
- Corrected `PaparazziPage$close()` wording while retaining "Idempotent." `btw pkg document` regenerated `man/PaparazziContext.Rd`: this is the actual roxygen topic containing the `PaparazziPage` alias and `$close()` method, not `man/PaparazziPage.Rd`.
- Regression red (without teardown): under one Chrome lock, `test_local(filter = "open|device|js")` started 3 processes; profiles before 72, after 75 (+3 after 5 seconds); existing PPID-1 headless Chrome orphan count 7 before and 7 after (0 new). `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 254 ]`, exit 0: the red signal was leaked profiles, not failing test assertions.
- Regression green (with teardown): started 3 processes; profiles before 76, after 76 (+0 after 5 seconds); orphan count 7 before and 7 after (0 new). `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 254 ]`, exit 0. The extra pre-existing profile between runs is consistent with concurrent Chrome users outside this lock; before/after differences were measured within each lock.
- `air format --check .` and `jarl check .` passed. No fallback `--user-data-dir` workaround needed; the parallel teardown grace was sufficient for this targeted run. Do not close the issue until the orchestrator's main-branch gate.
