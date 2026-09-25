# Examples on every exported function (v56x)

Signed off: garrick (decisions recorded on paparazzi#v56x).

## Decisions

- Examples drive pages shipped in `inst/examples/`, reached through a new
  export `pz_example(name = NULL)`. Names carry no extension:
  `pz_example("tasks")` returns the path to `inst/examples/tasks.html`;
  `pz_example("tasks-app")` returns the app directory
  `inst/examples/tasks-app/`. `name = NULL` returns the available names.
  An unknown name errors with the list of names.
- Guard: `@examplesIf rlang::is_interactive() && <Chrome found>`. Examples
  never launch Chrome under R CMD check. Because the guard uses
  `rlang::is_interactive()`, a test can set `rlang_interactive = TRUE` and
  run every help page's examples, so examples fail loudly when they rot.
- Examples open a page, show the function in one or two realistic calls,
  and close the page. Output-producing calls (getters, `pz_js()`) are left
  unassigned so the rendered help shows their value.
- Four slices, human check-in after each:
  1. infrastructure (`pz_example()`, example pages, the example test) plus
     pages, apps, navigation, device;
  2. specs, scoping, actions;
  3. expectations, waits, getters (replacing the `\dontrun{}` +
     example.com examples);
  4. recording, framing, cursor, staging, escape hatches.

## Example assets

- `tasks.html`: a small static task tracker. It has a form (title input,
  priority select, "urgent" checkbox, disabled-until-typed Add button), a
  scrollable task list whose items carry a title, a priority badge and a
  Done button, a notes textarea, an attachment file input, a hidden help
  panel with a toggle, and a fragment link for history examples. Plain
  JavaScript, no network.
- `tasks-app/`: the same idea as a Shiny app, for `pz_app()`,
  `pz_open()` on apps, `pz_set_shiny_input()` and
  `pz_wait_for_shiny_idle()`. Depends only on shiny.

## Handoff
