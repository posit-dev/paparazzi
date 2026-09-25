# Phase note: recording (kata paparazzi#fx4z)

Mechanism decisions for poll-based recording, encode, and the
`pz_record*()` lifecycle. Durable requirements live in `.agents/SPEC.md`
(sections "Recording", "Framing"); this note holds mechanism-level
choices and session handoffs for recording only.

## Decisions

- **Recorder state object.** A plain mutable environment stored in the
  page's reserved `private$recorder_` slot (R/context.R), reached only
  through `page_recorder()` / `page_set_recorder()` in R/record.R --
  the same single-access-point pattern as `page_frame()`. Fields:
  `path`, `format` (`"mp4"`/`"webm"`/`"gif"`), `fps`, `scale`,
  `hold_first`/`hold_last`, `keep_frames`, `frames_dir`, parallel
  vectors `times`/`files`, `holds` (list of `list(vt, seconds)`),
  `frame` (resolved spec or NULL), `frame_ctx` (the start-time framing
  context for a frame spec), `when`, `crop` (measured CSS box +
  viewport width, computed at start or stop per `when`), the video
  clock (`vt_base`, `active_since`), `active`, `paused`, `in_flight`,
  `pending` (the in-flight capture's `vt` + file), `vt_end`, and
  `n_errors`/`first_error`. One recorder per page; starting twice
  aborts.

- **Timer and capture loop.** `later::later(record_tick, delay,
  loop = page$child_loop)`, re-armed at the top of every tick while the
  recorder is active, so the cadence is measured from tick fire time
  and the timer dies on its own once `active` is FALSE (a tick already
  scheduled when stop runs fires once, sees the inactive recorder, and
  does not re-arm). A tick does nothing but re-arm when `paused` or
  when `in_flight` -- that skip is the SPEC's in-flight guard, the only
  ordering flag. Captures are ASYNC:
  `session$Page$captureScreenshot(format = "png", fromSurface = TRUE,
  wait_ = FALSE, timeout_ = page$default_timeout, callback_ =, error_
  =)`, so `synchronize()` is never nested inside a callback; the
  `timeout_` promise rejection clears `in_flight` if Chrome wedges.
  `in_flight` is set at issue and cleared in `callback_`/`error_`,
  which chromote invokes when the child loop pumps. The whole tick
  body is wrapped in tryCatch: callback errors must not escape into an
  unrelated `run_now()`; failures increment `n_errors` and keep the
  first condition. `page$close()` tears the recorder down
  synchronously (`record_page_closed()` in record.R, called from
  context.R's close path) -- the closed session's loop may never pump
  again, so a later tick can't be relied on.
  Consequence documented in `?pz_record_start`: the timer only fires
  when the child loop pumps -- synchronous chromote calls and
  `pz_wait()`/`pz_poll()` pump it, but long-running plain R between
  steps freezes the recording.

- **Video clock.** Monotonic `proc.time()["elapsed"]`. Video time
  `vt = vt_base + (now - active_since)` while running; pause folds the
  elapsed stretch into `vt_base`, resume resets `active_since`, so
  paused stretches are cut. Frame timestamps are taken at ISSUE time
  (one capture in flight at a time, so issue order is resolve order).
  At encode, times are normalized so the first frame is vt 0.

- **Frame store + resampling.** The capture callback decodes and
  writes each PNG to `frames_dir` at capture time (memory stays flat;
  `frames_dir` is a tempdir, or `<output-stem>_frames/` next to the
  output when `keep_frames = TRUE`). Resampling to constant fps happens
  in R at stop: holds (first-frame, user `pz_record_hold()`s, last-
  frame) are `(vt, seconds)` intervals sorted by vt; output tick times
  `k/fps` over `vt_end + sum(hold durations)` map back to video time by
  subtracting completed holds and pinning to `hold$vt` inside one, then
  `findInterval()` picks the latest frame at each tick. Repeats in the
  resulting index vector are how holds and skipped ticks manifest; av
  and gifski both accept repeated input paths.

- **Encode pipeline.** Format from the extension. av encodes
  `.mp4` (libx264), `.webm` (libvpx-vp9), and `.gif` (gif codec);
  gifski is the higher-quality `.gif` path, used when installed and no
  crop/scale filter is needed (it can't crop; a framed `.gif` goes
  through av). The ffmpeg `vfilter` chain is built in R:
  `crop=W:H:X:Y` (see below), optional `scale=W:H` (`scale <= 4` is a
  factor, larger is an output width in px, height proportional), and
  `format=yuv420p` for mp4/webm. `.mp4` dimensions are floored to
  multiples of 4 (SPEC), webm/gif to even pixels; with no frame spec
  the "crop" is the PNG itself floored to the format's alignment, so
  odd viewports can't fail the encoder. PNG dimensions come from a
  tiny internal IHDR reader (dependency-free; mirrors the test
  helper). `pz_record_start()` checks up front with
  `rlang::check_installed()`: av for mp4/webm; gifski-or-av for gif
  (av alone sufficing when a crop is needed).

- **Crop at encode (frame integration).** Capture is always the full
  viewport; the crop is computed once -- at start for
  `pz_frame(when = "start")`, at stop for the default `"stop"` -- by
  re-running the framing pipeline viewport-relative:
  `frame_content_box()` + `frame_apply()` with the spec's bounds and
  the visible viewport `c(0, 0, vw, vh)` as clamps (NOT the document
  box `frame_clip()` uses -- the PNG only contains the viewport),
  rounded with `frame_round(even = TRUE)`. CSS-to-pixel conversion
  uses `dpr = png_width / viewport_css_width` measured against the
  first frame, so no reliance on chromote's pixel-ratio tracking.

- **`pz_record_stop()`.** Deactivate (`active = FALSE`, `vt_end` =
  current vt), pump the child loop until the in-flight capture settles
  (bounded by the session timeout), measure the crop when
  `when = "stop"`, resample, encode, clean up the tempdir unless
  `keep_frames`, clear `recorder_`. Zero captured frames aborts with
  `paparazzi_error_record` (wrapping `first_error` when there is one).
  Stop/pause/resume without an active recording abort with
  `paparazzi_error_record`; `pz_record_hold()` is a documented no-op
  when not recording, so debug runs skip video-only pauses.

- **Block form.** `pz_record(ctx, path, code, ...)`: `substitute()` +
  `eval()` in the caller (an expression, never a function -- same
  pattern as `pz_with_page()`), `pz_record_start()` first, then
  `withr::defer(pz_record_stop(ctx))`, so exit by error still encodes;
  returns `ctx` invisibly, not the block's value. `...` forwards to
  `pz_record_start()`.

- **Screencast seam.** `method = "screencast"` aborts
  `paparazzi_error_unsupported` for now. The seam: ticks only PRODUCE
  `(vt, png-bytes)` and ingestion is the callback writing to
  `frames_dir` + appending `times`/`files`; a screencast method feeds
  the same ingestion from `Page.screencastFrame` events (acking each
  frame) with no change to the clock, resample, or encode.

## Review-fix round (roborev 1262)

Mechanism decisions for the five accepted findings; landed as five
commits, one per finding.

- **Stop-time final frame (finding 1).** `pz_record_stop()` now issues
  one capture itself instead of only rescuing the zero-frame case:
  after deactivating and fixing `vt_end`, and letting an in-flight
  capture settle, it issues an async capture with `vt` pinned to
  `vt_end` and pumps until it settles (bounded by
  `min(default_timeout, 5)`). `record_frame_done()` accepts it
  (`pending$vt <= vt_end`), so the last captured frame is the page
  state at stop and the last-frame hold repeats it, not an older
  frame. The first-frame pump is subsumed: an immediate stop gets
  exactly this one frame, so the pump (and its `ticks` counter bound)
  is gone. Capture issuing is extracted into `record_capture(rec,
  page, vt)`, shared by the tick and the stop path.
- **Tick-to-recorder binding (finding 2).** Every scheduled tick
  closure now carries its recorder; `record_tick(page, rec)` returns
  when the recorder is inactive OR no longer the page's current one
  (`identical()` against the slot -- a single identity check, not an
  ordering system). A tick left scheduled by a stopped recording can
  no longer adopt a restarted recording's recorder, so a quick
  stop/restart can't run two polling chains.
- **Start-time framing context (finding 3).** `pz_record_start()`
  retains the ctx it was called on (`rec$frame_ctx`) whenever a
  frame spec is in effect. The `when = "stop"` crop is still measured
  at stop against the final layout, but resolved from that retained
  ctx -- its scope -- instead of the scope in force where
  `pz_record_stop()` happens to be called. Explicit targets and
  bounds resolve the same way; a detached start-time scope still
  raises the classed detach error at stop.
- **Synchronous close teardown (finding 4).** `page$close()` (context.R)
  calls `record_page_closed()` (record.R) before closing the session:
  deactivate the recorder, clear the recorder slot, remove the temp
  frames dir (unless `keep_frames`). The closed-page branch in
  `record_tick()` is gone -- close is now the single teardown point,
  reversing the earlier "context.R is untouched" decision. The
  in-flight capture, if any, is left to resolve harmlessly on the
  recorder (errors land in `first_error` of a discarded recorder).
- **Pinned-edge even rounding (finding 5).** `record_crop_box()`
  computes the pinned-edge vector exactly as `frame_clip()` does --
  which edges a clamp fixed in place, exact bit-equal comparisons,
  coinciding values treated as pinned -- and passes it to
  `frame_round(even = TRUE)`, so clamped edges round inward and the
  even crop stays inside explicit bounds (a left bound at 1 no longer
  rounds to 0).

## Handoff log

(newest first; three lines per session: landed / next / provisional)

- 2026-09-24 (review): landed the roborev 1262 follow-up round as one
  commit per finding (see Review-fix round above): stop-time final
  capture (84c5eea), tick-to-recorder binding (afc2d75), start-time
  framing context (85334a2), synchronous close teardown (f02030c),
  pinned inward even-rounding of the crop (e0652da), plus the
  pz_record_start doc paragraph (888288e). Full suite 1583 green on
  the first run, staging/cursor tests included. Next: recording stays
  done per acceptance; `method = "screencast"` remains the reserved
  seam. Provisional: the stop-time capture can hold a stop up to 5s
  when Chrome can't produce a frame (closed page) and then aborts
  with the kept first_error; the final-frame test reads kept PNG
  pixels via the png package (skipped where it isn't installed).
- 2026-09-25 (finish): landed the previous session's three hardening
  fixes as four commits: closed-page tick teardown -- a tick on a
  closed page deactivates the recorder and removes the temp frames
  dir instead of re-arming forever (b802171); immediate-stop one-frame
  capture -- pz_record_stop() pumps the child loop for a first frame
  before deactivating, bounded by a tick counter on the recorder
  (9034dbc); block error rethrown over the stop error (e5fd076); and
  gif assertions without av via a GIF logical-screen-descriptor reader
  (8541856). Full suite 1167 green (one chromote-timeout flake in
  test-get.R passed on serial rerun). Next: recording is done per
  acceptance; the cursor/staging task consumes `page_recorder()` state
  and `pz_record_hold()`'s no-op pattern; `method = "screencast"`
  remains the reserved seam. Provisional: the immediate-stop pump can
  hold a stop up to 5s when the loop can't produce a frame (e.g. the
  page was closed first) and then aborts with the kept `first_error`.
- 2026-09-24 (close): landed the phase note (b3fb55f), R/record.R
  lifecycle + poll timer + resample + av/gifski encode (06e6b1f), and
  fixture/helper/tests (8d42eef). 1163 expectations green twice, 0
  failures/skips. Next: the cursor/staging task consumes
  `page_recorder()`-style state and `pz_record_hold()`'s no-op pattern;
  `method = "screencast"` remains the reserved seam (ack each frame,
  feed the same ingestion).
- 2026-09-24 (start): claimed fx4z; blockers 18j6 (capture) and r0zd
  (framing) closed, baseline 1108 tests. Installed av 0.9.6 + gifski
  1.32.0 (both already in Suggests); libx264/libvpx-vp9/gif encoders
  confirmed in the av binary. Decisions above resolved before code.
  Next: R/record.R, fixture + helper-record.R + test-record.R.
  Provisional: `scale <= 4` means factor, larger means output width.
