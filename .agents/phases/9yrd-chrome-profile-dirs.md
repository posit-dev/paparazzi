# Exit-proof test Chrome profiles and orphan reaping (paparazzi#9yrd)

## Root cause (verified 2026-09-29, macOS, R 4.6.1, chromote 0.5.1, later 1.4.8, testthat 3.3.2)

Two independent defects, both outside paparazzi's package code:

1. **Chrome deletes its headless `scoped_dir*` profile only on `Browser.close`.**
   Measured: SIGTERM exits Chrome with status 0 and leaves the profile; SIGKILL
   leaves it; chromote's `Browser` finalizer sends SIGTERM and processx's
   finalizer and supervisor send SIGKILL. So every exit path other than an
   explicit, completed `Chromote$close()` leaks ~35 MB under
   `~/Library/Application Support/Google/Chrome-headless/`, which nothing
   ever cleans. The deletion is also what makes `close()` slow: ~0.65 s with
   the default profile vs ~0.07 s with `--user-data-dir`, against testthat's
   1 s parallel teardown grace before `kill_tree()`. Pre-fix green run of
   `open|device|js|record|screenshot`: all 5 worker `Rtmp*` dirs left behind
   (workers SIGKILLed by `kill_tree()` before `R_CleanTempDir()`).
2. **Killed test runs orphan workers that never exit.** testthat's callr
   workers are unsupervised (`supervise = FALSE`). SIGKILL or SIGTERM of the
   main test process reparents them to launchd with closed stdio sockets.
   `sample` of the orphans shows R's SIGPIPE handler (`handlePipe` ->
   `Rf_error`) running on a background thread — later's timer thread, which
   does not block signals (macOS delivers socket SIGPIPE process-wide).
   Idle workers then deadlock in `exit()` (`Timer::~Timer` joining that
   thread, which is stuck in `flockfile`) *after* `R_CleanTempDir()`; busy
   workers spin at 100-200% CPU forever with their Chrome and profile alive.
   Reproduced deterministically: SIGKILL/SIGTERM of `test_local()` 25 s in
   left 2-5 orphaned workers each time. The machine had 9 such orphans (up
   to a day old, including an `R CMD check` run) when this started; the
   9yrd "PPID-1 Chrome" observations are this path.

The yqm8 "+3 on red" figure was the pre-fix (TDD red) measurement on a
passing run, not a failing-test leak path.

Direct leak found along the way: the two Quarto-render tests
(`test-record.R`, `test-screenshot.R`) open a browser in a knitr subprocess
that never runs testthat setup and closes only its tab: +1 profile each per
run (pre-fix `screenshot`-only run: +1).

## Fix (test infrastructure only; package behavior unchanged)

- `tests/testthat/setup-chrome.R`: appends `--user-data-dir` inside the
  worker's `tempdir()` to the Chrome args in effect, restored in teardown;
  teardown still closes the browser, then unlinks the profile. R removes the
  profile on any non-SIGKILL exit, including the idle-orphan deadlock.
- `helper-page.R`: `chrome_profile_code()`; the Quarto documents put their
  profile in the test's `local_tempdir()`.
- `.agents/chrome-reap.sh`, run by `chrome-lock.sh` after acquiring the lock:
  SIGKILLs PPID-1 callr R processes whose cwd is under a `paparazzi*` path,
  with their trees, and removes their `Rtmp*` dir (from the processx
  supervisor's FIFO path) and any `Chrome-headless/scoped_dir*` they held;
  also reaps PPID-1 chromote Chromes (`--crash-dumps-dir=…/Rtmp…/chrome-`)
  and removes that dead session's `Rtmp*`.

## Verification (under the Chrome lock, `open|device|js|record|screenshot`)

| run | Chrome-headless profiles | leftover `Rtmp*` | orphans after reap |
| --- | --- | --- | --- |
| green, pre-fix | +2 | +5 | 0 |
| green, fix | +0 | +0 | 0 |
| SIGKILL at 25 s, pre-fix | +7 (reap recovers 0) | — | 0 (2 reaped) |
| SIGKILL at 25 s, fix | +0 | busy orphan's removed by reap | 0 (4 reaped) |
| SIGTERM at 25 s, fix | +0 | — | 0 (3 reaped) |

Full suite with the fix, 5 workers: exit 0, no failures/warnings/skips in
the summary reporter, +0 profiles, 0 orphans, one empty `Rtmp*` (no
profile). After the review fixes, `record|screenshot` rerun: +0/+0/0.
`air`, `jarl`, and `shellcheck` pass. roborev 1366 (3 low findings, fixed
in 96f705e) and 1367 (pass), both closed. Before starting, the reaper cleared
9 real orphans (1 spinning at ~200% CPU for 80 min, 2 from an `R CMD check`
a day old).

## Not done / follow-ups

- Upstream: later's background timer thread should block signals (as cli's
  tick thread does); R's `handlePipe` calling `error()` from any thread is
  the underlying hazard. testthat workers could also be supervised.
- Package-level (`pz_open()` choosing a profile dir, or closing the browser
  on last page close) would cover interactive/Positron sessions; it's a
  user-facing decision, not taken here.
- A SIGKILLed worker still leaves its `Rtmp*` (with profile) in `$TMPDIR`,
  which macOS ages out (oldest observed ~5 days) — bounded, unlike
  Chrome-headless. Runs outside `chrome-lock.sh` don't get reaping.
