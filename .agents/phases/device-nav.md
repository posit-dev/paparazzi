# Phase note: device emulation and navigation (kata paparazzi#xn2j)

Mechanism decisions for the device/navigation task, resolved before
code. Durable requirements live in `.agents/SPEC.md` (sections
"Sessions and apps" -- the `pz_device()` and navigation blocks and the
`pz_open()` signature; "Argument order"); this note holds
mechanism-level choices and session handoffs for this phase only.
Builds on the page core
(`.agents/phases/page-context-core.md`) and the scoping stack
(`.agents/phases/scoping.md`).

## Decisions

- **CDP backing per argument.** `width`/`height`/`scale`/`mobile` (and
  viewport-method `zoom`) back onto `Emulation.setDeviceMetricsOverride`;
  `color_scheme`/`reduced_motion` onto `Emulation.setEmulatedMedia`
  (`features`); `locale` onto `Emulation.setLocaleOverride`;
  `timezone` onto `Emulation.setTimezoneOverride`. All four methods
  exist in the installed chromote. Probed CDP semantics: width/height
  of 0 mean "keep the current value"; `deviceScaleFactor = 0` resets to
  1 (NOT "keep"), so the factor is always sent explicitly; width/height
  are protocol integers, so zoomed dims are rounded.
- **Two zoom methods.** `"viewport"`: one metrics override with
  `width / zoom`, `height / zoom`, `deviceScaleFactor = scale * zoom`
  -- keeps `vh` correct, can trigger media queries. `"css"`: the
  metrics override is untouched and
  `document.documentElement.style.zoom` is set via
  `Runtime$evaluate` -- keeps layout (media queries unchanged), breaks
  `vh` (a 50vh element renders across the full viewport at zoom 2).
  Verified by probing both against a fixture (innerWidth, dpr,
  matchMedia, rect measurements).
- **Persistent device state.** Every `pz_device()` call recomputes the
  override from state, so state lives as an attribute
  `"paparazzi_device"` on the `PaparazziPage` (R6 objects are
  environments; the attribute rides on the object, dies with it, and
  avoids adding an R6 field to `context.R`, which this task must not
  edit). Held: the user-specified
  width/height/scale/mobile/zoom/zoom_method, the active emulated
  media pair, the css-zoom currently applied, whether an override is
  applied by us, and sticky `base_width`/`base_height`. The sticky base
  exists because a live `innerWidth` read is already zoomed while a
  viewport zoom is active, so it is captured (user value, else live
  read) at the first viewport zoom and reused for recomputes.
- **"Only supplied arguments change state."** `NULL` arguments are
  "not supplied" and leave state alone; therefore `zoom = 1` (not
  `NULL`) disables zoom, and there is no clear path yet for color
  scheme, reduced motion, locale or timezone (`features` values clear
  with `""`; the SPEC asks for none). `scale` defaults to 2 (retina)
  whenever an override is applied. `Emulation.setEmulatedMedia`
  `features` REPLACE the whole set (probed), so color scheme and
  reduced motion are tracked together and always sent as the union of
  the active ones.
- **`pz_open()` dots.** Captured with `rlang::list2()`, then: unnamed
  dots error (device settings must be named); names are checked
  against `pz_device()`'s formals, with unknown names errored and
  near-misses suggested ("Did you mean `width`?", via `adist`, like
  match.arg's hint). Forwarded with `do.call()` right after page
  creation, BEFORE navigation, so viewport/media scheme are right at
  first render; applies to the ChromoteSession wrap path too.
- **Nav sequence.** `release_object_group()` -> root context
  (`ctx` itself at root, else a fresh `PaparazziContext` with an empty
  stack, mirroring `pz_find_reset()`) -> navigate -> wait. `goto`
  checks `errorText` like `pz_open()` and aborts classed
  `paparazzi_error_navigation`. `wait` on goto/reload resolves
  `"auto"` -> `"load"`; `"shiny"` errors unsupported, `"none"`
  skips (reload then skips the event registration too -- nothing is
  left pending). **Superseded by h5qs:** `"shiny"` now follows load
  with Shiny idle; `"auto"` does so for an app-backed page on its app
  origin after load settles. Back/forward take no `wait` argument (per
  SPEC) but now apply the same auto rule after the load wait -- at a history boundary no
  navigation is triggered at all, so nothing waits. Back/forward use
  `Page$getNavigationHistory()` + `Page$navigateToHistoryEntry()`;
  out-of-range is a no-op.
- **History arithmetic.** CDP's `currentIndex` is 0-based, R's
  `entries` list is 1-based, so the target's R index is
  `currentIndex + offset + 1` (the session-start handoff's
  `currentIndex + offset` was an off-by-one: back from the second
  entry navigated to the session's initial `about:blank`, whose
  empty title and instantly-complete readyState looked exactly like
  the settle-too-early symptom). Back also stops at that initial
  `about:blank` entry -- the browser creates it with every new
  session, it is not part of the user's history, and back-at-the-
  start must be a no-op.
- **Back/forward settle: history-index anchor.**
  `navigateToHistoryEntry` returns while the outgoing document still
  reports `readyState == "complete"`, so `wait_for_load()` alone
  settles instantly on the old page. The index anchors it: after the
  trigger, poll `getNavigationHistory()` until `currentIndex`
  equals the target (probed: flips within ~50ms), then
  `wait_for_load()`. A normal load flips at commit with readyState
  still cycling, so the wait does the real settling; a bfcache
  restore flips instantly with readyState already complete, and the
  instant settle is correct (nothing more loads). Mid-switch the
  session can transiently answer "Not attached to an active page";
  that means not-yet, and the poll retries it the same way
  `wait_for_load()` retries evaluation errors.
- **Reload settle: event registration.** A reload leaves the
  history index unchanged, so the anchor can't settle it. Instead
  `p <- session$Page$frameNavigated(wait_ = FALSE)` is registered
  BEFORE `Page$reload()`, the promise is synchronized within the
  timeout budget (`nav_await()`: a `promises::then()` callback
  flips a flag while `pz_poll()` pumps the page's child loop -- only
  the public promises API; a rejection is re-thrown, never
  swallowed), then `wait_for_load()`. `frameNavigated` is the right
  event because it fires on reloads, full navigations AND bfcache
  restores; `loadEventFired` skips bfcache restores, so waiting on
  it can hang a restore.
- **No window markers.** A marker set on the page survives a
  bfcache restore, so a marker-change poll can never signal the
  restore -- both settle mechanisms avoid it for exactly this
  reason. `promises` moves to Imports for `nav_await()`.

## Review-fix round (roborev 1265)

Dispositions for all five accepted findings, decided before any code;
one commit per finding.

1. (HIGH) The css zoom lived as an inline style on `<html>`, so any
   navigation discarded it and `state$css_zoom` caching skipped ever
   re-applying it -- a `pz_open(url, zoom_method = "css")` lost its
   zoom at the first navigation. Fix: the apply mechanism becomes
   `Page.addScriptToEvaluateOnNewDocument` (the CDP feature built for
   exactly this) with a top-frame guard in the injected JS
   (`window === window.top`) so iframes keep their own layout. The
   script is registered whenever a css zoom is active -- including
   from `pz_open()`'s device dots, so the destination document gets
   it; an inline application still covers the CURRENT document --
   removed with `Page.removeScriptToEvaluateOnNewDocument` when the
   zoom disables, and re-registered when the factor changes.
   `state$css_zoom` keeps meaning "the zoom currently in effect".
2. (HIGH) A scoped framed recording retained its start-time
   `rec$frame_ctx`, but navigation releases the pins it holds, so the
   `when = "stop"` crop in `pz_record_stop()` hit the detach error
   instead of finishing. The recording survives (SPEC: staging and
   recorder carry over), but its framing falls back to the viewport:
   the rebase hook lives in `wait_nav_reset()` -- the single seam
   every nav entry point and `pz_wait_for_navigation()` share -- and
   clears `rec$frame` and `rec$frame_ctx`, so a not-yet-measured
   `when = "stop"` crop resolves as the full viewport; a
   `when = "start"` crop was already measured as a fixed box in
   viewport coordinates and stays.
3. (MEDIUM) `pz_nav_goto()` waited on `readyState` alone, which
   settles on the outgoing page whenever it is still `"complete"`
   when `Page.navigate()` returns. Fix: mirror `pz_nav_reload()` --
   register `frameNavigated(wait_ = FALSE)` BEFORE the navigate, then
   `nav_await()` it, then `wait_for_load()` -- for `wait = "load"`.
   Same-document navigations (URL fragments) never fire frameNavigated
   (probed), but their `Page.navigate` response also carries no
   `loaderId` while a cross-document one does (probed), so the anchor
   is gated on `loaderId`: a fragment navigation skips straight to
   the readyState wait, where the instant settle is correct (the
   document never changed, it is already complete).
4. (MEDIUM) `pz_open()` registered its deferred close after
   `device_open()`, so an invalid device setting or a failed emulation
   command (e.g. a bad timezone) leaked the freshly created browser
   session. Fix: register the deferred close immediately after
   `PaparazziPage$new()`, before `device_open()`, in the new-session
   branch only -- the ChromoteSession wrap branch must never close
   the caller's session (the caller owns it).
5. (LOW) Disabling css zoom removed the inline `zoom` property even
   when the document had one before emulation. Fix: the first
   application captures the page's own inline zoom (or its absence)
   in state -- before the injected script takes over -- and disable
   means removing the script and restoring the saved value.

Landing notes (mechanism facts probed during the fix, kept for the
next reader):

- The `addScriptToEvaluateOnNewDocument` mechanism runs only on
  documents committed while the **Page domain is enabled**;
  registration itself survives disable/enable cycles. chromote
  auto-enables a domain when its event-listener count goes 0→1 and
  auto-disables it at 1→0 (a released `frameNavigated` promise), so
  the registration additionally calls `Page$enable()` explicitly.
  Because that enable can still be undone by a later listener
  release, every paparazzi settle point re-applies the inline zoom
  on the settled document (`device_css_reapply()`, skipping script
  re-registration): the script covers commits paparazzi never
  settles (`wait = "none"`, external redirects), the reapply covers
  commits the script missed. `wait_nav_reset()` clears only the
  `css_zoom` cache slot to drive that reapply. Back/forward at a
  history boundary re-set the same zoom on the same document,
  harmlessly. `pz_wait_for_navigation()` also reapplies (it is a
  settle seam too).
- The injected script runs before `<html>` exists, so its JS waits
  for `readystatechange` when `documentElement` is null (probed:
  `!!document.documentElement` is false at script run time).
- A fragment (same-document) navigation returns no `loaderId` and
  fires no `frameNavigated`; a cross-document one returns a
  `loaderId` and fires it (probed). Downloads answer without a
  `loaderId` too, so the goto anchor's gate handles them like
  fragments.
- On an idle machine a file:// `Page.navigate` response can arrive
  after the destination already reports `readyState "complete"`
  (probed), so the goto race is not deterministically reproducible
  there; the delayed-destination test pins the required behavior
  (anchor → commit → settle on the completed destination), and the
  fragment test does fail if the `loaderId` gate is removed (it
  times out awaiting a commit that never fires).
- ChromoteSession registers itself with its parent browser object
  and is never deregistered on close (chromote keeps the registry
  as a private list, re-read fresh each access); the pz_open leak
  test finds the failed open's session in that registry and asserts
  it rejects commands as closed. The default browser is shared
  across R processes (the #3tty contention), but the registry is
  per-process, so the test is noise-free.

## Handoff log

(newest first; three lines per session: landed / next / provisional)

- 2026-09-25 (review fix): landed all five roborev 1265 findings, one
  commit each after 5a82b19 planned them: css zoom across documents
  (4bb7aef), recorder viewport rebase on navigation (15e41e9), goto
  commit anchor (2681da0), pz_open deferred close before device_open
  (291e428), inline-zoom restore on disable (6b5fe2e), plus this note.
  Targeted open|nav|device|record runs green (300 expectations; two
  runs showed one transient chromote-timeout failure each, the #3tty
  parallel-load flake -- clean on rerun while the main-branch baseline
  suite was running concurrently). Each new test was verified to fail
  against the reverted fix (detach error, 10s commit timeout, leaked
  session answering commands, clobbered inline zoom). Next: the full
  suite + merge stay with the orchestrator; roborev 1265 not closed
  here. Provisional: the goto race is not deterministically
  reproducible on an idle machine (file:// navigate responses can
  arrive post-commit), so the slow-destination test pins behavior
  rather than reproducing the bug; the css-zoom restore is
  per-document (a save captured on one document restores onto
  whichever document is current at disable), matching the decided
  disposition.
- 2026-09-25 (landing): re-applied the completed work onto current main
  (7d47509) via stash + reset; dropped the scope.R detach-regex hunk
  (superseded by main's pinned_dead_context_error()) and adapted two
  seams main added under this task's names: nav_root() is now main's
  wait_nav_reset() (identical helper), and nav_settle(page, wait) is
  renamed nav_wait_load() (main's wait.R grew its own nav_settle()).
  Commits: 14b2a9c device core, 1bbaa4f nav actions, ff53796 open
  dots, a1e851c tests+fixtures, 9e42e62 stale-man catch-up, plus
  this note. Next: full-suite pass (nav 44 / device 68 / open 85
  already green; chromote contention with sibling worktrees is the
  paparazzi#3tty flake) and a roborev review of the landed unit.
  Provisional: none.
- 2026-09-24 (start): claimed xn2j; harness green at c8d889b (838
  tests). Probed CDP semantics (metrics-override zeros, media feature
  replacement, locale/timezone, history, both zoom methods) and read
  the page-core and scoping notes. Next: implement per decisions above.
  Provisional: device state as a page attribute, not an R6 field.
