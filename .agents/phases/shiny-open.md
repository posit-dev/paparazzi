# Shiny page opening (fy5e)

Source: .agents/SPEC.md, Sessions and apps (Opening pages, Apps, Page lifecycle); base main 106e75e.

## Mechanism and ownership

- Dispatch `ChromoteSession` unchanged; reject `shiny.appobj` with the existing run-separately advice. A `PaparazziApp` handle supplies its URL, but stays caller-owned. Existing local directories and recognized app file names start through `pz_app(path, envvars, shiny_options, timeout)`; the resulting app belongs to the new page. Other files, URL strings and errors retain their existing paths. `pz_app()` already owns spawn/readiness/shutdown: no parallel process mechanism.
- Add an optional owned-app reference to `PaparazziPage`, set when constructing the page. `close()` closes the browser session and stops *only* its owned app, on explicit close or block/form exit. On opening errors before a page is constructed, stop the just-started app; after construction the existing deferred page-close path takes responsibility. `pz_with_page()` and `pz_local_page()` continue to close pages only.
- Resolve `wait = 'auto'` against the target type: Shiny means conceptually `shiny`, but temporarily use `load` until n4f2. The single named seam is `open_wait_mode(wait, is_shiny_app)`; n4f2 replaces the Shiny auto branch and supplies idle behavior. Explicit `wait = 'shiny'` remains unsupported.
- Validation and dots remain as before; use app validation (`pz_app`) for app-only options. No init/restore window, timer, queue, ordering flag, display-shaped state or layered guards.

## Test seams

- First run local baseline `btw pkg test --filter 'open|app|context'` on this branch; base full suite was green (1829 assertions). Add red integration tests in `test-open.R` for owned dir/file, shared handle, option/env forwarding, failure cleanup and block forms. Use the existing Shiny lifecycle fixture/helper without editing them; add only task-specific fixtures if essential. Test page-close ownership through actual port reachability and app-handle liveness; verify wrapped session and URL/file behavior with existing tests. Run targeted filter and `btw pkg document`; cross-module seam is `test-app.R` (pz_app readiness/stop) plus `test-nav.R` where navigation relies on page lifecycle.

Signed off: teammate-1, before feature code.

## Handoff

- Landed: directory/app.R (and recognized file variants) start page-owned apps; handle pages are shared; owned-app stop on close/open failure, with block cleanup and option forwarding verified. Baseline 139 passes; red test demonstrated six failures before implementation.
- Next: n4f2 replaces the Shiny auto `load` placeholder at `open_wait_mode()` and implements actual connected/idle waiting; orchestrator runs full suite on main as merge gate.
- Provisional: Shiny auto returns `load` until n4f2. The internally documented `PaparazziPage$initialize(owned_app)` source parameter changes `man/PaparazziContext.Rd` on `btw pkg document`; this task restores that unapproved generated artifact after documenting, so the coordinator can decide whether to update the internal topic separately.
