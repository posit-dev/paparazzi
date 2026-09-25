# Shiny idle wait (n4f2)

Source: .agents/SPEC.md, Sessions and apps / Shiny idle; base main 54f0741.

## Mechanism and ownership

- Shiny's `shiny:connected` fires synchronously in the WebSocket `onopen` callback, after the socket changes to OPEN. A post-navigation listener misses events that fired during `pz_open()`. Sample the live Shiny socket (`window.Shiny.shinyapp.$socket.readyState === WebSocket.OPEN`) instead: it is durable evidence of the connected state across the listener race. Require this state continuously through the 200ms hold; by the next poll after an OPEN sample the onopen callback has fired. Do not install listeners in the init/restore window, add flags, or alter page state.
- After document load, a page lacking `Shiny.shinyapp` is not a Shiny page: fail immediately with a clear classed error, both in the direct wait and explicit `pz_open(wait = 'shiny')`. Poll the trio (open connection, no `shiny-busy` on html, zero `.recalculating`) in a single JS sample and reset the stable-since timestamp on any false sample. The existing `pz_poll()` pumps the child loop at 100ms intervals and enforces the session/default or per-call timeout; no new timer mechanism. Window must finish within the same timeout budget.
- `open_wait_mode(wait, is_shiny_app)` resolves Shiny app paths/handles under `auto` to `shiny`, other targets to `load`. Explicit `shiny` invokes the identical direct wait after navigation. Preserve device CSS reapplication and open failure cleanup.
- `shiny:connected` and the busy/recalculating trio describe *current* Shiny work, not causal completion of a newly dispatched input. Normal text/date bindings invoke an immediate callback on jQuery `change`, bypassing the ~250ms debounce used for `input`/`keyup`, but Shiny may batch an immediate input before server busy begins. The input action must verify server reactions end-to-end rather than lengthening this SPEC-defined wait or adding a timer/flag here. Binding `setValue()` alone does not trigger server work; em3d must dispatch a change event. The idle tests exercise an already-started slow server reactive output.
- Only R/wait.R and R/open.R and mirrored tests, task-specific fixture/helper, and generated help are in scope; no shared helpers, lifecycle fixtures, nav or context changes.

## Tests and cross-module seams

- Baseline targeted tests before implementation: wait/open/app. Write failing tests before feature code for slow Shiny reactive output, window hold after busy clears, explicit and auto directory/file/handle routes, classed non-Shiny errors (direct and explicit), timeout, and no-early-return before the socket connects. Reuse existing Shiny helper and add a dedicated slow-reactive fixture in `fixtures/shiny-idle/` only. Run `btw pkg document` and `testthat::test_local(filter = 'wait|open|app')`, plus named `test-nav.R` seam (navigation's load wait shares `pz_poll` and `wait_for_load`). Main full suite remains coordinator-owned.

Signed off: teammate-1, before feature code.

## Handoff

- Landed: direct Shiny idle wait, 200ms continuous connected/unbusy/no-recalculating hold, non-Shiny error, and open explicit/auto routing for app paths and shared handles; tests use a slow server reactive and verify no early return.
- Next: coordinator runs full suite on main; em3d handles input-binding change events and tests server-side reactions.
- Provisional: no change to SPEC's idle hold; the input action must not equate a post-input idle sample with causal completion before Shiny starts reporting busy.

## Review fix: navigation commit (roborev 1269)

For a newly created session using Shiny wait (explicit or auto-app), register the existing `Page.frameNavigated(wait_ = FALSE)` anchor before `Page.navigate`, then await it on a returned `loaderId` before sampling Shiny idle. `Page.navigate` may respond while the original `about:blank` document still reports `readyState == "complete"`; checking load at that point can incorrectly classify the page as non-Shiny. Keep CDP `errorText` handling ahead of the wait, leave `none` and generic `load` untouched, and use `nav_await()` rather than adding ordering state. This does not change init/restore or the Shiny idle hold. Regression coverage will exercise a real new-session app open and document the stale-old-document boundary; without deterministic HTTP gating it may not force the pre-fix race on every run.

## Review-fix handoff

- Landed: new-session Shiny open now waits for the destination `frameNavigated` commit when `Page.navigate` returns a `loaderId`, before checking Shiny idle. Navigation `errorText` still wins; `none`, generic `load`, and wrapped sessions retain their old paths.
- Verified: pre-fix targeted suite 321 passes; the new test failed before the fix and the targeted `open|wait|app|nav` suite passes 325 assertions afterward. It observes an actual new `about:blank` session at `readyState == "complete"`, then instruments the existing navigation await (without replacing it) to check the destination history entry for explicit and auto app opens. The test verifies the required anchor but does not force a delayed navigation response; it is not a deterministic reproduction of the original timing race.
- Next: coordinator owns full main suite, review disposition, and issue closure. No change to the em3d causal server-busy seam.

## njfj: continuous-hold replacement (supersedes sampled-hold mechanism above)

Owner authorized ONE page-side awaited Promise in R/wait.R, replacing (not supplementing) the R-side `pz_poll`/`stable_since` block. The existing `wait_for_load`, non-Shiny check, and one R deadline remain; the Promise gets only the budget left after these checks. It reads the live socket OPEN state (not an event-history flag), html busy class, and `.recalculating` count. Install one MutationObserver on the document subtree (`childList`, `class` attributes with `attributeOldValue`) and Shiny's jQuery document `shiny:connected`, `shiny:disconnected`, `shiny:busy`, `shiny:idle` listeners before the initial state check. An observed busy-class or recalculating transition resets the one 200ms hold timer even if it starts and finishes between former 100ms samples. Detect class changes via old and new class tokens, and inserted/removed nodes via matches/descendant matches; connection events reset/check the hold. Ignore unrelated DOM churn to avoid starving a quiet app. A relevant change while idle cancels/restarts the hold; when non-idle, no hold runs. At hold expiry, drain pending observer records, then re-read all three state conditions before settling. A single deadline timer resolves false when the remaining budget expires. On resolve (success, deadline, pagehide) disconnect observer, remove listeners, cancel timers and pagehide handler; no global state, second queue, init/restore hook, or R-side fallback poll.

Return `true` on success and `false` on page-side deadline; R maps false and a CDP/pz_js timeout to `paparazzi_error_timeout` with "Shiny idle" in the message. Other JS errors propagate; non-Shiny still gets `paparazzi_error_unsupported`. CDP await timeout gets only a small transport grace beyond the remaining R budget so browser-side deadline normally runs cleanup; a CDP cancellation or destroyed execution context can prevent page-side JS cleanup until navigation destroys that context. This is a limitation, not a reason to add persistent page state or another timer. `pz_open(wait='auto')` app routing already calls this function, and is unchanged.

Deterministic tests first: on an already-idle fixture, schedule a brief html busy class pulse and a separate brief `.recalculating` insertion/removal inside the initial hold, record browser `performance.now()` at the *end* of each pulse, assert the wait returns at least 200ms later using another browser timestamp. Check a steady idle return, timeout class plus post-deadline cleanup through subsequent pulses, non-Shiny error, and existing open auto route. Run targeted `wait|open|shiny-input` only, serially if contention causes transient failures. No change to R/js.R, R/open.R, shared helpers, or dependencies. If correct coverage requires another timer/queue/flag or an init/restore intervention, stop and consult.

Signed off: teammate-3, before tests and feature code, paparazzi#njfj.

## njfj handoff

- Landed: one awaited browser Promise replaces R sampled Shiny hold, tracks socket and Shiny events plus relevant DOM mutations, drains pending records at expiry, and removes observer/listeners/timers on success, browser deadline, or pagehide. Existing open routing, load check, non-Shiny error, and shared R timeout budget remain unchanged.
- Verified: before replacement, new wait tests fail (four assertions: observer missing for each DOM pulse, early return after connection event, and missing observer cleanup). With replacement, `test_local(filter='wait|open|shiny-input')` passes (289 assertions); each named file also passes individually to exclude cross-process Chrome contention. Static parse, roxygen documentation, and diff whitespace checks pass. Coordinator owns the full-suite main gate.
- Limit: if CDP cancels the awaited Promise before its browser deadline, JS may not settle/tear down until the execution context is destroyed; no persistent page state or secondary cancellation mechanism was added. Mutation filtering intentionally ignores unrelated class/child changes; brief transient evidence comes from class old values and inserted/removed recalculating subtrees. No new dependency or init/restore intervention.
