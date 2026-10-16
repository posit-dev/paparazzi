# 7y7b: Shiny idle settles for apps with suspended outputs

## Decision (owner-approved)

Match shinytest2: idle = Shiny socket OPEN + no `shiny-busy` on `<html>`,
held 200ms, driven by the four Shiny jQuery events. The `.recalculating`
DOM condition and the MutationObserver are gone. The per-output guarantee
(idle implies a visible output was delivered and undimmed) moves to a
possible `pz_wait_for_shiny_output()` — tracked separately, talk-first.

Rejected: excluding `.recalculating` elements that Shiny considers hidden.
Owner: paparazzi must not mirror shiny.js's `isVisible()` (it changed
recently and may change again); the predicate must rest on first
principles that survive shiny.js changes. The busy signal is that
principle: the server sends `busy` messages bracketing its reactive
flush, and suspended outputs never enter the flush.

## Mechanism facts (grounded in shiny server + client source)

- Server marks an invalidated output `.recalculating` immediately via a
  progress message (`obs$onInvalidate -> showProgress`), but only
  increments busyCount in the observer's `continue()`, which suspended
  observers defer to `.onResume`. So suspended outputs get the class
  with no busy signal and no events — the old predicate's hang.
- Client applies/removes `.recalculating` in values-message processing,
  before `renderValue`, so an expectation on delivered content already
  implies the class cleared for that output. The semantic expect, not
  the idle wait, is the dimming guard.
- ExtendedTask / `req(cancelOutput = "progress")` keeps visible outputs
  persistently `.recalculating` while the server is idle — the known
  cost of dropping the DOM condition; `pz_wait_for_shiny_output()` is
  the candidate answer.
- py-shiny ships the same client build and mirrors the busy/recalculating
  contract; covered by an explicit test (helper-py-shiny.R).

## Continuous-hold guarantee (njfj) after the change

Every real busy transition fires `shiny:busy`/`shiny:idle` alongside the
class change (same client message handler), so event listeners plus
current-state reads give exact continuous evidence without an observer:
a missed event is caught by the class read, a missed class change is
caught by the events. Tests inject busy the way Shiny signals it (class
+ event together) and assert brief in-hold pulses still restart the hold.

## What landed

- R/wait.R: predicate and roxygen (idle semantics + suspended-output
  behavior + expect-content-before-capture guidance).
- SPEC.md Shiny idle entry amended.
- shiny.md skill reference "Ready means" paragraph amended.
- New fixture fixtures/shiny-suspended/ (tabbed app, `input$go`
  invalidates the hidden output) + tests: settle at open with stuck
  class, recording idiom (`click |> wait |> set(wait = TRUE)`), resume
  waits out the slow render.
- New fixture fixtures/shiny-suspended-py/ + helper-py-shiny.R
  (skip_if_no_py_shiny, test-side `shiny run` server) + py-shiny test.
- njfj tests rewritten for the event-only design; recalculating pulse
  test replaced with a does-not-wait-on-recalculating lock.
