# Recorded click after auto-scroll (paparazzi#9tdp)

## Diagnosis

`el_pointer_point()` in `R/actions.R` calls `stage_scroll_into_view()` inside its poll, then reads `getBoundingClientRect()` and computes the center. `stage_wheel_into_view()` in `R/stage.R` pumps the child loop after each wheel step and probes again until the remaining scroll delta is zero. Cursor movement and the mouse press follow point computation. The actionability probe checks visibility and non-empty dimensions, **not** whether the target occupies the dispatch point.

Reproduced with `pz_open('/tmp/v56x/tasks.html', width = 800, height = 600)`, a `mousedown` listener logging `clientX/clientY`, scroll position, and target rect, and a trace of `el_pointer_point()` (temporary scripts outside the repository). On a missed recorded click, the computed point was `(187.6, 583)`; at `mousedown`, `scrollY` was 122, the button's rect was `(137, 566, 101.2, 34)`, but the event arrived on BODY at `(93, 291)`, approximately **half** the dispatched coordinates. `devicePixelRatio` was 2, `innerWidth` 800, visual viewport scale 1, and CSS zoom 1. The same point and scroll position sometimes delivered the event correctly at `(187, 583)`. An unrecorded click delivered it correctly.

Critically, pre-scrolling the button **before** starting the recording still missed on 4 of 6 runs. This rules out a stale rect caused by the staged scroll. The failure appears to be intermittent CDP input coordinate scaling during recording (possibly concurrent screenshot capture), not the ordering of scroll and point measurement. That inference needs investigation; the event log establishes the mismatch, not its underlying browser cause.

## Fix and tests

No fix or red-first test was built. Moving point measurement after the scroll cannot correct a point that was already correct when CDP mapped the press to half its coordinates. Correcting the mismatch may require changes to the recorder/capture or input dispatch pipeline, outside the pre-approved ordering change. Stop for direction rather than adding a timer, queue, ordering flag, init/restore change, or guard. A future regression test should use a small below-fold button fixture at a viewport where halved coordinates hit BODY, assert a recorded click reaches the button, and check `pz_hover()` / targeted `pz_type()` because they share `el_pointer_point()` and mouse dispatch. The existing target-visible/non-empty actionability check does not hit-test the final press location.

Baseline targeted suite (`testthat::test_local(filter = "record|actions|cursor|stage")`): FAIL 0, WARN 0, SKIP 0, PASS 431. No post-fix run applies.

## Handoff

Landed: diagnosis and reproduction evidence only; no production or test changes.
Next: decide whether to authorize investigation of CDP coordinate mapping during concurrent recording capture, then add a red-first fixture and fix.
Provisional: screenshot/input concurrency is a hypothesis, not proven; scroll/rect ordering is ruled out by the pre-scroll reproduction.

## Follow-up diagnosis: DPR-2 screenshot/input interaction (2026-09-25)

Investigation only. Scratch harnesses and logs are under `/tmp/9tdp/`; the package was not edited. Each Rscript experiment ran serially, with one browser process at a time. The harness loaded this worktree and opened `/tmp/v56x/tasks.html` at 640 × 560, scale 2. Temporary R namespace instrumentation logged entry to `record_capture()` (`captureScreenshot` issue), `record_frame_done()` (resolution), and `dispatch_mouse()` (issue/return). A capture was considered in flight until its callback. A page-side `requestAnimationFrame` sampler logged changes to `[devicePixelRatio, innerWidth, innerHeight, visualViewport.scale]`; `mousedown` logged the target and actual client coordinates. Variants changed only the capture call *in scratch R memory*, not source files.

| Poll capture at 30 fps | Correct clicks | Presses while capture in flight | Observed coordinates |
| --- | ---: | ---: | --- |
| `fromSurface = TRUE` (current recorder) | 2/12 | 11/12 | Six `#task-title` presses sent at (198,128) arrived on H1 at (98,64); four `#toggle-help` presses sent at (108,543) arrived on MAIN at (53,271). Two help presses arrived correctly, including one issued in flight. |
| `fromSurface = FALSE` | 12/12 | 12/12 | Both targets received all presses at the dispatched CSS coordinates. |
| `fromSurface = TRUE`, explicit viewport `clip`, `scale = 1` | 12/12 | 9/12 | Both targets received all presses at the dispatched CSS coordinates. |
| Same explicit clip, with `clip.y = window.scrollY` read at capture time | 10/10 | 9/10 | Both targets received all presses at the dispatched CSS coordinates. |
| Current capture at **1 fps** | 12/12 | 0/12 | Both targets received all presses at the dispatched CSS coordinates. |

In the first run of the 30-fps baseline, for example, the first press was issued ~21 ms after capture issue, before its resolution, and arrived at (98,64) rather than (198,128); another missed press was issued ~32 ms after capture issue. At 1 fps the presses fell between captures and all arrived correctly. Overlap is **not by itself sufficient** for a miss: two baseline help presses and every press in the `fromSurface = FALSE` control hit during in-flight captures. The exact sensitive interval within Chrome's screenshot implementation is not established. The page-side sampler saw only `2/640/560/1` throughout each run, including misses; the page's exposed DPR/viewport do not visibly flip. No instrumentation of Chrome's internal emulation state was done.

**Root cause supported by these controls:** Chrome's *unclipped, surface-based* `Page.captureScreenshot` path at device scale 2 intermittently changes how concurrent `Input.dispatchMouseEvent` coordinates are mapped (approximately ÷2). This is not stale geometry from scrolling: the above H1 miss is above the fold, and the previous pre-scroll experiment also missed. The traces establish a strong association and a capture-parameter intervention, not the precise internal Chrome race or a guarantee on other Chrome versions. The recorder's frame crop is applied at encode time and does not change the CDP capture parameters.

### Fix choices for human review (no choice implemented)

1. **Explicit viewport clip with `fromSurface = TRUE`, `scale = 1`: preferred candidate to investigate.** It kept 2× output resolution and 22/22 sampled recorded clicks correct (12 fixed-origin, 10 scroll-aware), including presses concurrent with captures. The clip must track *document* scroll: a fixed `(0,0,640,560)` clip after scrolling to `scrollY=122` differed from the current un-clipped frame (RMSE ~0.157 of quantum range). At `(0,122,640,560)` with default `captureBeyondViewport = FALSE`, the comparison image was pixel-identical (RMSE 0); setting `captureBeyondViewport = TRUE` was *not* pixel-identical (RMSE ~0.040). Viewport width/height, horizontal scrolling, zoom, resize, negative/overscroll origins, and animations need explicit validation. Measuring scroll/viewport for every frame may add CDP traffic and creates a capture-time observation; verify resulting frame fidelity and stability, especially for framed videos, before choosing this option. The screenshot API already uses a different `clip` with `captureBeyondViewport = TRUE` for document-space stills; do not copy that blindly to the recorder.
2. **`fromSurface = FALSE`: simple input-compatible capture path in this sample (12/12 hits despite 12/12 in-flight), but output was 640 × 560 instead of the current 1280 × 1120 at DPR 2.** It loses high-DPI fidelity and may behave differently for headless, offscreen, and framed captures; acceptance of that tradeoff needs review.
3. **Serialize input against capture: await the in-flight screenshot before dispatching any `Input.dispatchMouseEvent`, and prevent a new tick until the input sequence ends.** **PROJECT TRIPWIRE: this is an ordering mechanism and requires explicit human sign-off before implementation.** Waiting only for the current capture is insufficient if another tick can start between move, press, and release. It risks latency, altered staged-motion/frame timing, and deadlock/reentrancy with child-loop pumping; it needs a precise protocol and tests if authorized. Reducing capture fps to avoid overlap is not a reliable fix (the 1-fps result is only a diagnostic control).
4. **`Page.startScreencast`: not tested here.** This currently is an unsupported/reserved method in `pz_record_start()`; using it changes the recording pipeline, frame timing, and backpressure rather than being a parameter-only repair. Evaluate separately if the clip approach fails.

A regression should run at scale 2 with above- and below-fold targets while recording, assert actual `mousedown` coordinates/targets (not just no error), and exercise both unframed and framed recording. Add an independent video frame-content/dimensions check if capture parameters change. A final-point DOM hit-test is useful to detect some misses but cannot correct Chrome's remapping of a correctly computed point.

## Handoff update

Landed: evidence and options only; no package code or tests changed.
Next: obtain human choice/sign-off for the capture strategy (mandatory if input/capture ordering is proposed), then implement a red-first DPR-2 regression and verify frame fidelity.
Provisional: explicit scroll-aware viewport clipping is promising on this Chrome build, but viewport/zoom/frame behavior remains unproven.
