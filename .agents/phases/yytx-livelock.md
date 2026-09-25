# yytx: full-suite livelock / nav-wait failures

## Diagnosis (2026-09-25)

Two symptom families on main @ 481ce6d, reproducing in 4/4 timeout-capped
full-suite runs here (2 wedged workers at ~99% CPU, 2 runs completed with
2-3 `pz_nav_goto` "Timed out after 10s waiting for page navigation"
failures each).

### Fail mode (root-caused, fixed in ac20712)

`nav_await()` (R/nav.R) registered its `promises::then(p, ...)` on the
goto/reload anchor promise from top-level context. When a promise is
ALREADY settled, `then()` queues the callback via `later::later(...)`
on the CURRENT loop -- the default loop at that call site -- but
`pz_poll()` only pumps the page's child loop. The anchor settles early
exactly under load: Chrome's `frameNavigated` arrives and is dispatched
while `Page.navigate`'s own synchronize is still busy-pumping the child
loop waiting for the command response (delayed under parallel workers).
Every such `nav_await` then waited the full 10s and aborted -- matching
"systematic within a run, never serial on an idle machine".

Proven with protocol-level evidence (temporary per-worker trace setup
patching chromote debug_log + a synchronize watchdog; preserved at
/tmp/yytx/setup-yytx-trace.R): a serial nav run showing SEND navigate
-> RECV frameNavigated + dispatch + once-deregister + nested
Page.disable, all during the navigate synchronize, followed by a 10s
protocol-silent hole (pz_poll pumping a child loop that never gets the
already-queued-on-default-loop callback) and the paparazzi_error_timeout.
The regression test (test-nav.R, "nav_await settles a promise that
resolved before the wait") fails with exactly that 10s timeout against
the pre-fix code and passes after; no Chrome timing needed.

Fix: wrap the `then()` in `later::with_loop(page$child_loop, ...)` so a
pre-settled promise's callback lands on the loop pz_poll pumps. Pending
promises are unaffected (resolution queues on the resolving loop, which
is the child loop).

### Wedge mode (not reproduced post-fix; mechanism still open)

Pre-fix: 2/4 local runs wedged a worker at ~99% CPU (macOS samples:
deep R eval, GC-heavy, inside later's execCallbacks; websocket thread
idle; deadlines never fired because the spin sits inside a single
pump). The instrumented runs pinned the spin shape: chromote's
`synchronize()` busy-wait (`while (is.null(type)) run_now(loop)`) and,
inside event dispatch, the once-listener deregister issuing a
SYNCHRONOUS nested `Page.disable` (a nested synchronize inside the
dispatch callback inside run_now -- any stall there blocks every outer
deadline check). Post-fix: 0 wedges in 3 full-suite runs (was ~50%).
Not conclusive; if it recurs, the watchdog setup at
/tmp/yytx/setup-yytx-trace.R dumps the spinning stack and the full
SEND/RECV protocol log per worker (YYTX_TRACE_DIR env var).

### Remaining failures seen post-fix (NOT yytx's signature)

Zero nav_await timeouts in 3 post-fix runs. Occasional
"Chromote: timed out waiting for response to command X"
(Runtime.evaluate/callFunctionOn, 10s) under parallel load remain --
this is the pre-existing paparazzi#3tty chromote contention family,
also seen on pre-fix-round baselines per the device-nav handoff. One
anomaly worth noting for #3tty: in run8's failing worker the failing
command's SEND never appeared in the protocol log and no message id was
consumed, yet its synchronize waited the full 10s and hit
promise_timeout -- i.e. the response-wait outlived a command that
(apparently) never reached the wire. Unexplained; captured in
/tmp/yytx/trace-89145.log.

## Gate status

- Pre-fix: 4/4 runs bad (2 wedge, 2 nav-timeout fail-runs).
- Post-fix (ac20712): run7 GREEN (1780 PASS), run8 1 fail (#3tty-family
  command timeout), run9 3 fails (#3tty-family + one open-registry
  timing flake at test-open.R:137). The 3-consecutive-green gate has
  NOT been met; orchestrator should re-gate on a quiet machine and
  decide whether #3tty must land first.

## Handoff log

- 2026-09-25 (yytx): claimed, reproduced 4/4, root-caused the nav-wait
  fail mode to nav_await's then() landing pre-settled callbacks on the
  default loop (protocol-log proof), fixed in ac20712 with a
  deterministic regression test (verified failing pre-fix). Wedge mode
  0/3 post-fix, mechanism open. Instrumentation NOT shipped; preserved
  at /tmp/yytx/ (setup-yytx-trace.R, run*.log, trace-*.log, samples).
  Next: orchestrator re-gates; if the wedge recurs, redeploy the
  watchdog setup and read the spin stack + protocol log.


## Wedge mode: root cause (2026-09-25, second session)

Root-caused with five live captures (watchdog + per-worker protocol
log + heartbeat/queue traps + a trap logging any scheduling onto the
default loop; instrumentation preserved at /tmp/yytx/, never
committed).

**Chain:** new_pinned() (R/scope.R) registered a GC finalizer per
pinned-elements wrapper that issued a SYNCHRONOUS
Runtime.releaseObject. Scope-heavy tests create thousands of wrappers,
so under GC pressure the finalizer fires at arbitrary evaluation
points. When it fired in the microseconds between a command's
send_command and wait_for(), its nested chromote synchronize() pumped
the child loop and processed the OUTER command's response early,
settling the promise chain. synchronize() then called then() on an
already-settled promise; promises schedules then-handlers on the
CURRENT loop (the default loop at top level, never pumped by a
worker), so synchronize's completion flag never flipped and its
`while (is.null(type)) run_now(loop)` busy-wait spun forever -- no
deadline anywhere can fire from inside the single R call. This is the
same wrong-loop class as the nav_await fail mode (ac20712), one level
down inside chromote, but reachable only via the finalizer's arbitrary
nested pump.

**Evidence (run31 capture, the others consistent):** wire log shows
the response RECV and a nested releaseObject SEND between the outer
SEND and synchronize's then(); a scheduling trap caught
`result$then()` inside synchronize queueing on the default loop with
the full stack (pz_expect_style -> pinned_assert_connected ->
callFunctionOn); the queue dump shows that handler overdue forever on
the default loop while the child loop stays healthy (2s heartbeats);
SIGINT landed in chromote synchronize's interrupt handler, proving the
spin site; samples show the MHz busy-wait with no callbacks executing.

**Fix (20781eb):** the finalizer's release is now fire-and-forget
(wait_ = FALSE with no-op callbacks), so it never pumps the loop.
Audited the whole surface for other arbitrary-pump hazards: the two
other releaseObject call sites are mainline-synchronous; chromote has
no R6 finalize methods issuing CDP commands (Browser$finalize kills
the process via processx, no later pump, fires only at browser death);
later's own loop finalizer runs no R code.

**Upstream note (not done here):** chromote's synchronize() remains
latently vulnerable to the same pattern -- registering then()/catch()
on an already-settled promise schedules on the current loop, not the
pumped loop. A one-line upstream hardening would wrap the registration
in later::with_loop(loop, ...). Any nested command pump (not just the
removed finalizer) between send and wait_for can still trigger it, but
no such pump exists in the suite anymore.

**Gate:** three consecutive clean-tree full-suite runs (no
instrumentation) -- see handoff log.

## Handoff log (updated 2026-09-25, second session)

- Landed: ac20712 (nav_await loop pin, prior session) and 20781eb
  (finalizer fire-and-forget, this session) plus this note. Evidence
  and instrumentation preserved at /tmp/yytx/ (setup-yytx-trace.R
  redeployable; wedge-run*/ capture dirs; run*.log series).
- Gate: runs 39-41 green three consecutive, clean tree. Issue stays
  OPEN for orchestrator verification/merge; do not close from here.
- Provisional: if any wedge ever recurs, first check for a new
  arbitrary-pump source (GC finalizers, nested sync CDP in callbacks);
  the upstream chromote hardening (with_loop around synchronize's
  then/catch registration) would retire the whole class.
