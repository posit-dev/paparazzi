# Screencast capture (paparazzi#tef8)

Requirements: kata tef8 and `.agents/SPEC.md` § Recording. This branch is the feature branch; do not create another branch/worktree or merge to main.

## Mechanism decision (approved for implementation)

- `method = "poll"` stays the default and unchanged. `method = "screencast"` registers one `Page.screencastFrame` listener, starts `Page.startScreencast(format = "png")`, and immediately acknowledges every received frame, including frames discarded during pause or teardown. The listener is bound to its recorder, never to the current page slot on delivery. No polling timer for this method, queue, secondary ordering flag, or buffered display content.
- Stamp accepted events with the existing pause-aware `rec_vt()` at callback delivery. Ignore frames while paused/held, after stop, or when their recorder is no longer current; ack regardless. PNG bytes go through the existing disk frame store and resampling/encoding pipeline. Chrome's metadata describes the delivered frame; do not substitute the CDP wall-clock timestamp for the recorder's monotonic video clock. Use the PNG's actual dimensions for crop and encode; do not assume the screencast image is at the page's device-pixel ratio.
- Stop deactivates the producer, stops screencasting and deregisters its callback before taking the existing final screenshot at `vt_end`. Give that final screenshot the screencast's CSS-pixel resolution (clip scale = inverse of the live page DPR), so encode-time framing sees consistent coordinates across event and final frames. Page close tears down the listener and producer while the session is still alive. A stale callback must not write to removed frame directories or a new recorder. Start failure must leave no page recorder/listener/temp frames. Keep Chromote's listener registration/auto-Page.enable and deregistration/auto-Page.disable behavior in view; verify page functions continue to work after stop.
- Screencast is repaint-driven, not an fps guarantee. Idle intervals produce no new PNGs; resampling repeats the latest frame. Long-running plain R without a child-loop pump may miss intermediate animation frames. Retain the existing final screenshot so an immediate stop and last-frame hold reflect the final state. Document these differences.

## Gates and ownership

- Baseline before work: `.agents/chrome-lock.sh btw pkg test -f record --reporter minimal`: FAIL 0, WARN 0, SKIP 0, PASS 671. Disposable real-Chrome spikes recorded on kata tef8 proved event acknowledgement and reuse of the existing frame store/encoder for cropped MP4 and GIF; they did not exercise package lifecycle.
- Red-first tests in `tests/testthat/test-record.R` (and existing fixture/helper as needed), then production in `R/record.R`; regenerate `man/pz_record_start.Rd` via `btw pkg document`. Target method-independent contract tests for stop, pause, restart, close, framing, scaling, and formats; run `record|device|stage|cursor|nav` where changed behavior crosses modules, under `.agents/chrome-lock.sh`. Check `air format --check .` and `jarl check .`.
- One adversarial read-only subsystem review after tests, then one manual roborev review of the coherent committed unit; address findings against the spec. Do not merge this branch to main.

## Resolution contract (user-approved)

A real-Chrome experiment at viewport 640×480, DPR 2 produced 640×480 screencast PNGs with metadata `deviceWidth=640`, `deviceHeight=480`, `pageScaleFactor=1`; `maxWidth/maxHeight` at 1280×960 and 2560×1920 had no effect. The poll method produces 1280×960 PNGs, and its framed #box MP4 is 200×120; a screencast-only prototype produced a 100×60 crop. The page DPR remains 2. The user approved documenting this method-specific lower resolution rather than upscaling or changing CSS zoom/device emulation. Amend the roxygen description that presently claims all frames are captured at the current DPR; test screencast's native PNG size and crop behavior instead of imposing poll parity. Do not touch emulation init/restore.

## Escalation

Stop and consult before introducing timers, queues, another ordering flag, guards for guards, display-shaped state, or modifying the init/restore window. If event delivery needs any of those, reevaluate the approach rather than patching around it.

## Handoff

- 2026-09-28 (implementation): red-first tests proved unsupported method fails (FAIL 2/WARN 0/SKIP 0/PASS 664). A second red test exposed mixed final-frame sizes at DPR 2 (FAIL 1/WARN 0/SKIP 0/PASS 702); Chrome clip.scale=0.5 produced a matching 640×480 PNG with correct CSS-box color. The producer now feeds the existing frame store, and the final screenshot uses inverse page DPR for screencast only.

- 2026-09-28 (review): adversarial pass found shared poll/screencast framed-resize crop defect: the encoder uses the first PNG's dimensions for a frame measured at the final viewport. The user chose to backlog this pre-existing shared bug as kata 62g5, not expand tef8. The screencast resize test covers capture and encoding, not framed-resize crop accuracy. Final record filter (with idle page) FAIL 0/WARN 0/SKIP 0/PASS 734; record/device/stage/cursor/nav FAIL 0/WARN 0/SKIP 0/PASS 1453. README and pkgdown reference rendered successfully; the site build emitted Shiny/bslib-related warnings and writes through the pre-existing docs symlink to the main worktree's ignored site output. Next: commit, manual roborev, close kata after dispositions. No feature code beyond the approved scope.
