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
  left pending). Back/forward take no `wait` argument (per SPEC) but
  always settle via the same load wait -- at a history boundary no
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

## Handoff log

(newest first; three lines per session: landed / next / provisional)

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
