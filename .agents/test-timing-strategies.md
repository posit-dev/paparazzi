# Test-suite timing reduction strategies

Researched 2026-10-11. Baseline: 211.2s local wall (TESTTHAT_CPUS=5, file-level
parallelism), ~21-27 min per browser job on CI (TESTTHAT_CPUS=1, fully serial).
Per-test timings for the 12 slowest files: /tmp/pz-timing/*.csv (regenerate with
/tmp/pz-timing/time-tests.R).

## Structural facts that shape everything

1. **CI is serial by design** (`TESTTHAT_CPUS: 1`, R-CMD-check.yaml) because
   concurrent Chromes starved shared runners (chromote timeouts = flakes). Every
   second cut from a test is 1:1 CI wall time. Local wall is bounded by the
   slowest *file* (parallelism is file-level).
2. **~818 page opens across ~1083 test blocks.** Each open = new httpuv server +
   new Chrome target + navigate + 100ms-granularity load poll + close ≈
   0.1-0.35s of pure machinery. That's 25-40% of suite time, and it amortizes.
3. **Real-time floors**: staged actions animate at wall-clock speed (0.5s glide
   floor per action), recordings capture+encode at stop, Shiny fixture boots
   cost 1.5-2.5s each, and `app$stop()` can burn up to 2s on graceful shutdown.
4. test-scope.R proves the pattern: two tests each burn the full 10s default
   timeout = 20s of the file's 22s.

## Tier 0 — pure wins (no coverage loss, no flake risk)

| # | Strategy | Local | CI serial |
|---|----------|-------|-----------|
| 1 | test-scope.R:56,88 — set a short timeout (e.g. `page$default_timeout <- 0.5`) on the two tests that wait out the 10s default | −19s | −19s |
| 2 | test-drag-preview.R: record at fps=2 and stop right after the drag in the ~38 recordings that never inspect a frame (they only need `recorder_active()`) | −10-25s | −10-25s |
| 3 | Split test-drag-preview.R into 2-3 files (fixtures move to helper-drag-preview.R). 135s file = one worker's critical path | −60-90s wall | 0 (but combine with #2) |
| 4 | Split the 78-example loop in test-example.R into 5-6 files sharing helper-example.R | −45s wall | 0 |
| 5 | test-record.R (~20 sites): replace fixed `pz_wait()` "let it record" pumps with polls on retained frames (pattern already at test-record.R:1165) | −8-12s | −8-12s, **flake reduction** |
| 6 | test-camera.R:155,166,239,251 — delete 4 fixed `pz_wait()` paddings already guarded by adjacent `pz_poll`s | −1.3s | flake reduction |
| 7 | test-stage.R pause tests (717,739,784,815): convert to mocked-`pump_loop` duration assertions (pattern already at 784-837); delete the `elapsed < 5` upper-bound at :952 (flake liability) | −7-10s | −7-10s, flake reduction |
| 8 | test-stage.R smooth-scroll test (280): `duration = 0.05` wheels — assertions are event counts and final positions, identical at any speed | −3.5-4.5s | −3.5-4.5s |

## Tier 1 — shared fixtures (the 25-40% lever)

| # | Strategy | Est. serial savings |
|---|----------|---------------------|
| 9 | One cached static server per worker for fixtures/ (lazily created in helper-page.R, stopped in teardown); kills ~800 httpuv start/stops and port churn | −8-33s |
| 10 | Faster load poll: `interval = 0.02` in `wait_for_load()` only (keep 0.1s elsewhere) | −20-60s serial across 818 opens |
| 11 | Memoized per-file record fixture page (helper-record.R) with a dirty-check reload for the ~40 record tests that never navigate/resize | −15-25s |
| 12 | Shared staging page for the 12 pure-R blocks in test-stage.R (reset via `page_set_stage(page, NULL)`); merge subsumed blocks 90→23 and 138/158/175/192→≤2 | −4-6s |
| 13 | test-actions.R shared pages: validation tests → 1 page; 18-test `pz_set_value` family → 4-5 pages (reset `window.__pzLog` + `form.reset()`) | −15-20s |
| 14 | test-cursor.R: one shared page for the 6 static-state tests; merge 4 keyframe recording tests into one recorded session; trim terminal `duration=0.5` pumps where assertions read only keyframe text | −10-14s |
| 15 | test-wait.R: consolidate 10 Shiny boots → ~4 (share app across busy/pulse tests); open with `wait="none"` in tests that immediately force busy | −11-18s |
| 16 | test-annotate.R: page-reuse-with-DOM-reinject for `annotation_page()` tests (synthetic DOM makes leakage detectable); keep fresh pages for the 13 recording tests. Gate behind a `reset_page()` that errors if recorder/scope active | −20-30s |

## Tier 2 — redundancy cuts and spawn reduction

| # | Strategy | Est. savings |
|---|----------|--------------|
| 17 | Merge camera metadata blocks (test-camera.R:1074+1091+1113+1127 → one page, one recording, 4 `pz_camera` calls); fold 1105/1144 into 89 | −3-4.5s |
| 18 | Merge record clusters: captioned+plain videos; mp4+webm+gif encode trio; three error-path tests onto one page; two preview tests | −4-6s |
| 19 | Shrink deliberate floors: pause/resume 1.7s→0.85s with rescaled bounds; hold-drain 1.5s→0.6s; DPR-2 click tests fps 30→10 (assertions never use cadence) | −5-8s |
| 20 | test-serve.R: merge 2 log tests + fold quiet-options into app-file test (−2 spawns); retry-budget knob so the port-taken exhaustion test dies twice, not 5× | −6-8s local, −20-40s CI |
| 21 | test-open.R: fold `app.R` case into recognized-names loop; drop the redundant app-file arm in the auto-route test (−2 spawns) | −4s local, −10s CI |
| 22 | Fast-stop opt-in for fixture apps (`R/serve.R:640-656`: kill_tree first under env var), keep ONE graceful-stop test | −3-5s local, −30-60s CI |
| 23 | Quarto: gate the `quarto render` test (test-record.R:416) to CI-only env var; drop one of two `render=TRUE` tests in test-serve.R | −5-15s local |
| 24 | Delete: drag-preview T5 'disabled' gate (subsumed by T2); test-cursor.R:1096 (subsumed); `recorded >= 1` wall-clock assertions (test-actions.R:1654,1691); cadence assertion `expect_lte(length(idle), 2L)` (test-record.R:2240, contradicts the test's own content-not-cadence contract) | −3-5s, flake reduction |

## Tier 3 — CI-level lever

25. **TESTTHAT_CPUS: 1 → 2 trial on ubuntu** (4 vCPU runners; workers already have
    isolated R processes + isolated Chromes). Run on a branch several times,
    measure flake rate, keep macOS at 1. Potential: 21-27 min → ~12-15 min
    before any test cuts. This was turned off for Chrome starvation — the
    question is whether 2 (not 5) browsers stay healthy. If flakes appear,
    revert; the test cuts above still stand.

## Tier 4 — flake hardening (zero time cost, do alongside)

- Widen upper-bound duration assertions on encoded video (test-record.R:82-86,
  97-104, 196-202, 786-791, 963-966) — lower bounds are the real contract.
- test-cursor.R:783 "automatic glide switches icon": replace mid-animation
  computed-style sampling with keyframe-boundary text assertions (siblings
  already do this).
- pz_stage_fonts example hits the real network — use a bundled woff or
  offline-skip. The one hard flake in test-example.R.
- test-open.R:103 wall-clock `< 2s` bound and :402 3s target-cleanup deadline —
  raise or assert mechanism instead.
- test-wait.R:623 bfcache test: in-process `pz_serve_static` instead of an
  Rscript subprocess (removes spawn+port flake).
- drag-preview T13 (test:1160): carry predicate can pass on a settled frame;
  require y strictly between source row and resting position.
- drag-preview T11 (test:1077): fixed pump before a negative assertion — poll a
  promise-resolution flag instead.

## Expected outcome

- Local wall: 211s → ~110-140s (drag-preview + example splits are most of it).
- CI serial test time: ~835s → ~450-550s; browser jobs ~21-27 min → ~13-17 min;
  ~7-9 min if the CPUS=2 trial holds up.

## Implementation notes

- One kata task per numbered strategy; tiers 0→4 in order. Roborev once per
  completed unit. Run `btw pkg test` filtered to changed files per task; full
  run on main as merge gate.
- Watch the tripwires: page-reuse helpers (11, 13, 14, 16) must stay simple —
  a `reset_page()` that errors on active recorder/scope, not a lifecycle
  manager. If a reuse helper starts wanting a queue or ordering flags, stop
  and reconsider.
- Judge results by FAIL/WARN, and re-time with /tmp/pz-timing/time-tests.R
  after each tier.
