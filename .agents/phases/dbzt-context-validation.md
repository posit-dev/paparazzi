# Phase note: context validation before scope access (paparazzi#dbzt)

Signed off by teammate-1, 2026-09-25, before code changes. Requirements: `.agents/SPEC.md` (Chaining, Scoping, Actions, Getters) and the dbzt issue. This is a maintenance fix, not a change to target resolution or pinned-scope lifetime.

## Mechanism and boundary

- Invalid `ctx` with `target = NULL` must raise `paparazzi_error_context`, rather than fail reading `ctx$scope`. The existing `check_context()` in `R/utils.R` owns the error type and closed-page behavior; do not add a new checker or error class.
- `get_impl()` in `R/get.R` calls `scope_root()` before reaching `loc_resolve()` when `target = NULL`, unlike `pz_get_count()`, which already checks its context. Put `check_context(ctx, call = call)` at the start of `scope_root()` in `R/scope.R`, before its `scope_top()` call. That shared scope-use entry also protects internal action resolution via `action_elements()`. Retain existing public action validation; `pz_type()` calls `scope_top()` directly only after its own check. Do not change `scope_top()`'s raw-stack purpose, target resolution, or detach checks.
- Scope of edits after coordinator release: `R/scope.R`, tests in `tests/testthat/test-get.R`, `tests/testthat/test-actions.R`, and `tests/testthat/test-scope.R` only if needed. `R/get.R`/`R/actions.R` are allowed if inspection or red tests show an uncovered path, not as a second redundant guard. Any other uncovered source path is an escalation to the coordinator, not an opportunistic edit.

## Test seams and release gate

- Wait for the coordinator's explicit go-ahead after the main baseline finishes. Before then, no production edits and no tests.
- Red first: in `test-get.R`, assert `pz_get_text(1)` (implicit NULL target) raises `paparazzi_error_context`; consider `pz_get_attr(1, "id")` or a tibble getter as another wrapper through `get_impl()`. In `test-actions.R`, exercise `action_elements(1, NULL)` as the internal scope-use seam (should fail before the fix), plus `pz_click(1)` as the public contract (already guarded). In `test-scope.R`, a direct `scope_root(1)` assertion pins validation before `scope_top()`, only if the action seam does not establish it sufficiently. Use `expect_error(..., class = ...)`, not message snapshots. Existing browser-backed scoped/root tests cover unchanged valid behavior and detached scope behavior.
- Run only targeted filters `get|actions|scope` via `testthat::test_local(filter = "get|actions|scope")` for red and green; use `btw` for R package commands per `AGENTS.md`. Never run the full suite; the coordinator owns the main gate. Capture the failing-before/passing-after evidence, commit one conventional fix with `paparazzi#dbzt` in its body, and comment on kata with evidence and handoff. Do not close, merge, push, or request roborev review.

## Handoff

- Prepared before release: issue claimed and branch stamped; no production code or tests run during main baseline. Coordinator then reported main `btw pkg test` green (1974 passes) and released implementation.
- Red: `Rscript -e 'testthat::test_local(filter = "get|actions", reporter = "summary")'` failed at `pz_get_text(1)` and `action_elements(1, NULL)` with the raw `ctx$scope` error (exit 1). The other assertions in those tests were behind the first failures.
- Green: after adding `check_context()` before `scope_top()` in `scope_root()`, `Rscript -e 'testthat::test_local(filter = "get|actions|scope", reporter = "summary")'` passed (exit 0). No full suite run on the task branch.
- Next: one scoped conventional commit and kata evidence handoff; coordinator owns main gate. No merge, review request, issue close or push here.
