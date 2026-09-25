# Shiny idle wait (n4f2)

Source: .agents/SPEC.md, Sessions and apps / Shiny idle; base main 54f0741.

## Mechanism and ownership

- Shiny's `shiny:connected` fires synchronously in the WebSocket `onopen` callback, after the socket changes to OPEN. A post-navigation listener misses events that fired during `pz_open()`. Sample the live Shiny socket (`window.Shiny.shinyapp.$socket.readyState === WebSocket.OPEN`) instead: it is durable evidence of the connected state across the listener race. Require this state continuously through the 200ms hold; by the next poll after an OPEN sample the onopen callback has fired. Do not install listeners in the init/restore window, add flags, or alter page state.
- After document load, a page lacking `Shiny.shinyapp` is not a Shiny page: fail immediately with a clear classed error, both in the direct wait and explicit `pz_open(wait = 'shiny')`. Poll the trio (open connection, no `shiny-busy` on html, zero `.recalculating`) in a single JS sample and reset the stable-since timestamp on any false sample. The existing `pz_poll()` pumps the child loop at 100ms intervals and enforces the session/default or per-call timeout; no new timer mechanism. Window must finish within the same timeout budget.
- `open_wait_mode(wait, is_shiny_app)` resolves Shiny app paths/handles under `auto` to `shiny`, other targets to `load`. Explicit `shiny` invokes the identical direct wait after navigation. Preserve device CSS reapplication and open failure cleanup.
- Only R/wait.R and R/open.R and mirrored tests, task-specific fixture/helper, and generated help are in scope; no shared helpers, lifecycle fixtures, nav or context changes.

## Tests and cross-module seams

- Baseline targeted tests before implementation: wait/open/app. Write failing tests before feature code for slow Shiny reactive output, window hold after busy clears, explicit and auto directory/file/handle routes, classed non-Shiny errors (direct and explicit), timeout, and no-early-return before the socket connects. Reuse existing Shiny helper and add a dedicated slow-reactive fixture in `fixtures/shiny-idle/` only. Run `btw pkg document` and `testthat::test_local(filter = 'wait|open|app')`, plus named `test-nav.R` seam (navigation's load wait shares `pz_poll` and `wait_for_load`). Main full suite remains coordinator-owned.

Signed off: teammate-1, before feature code.
