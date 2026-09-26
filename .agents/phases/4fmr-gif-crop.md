# Framed GIF crop before encoding (paparazzi#4fmr)

Signed off: orchestrator (mechanism prescribed in the 4fmr diagnosis comment)

## Problem and mechanism

`record_encode()` in `R/record.R` sends framed GIFs through av's GIF codec because gifski cannot crop. av's rgb8 conversion visibly dithers off-white backgrounds and text. The full-viewport captures are already PNGs; keep them intact and encode **all** GIFs through gifski. For GIFs whose `record_output_spec()` requests a crop (frame or alignment trim), slice each unique PNG capture with `png::readPNG()` and `png::writePNG()` in a disposable directory, then `match()` the resampled input paths onto the cropped files. Preserve all channels including alpha. gifski applies output scaling with `width` and `height`. Keep geometry calculation in `record_output_spec()`; expose its crop rectangle (`x`, `y`, `width`, `height`) alongside `vfilter` and final dimensions. Video formats still use av's vfilter. Delete `rec$use_gifski` and av's GIF codec branch.

`record_check_packages()` runs before capture: require gifski for GIF; require png additionally for framed GIF. av remains required for mp4/webm. png is already in Suggests; add it to website needs. Update roxygen, generated docs, README.Rmd (do not render README.md), and the outdated Encoding paragraph in SPEC. NEWS has no encoder-path claim.

## Alternatives and tripwires

The orchestrator tested palette filters in av: av fixes GIF output to rgb8 regardless. av-generated cropped PNGs shift colors and add a duplicate frame. Neither is suitable. There is no init/restore change, new timer, queue, ordering flag, display-shaped storage, or guard for a guard. The crop directory is transient and distinct from `keep_frames` raw captures.

## Red-first tests and verification

Add a framed GIF test in `tests/testthat/test-record.R` using an off-white page with flat text and `keep_frames = TRUE`. Mock `gifski::gifski()` to inspect its input PNGs before the crop directory is removed: verify their dimensions and pixel equality with the corresponding slices of raw captures; check repeated frames reuse cropped paths, and output dimensions include scaling. Test missing-gifski and missing-png package checks by mocking package availability at the R-level, without installing dependencies. Update the existing GIF test to require gifski. First run the new tests red, then implement and run `/tmp/pz-chrome-lock.sh Rscript -e 'testthat::test_local(filter = "record|frame")'`; record exact totals. Run `btw pkg document` in this worktree.

## Handoff

- Landed: c947136 (signed-off mechanism), 3d3e855 (GIF crop/encode and tests), 488d494 (SPEC, README.Rmd, DESCRIPTION, roxygen docs), f79641b (handoff), and a follow-up ensuring all unique captures are cropped. Red-first: FAIL 5 / WARN 0 / SKIP 0 / PASS 494. Final targeted run: FAIL 0 / WARN 0 / SKIP 0 / PASS 523. `btw pkg document` ran.
- Next: orchestrator re-renders README.md and runs the full merge-gate suite.
- Provisional: unframed GIFs with odd captured PNG dimensions need an alignment crop; unlike explicitly framed GIFs, that need cannot be known at `pz_record_start()` before capture. The encode-time crop branch checks png with a clear reason; orchestrator to decide whether to also require png upfront for *all* GIFs (stricter than requested) or accept this late check on the odd-dimension edge case.
