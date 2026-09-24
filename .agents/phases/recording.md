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
  `frame` (resolved spec or NULL), `when`, `crop` (measured CSS box +
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
  first condition. A tick on a closed page deactivates the recorder
  (context.R is untouched, so `page$close()` can't stop it).
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

## Handoff log

(newest first; three lines per session: landed / next / provisional)

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
