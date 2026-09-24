**Use the `btw` CLI** for R package development tasks (`btw pkg` — check, test, document; also source lookup via `btw pkg src`) and for reading package documentation (`btw docs` — help pages, vignettes, NEWS). See `btw --help` for usage.

**Kata is the system of record** (the `kata` CLI issue tracker; the session environment provides its usage conventions). One issue per work item; decisions and dispositions land on issues, never only in chat scrollback. See `kata quickstart --agent` for usage details.

**roborev provides external review, requested manually.** We DO NOT USE the post-commit hook. Request one review per completed unit of work, never per commit: `roborev review <sha>`, then `roborev show <job_id> --job`. Close reviews when the fix is committed (`roborev close`).

## R Package Development

1. **Internal helpers are undocumented by default.** No roxygen; an unusually
   complicated helper may have a short block ending in `@noRd`.
1. **Test files mirror source files.** `R/foo.R` -> `tests/testthat/test-foo.R`.
1. **Use `cli` for errors and messages:** `cli::cli_abort()` for errors,
   `cli::cli_inform()`/`cli::cat_line()` for output; cli markup (`{.arg}`,
   `{.val}`, `{.fn}`) over `sprintf()`.
1. **Validate user input with rlang's `check_*()` functions** (`check_bool()`,
   `check_string()`, `check_number_*()`, `check_data_frame()`); use
   `stop_input_type()` where no `check_*()` fits; hand-rolled classed errors
   only when the class is needed.

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
