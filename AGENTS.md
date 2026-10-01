# NA

**Use `btw`** for R package development (`btw pkg`, `btw pkg src`) and
package documentation (`btw docs`). See `btw --help`.

**Kata is the system of record.** One issue per work item; record
decisions and dispositions there. See `kata quickstart --agent`.

**Request roborev manually**, once per completed unit, not per commit;
no post-commit hook. Use `roborev review <sha>`, then
`roborev show <job_id> --job`; close reviews after fixes are committed.

## R Package Development

1.  **Preserve API contracts.** `pz_find*()` returns a context visibly
    without mutating the page. `file://` lacks bfcache; recommend HTTP
    instead of navigation workarounds.
2.  **Style checks:** `air format --check .` and `jarl check .`. Put
    exported functions before private helpers, with one blank line
    between top-level definitions.
3.  **Internal helpers are undocumented by default.** No roxygen; an
    unusually complicated helper may have a short block ending in
    `@noRd`.
4.  **Test files mirror source files.** `R/foo.R` -\>
    `tests/testthat/test-foo.R`.
5.  **Use `cli` for errors and messages:**
    [`cli::cli_abort()`](https://cli.r-lib.org/reference/cli_abort.html)
    for errors,
    [`cli::cli_inform()`](https://cli.r-lib.org/reference/cli_abort.html)/[`cli::cat_line()`](https://cli.r-lib.org/reference/cat_line.html)
    for output; cli markup (`{.arg}`, `{.val}`, `{.fn}`) over
    [`sprintf()`](https://rdrr.io/r/base/sprintf.html).
6.  **Validate user input with rlang’s `check_*()` functions**
    (`check_bool()`, `check_string()`, `check_number_*()`,
    `check_data_frame()`); use `stop_input_type()` where no `check_*()`
    fits; hand-rolled classed errors only when the class is needed. Use
    paparazzi’s own checkers in `R/utils-check.R`
    (e.g. `check_character()`, `check_page()`) where they fit; extend
    that file as new shared checkers come up.
7.  **Test scope:** On feature branches, run tests mirroring changed
    sources and cross-module seams named in the kata task; a full run is
    optional at the implementer’s discretion. Run `btw pkg test` on main
    as the merge gate; filtered tests may miss integration breaks.
8.  **Serialize competing Chrome-heavy runs:** use
    `.agents/chrome-lock.sh` when test runs across worktrees might
    overlap and overload Chrome. Don’t lock browser-free or isolated
    runs. Judge test results by reported FAIL/WARN, not exit code or
    variable PASS counts.

## Agent Skill and Vignettes

The `agents*.Rmd` vignettes are thin wrappers that embed
`inst/skills/paparazzi/` files at render time
(`vignettes/skill-source.R`); edit skill content in the skill directory,
never in the vignettes. `skill-source.R` rewrites
`references/<topic>.md` links to `agents-<topic>.html`, so reference
topic names must match the vignette names. When adding, renaming or
removing a topic, update the `references/*.md` file, its entry in
SKILL.md’s References list, the matching `agents-*.Rmd` wrapper, and
`_pkgdown.yml` together.

## Rendered Docs

README.md and pkgdown/index.md are rendered from man/fragments/\*.Rmd —
edit the fragments, then rebuild: `build_readme()` for the README,
[`pkgload::load_all(); rmarkdown::render("pkgdown/index.Rmd")`](https://pkgload.r-lib.org/reference/load_all.html)
for pkgdown/index.md. Never edit the rendered files directly.

## Work Mechanics

1.  **One kata issue per work item**, parented appropriately; claim with
    `kata claim <ref>`, keep status truthful, close with evidence
    (`kata close <ref>`). Never end a session with a claimed issue left
    hanging — comment with what remains.
2.  **Small conventional commits**, one logical change each,
    kata/roborev refs in the body, never the subject.
3.  **Escalate early on these tripwires** — each is a known money pit:
    anything touching the init/restore window; anything that wants a
    timer, a queue, or a second flag to manage ordering; anything that
    stores display-shaped content; anything where the fix is “add a
    guard for the guard.” Stop and consult before building.
4.  **All comments are load-bearing** — only use comments to capture
    context that will be relevant in the future. Never include local
    refs (like kata or roborev), always inline important context from
    those refs. Regardless, comments should be minimal and included only
    when necessary.
