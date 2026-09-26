# Tidyverse style pass (paparazzi#jymc)

Signed off: orchestrator, per garrick's request to bring the package in line with the tidyverse style guide.

## Scope

Base: main `c9f2f20`, already formatted with `air` and clean under `jarl check .`. This pass handles style issues that need judgment and that neither tool catches:

- comments that narrate the code; stale comments
- `return()` as the final expression
- file order: documented exports before private helpers
- roxygen conventions and drift between docs and code
- unclear internal names
- redundant wrappers or checks, removed only after the callers are checked
- cli error wording, where the gain is clear

Out of scope:

- `|>` and `\(x)`, because the package supports R >= 4.0.0
- public renames, and changes to defaults, return values, condition classes, or error timing
- JavaScript embedded in R strings
- test design

Anything found that goes beyond style becomes a backlog issue.

## Mechanism

1. Five read-only reviewers, one per file group (findings in `/tmp/pz-style/findings-{a..e}.md`).
2. The orchestrator triages the findings and records the accepted ones in `/tmp/pz-style/accepted-*.md`.
3. low-aws agents apply the accepted edits. Each works in its own worktree on a disjoint set of files, then runs `air format --check .`, `jarl check .`, and the targeted tests for the files it touched.
4. The orchestrator merges the branches, runs the full gate under `/tmp/pz-chrome-lock.sh`, and requests one roborev review for the whole unit.

## Decisions

- garrick approved raising the minimum to R >= 4.1.0, because examples, README and vignettes already use `|>` and R CMD check parses Rd examples. Existing code isn't being converted to `\(x)`.
- Out-of-scope bugs went to the backlog: `nqbs` (`pz_set_files()` accepts directories), `wny8` (a `call =` forwarding gap in `pz_get_elements()`; JS `-0` loses its sign), `fjjr` (the `tryCatch` retries in `nav.R`/`wait.R` swallow every error).
- Declined as not style: consolidating `els_arg_values()` and `els_values()`; deduplicating `local_outside_testthat()` across test files.

## Handoff

- Landed: merges of style/jymc-a..e (comments, roxygen drift, a `keyCode` local renamed to snake_case, `inspect_scope_rects()` deduplicated, `test-placeholder.R` deleted), the R 4.1 bump, private helpers in `actions.R`/`open.R` moved after the exports (parse-verified: same expressions), and a blank line between top-level definitions (a parse-aware script added blank lines only). The scripts are in `/tmp/pz-style/`.
