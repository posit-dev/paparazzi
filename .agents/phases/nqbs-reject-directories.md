# Reject directories in pz_set_files() (paparazzi#nqbs)

Signed off: orchestrator.

## Scope and mechanism

- `check_file_paths()` in `R/actions.R` checks missing paths first, then rejects directories with a pluralized `paparazzi_error_input` from `cli::cli_abort(call = call)`. Keep the normalized-path return value unchanged.
- `pz_set_files()` already documents `files` as paths to existing local files; no documentation change is needed.
- Add a discriminating regression in `tests/testthat/test-actions.R` beside the current path-validation test. There are no snapshots for these messages; assert the error class and directory wording directly.
- Run the targeted actions tests under the Chrome lock, plus `air format --check .` and `jarl check .`.

## Handoff

- Landed: `check_file_paths()` now rejects directories after checking for missing paths, preserving normalized-path returns; the actions regression covers singular and plural directory messages and missing-path precedence. No docs or snapshots needed (the existing parameter description is accurate, and this file has no message snapshots).
- Red before fix: `[ FAIL 1 | WARN 0 | SKIP 0 | PASS 270 ]` (`pz_set_files(page, dir, target = "#file")` did not throw `paparazzi_error_input`). Green after fix: targeted actions tests `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 273 ]`.
- `air format --check .` and `jarl check .` passed. Next: orchestrator review and full suite on main; this issue remains open for the orchestrator.
