# Reject directories in pz_set_files() (paparazzi#nqbs)

Signed off: orchestrator.

## Scope and mechanism

- `check_file_paths()` in `R/actions.R` checks missing paths first, then rejects directories with a pluralized `paparazzi_error_input` from `cli::cli_abort(call = call)`. Keep the normalized-path return value unchanged.
- `pz_set_files()` already documents `files` as paths to existing local files; no documentation change is needed.
- Add a discriminating regression in `tests/testthat/test-actions.R` beside the current path-validation test. There are no snapshots for these messages; assert the error class and directory wording directly.
- Run the targeted actions tests under the Chrome lock, plus `air format --check .` and `jarl check .`.

## Handoff

Pending implementation and verification.
