**Use the `btw` CLI** for R package development tasks (`btw pkg` — check, test, document; also source lookup via `btw pkg src`) and for reading package documentation (`btw docs` — help pages, vignettes, NEWS). See `btw --help` for usage.

**Kata is the system of record** (the `kata` CLI issue tracker; the session environment provides its usage conventions). One issue per work item; decisions and dispositions land on issues, never only in chat scrollback. See `kata quickstart --agent` for usage details.

**roborev provides external review, requested manually.** Do NOT install the post-commit hook. Request one review per completed unit of work (a coherent feature slice, possibly several commits), never per commit: `roborev review <sha>`, then `roborev show <job_id> --job` for the result. Close reviews when the fix is committed (`roborev close`).

## R Package Development

1. **Internal helpers are undocumented by default.** Do not write roxygen for
   internal helpers. Exception: an unusually complicated helper may carry a
   short roxygen block, which must end with `@noRd`.
1. **Test files mirror source files.** `R/foo.R` -> `tests/testthat/test-foo.R`.
   Tests for a function live in the file named after the R file where its
   primary logic lives.
1. **Use `cli` for all errors and informational messages.** Errors via
   `cli::cli_abort()` (keep `class =` for classed errors); informational output
   via `cli::cli_inform()`/`cli::cat_line()`. Prefer cli inline markup
   (`{.arg}`, `{.val}`, `{.fn}`) over `sprintf()`. rlang's argument checkers
   (`check_dots_empty()`, `check_string()`, etc.) are fine and stay.
1. **Validate user input with rlang's `check_*()` functions** (`check_bool()`,
   `check_string()`, `check_number_decimal()`, `check_number_whole()`,
   `check_data_frame()`; DESCRIPTION pins rlang >= 1.2.0 for these). Where no
   `check_*()` exists for the type, use `stop_input_type()`. Hand-rolled
   `cli::cli_abort(class = ...)` checks are reserved for conditions that need
   a `paparazzi_error_*` class (e.g. because tests match on it).

## Work Mechanics

1. **One kata issue per work item**, parented appropriately; claim with
   `kata claim <ref>`, keep status truthful, close with evidence
   (`kata close <ref>`). Never end a session with a claimed issue left
   hanging — comment with what remains.
1. **Small conventional commits**, one logical change each, kata refs in the
   body.
1. **Escalate early on these tripwires** — each is a known money pit:
   anything touching the init/restore window; anything that wants a timer,
   a queue, or a second flag to manage ordering; anything that stores
   display-shaped content; anything where the fix is "add a guard for the
   guard." Stop and consult before building.
1. **All comments are load-bearing** — only use comments to capture context that
   will be relevant in the future. Never include local refs (like kata or
   roborev), always inline important context from those refs. Regardless,
   comments should be minimal and included only when necessary.
