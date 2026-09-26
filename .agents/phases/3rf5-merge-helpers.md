# Merge duplicated internal helpers (paparazzi#3rf5)

Signed off: orchestrator, per garrick. This work is part of the style pass. It doesn't get a roborev review, but the full gate still applies.

## Scope

A read-only survey (`/tmp/pz-style/dup-survey.md`) found the candidates. There are three disjoint packages, one worktree each:

- **P1 (`refactor/3rf5-cdp`)**:
  - `cdp_call()` and `cdp_check_exception()` in `R/utils.R` replace the timeout and JS-exception mapping copied across 10 sites.
  - `els_arg_values()` merges into `els_values(args =, doing =)`.
- **P2 (`refactor/3rf5-frame`)**:
  - `frame_measure()` and `frame_region()` are shared by `frame_clip()` and `record_crop_box()`. The clamp names that appear in user-facing messages are kept.
  - `clip_rects_union()` reuses `box_union()`.
  - `clip_viewport()` reuses `page_geometry()`.
  - `nav_check_response()` is shared by `pz_open()` and `pz_nav_goto()`.
- **P3 (`refactor/3rf5-tests`)**:
  - `helper-png.R` gets `page_dpr()`, `png_canvas_eval()`, `png_pixel()` and `expect_png_pixel()`, replacing three samplers and three scanner scaffolds.
  - `elements_text()` and `local_outside_testthat()` each end up in one helper file.

## Accepted message changes

These are internal or JS-diagnostic wording changes; no snapshot pins them.

- "JavaScript error while resolving/pinning ..." becomes "JavaScript error resolving/pinning ...".
- Internal errors in `clip_rects_union()` and `clip_viewport()` now use the messages from `box_union()` and `page_geometry()`.

## Declined

- `write_screenshot_data()`: it would wrap a single `writeBin()` call, so it adds nothing.
- Fixture-specific `local_*_page()` wrappers: they name meaningful fixtures.

## Handoff
- Landed: P1, P2 and P3 merged on main. The orchestrator fixed a P1 attribution slip: callers had passed `call = caller_env()` into `els_values()`, which pointed errors at the caller of the exported action. The last copy of the timeout mapping lives in `R/utils.R`. The full gate is `[ FAIL 0 | WARN 0 | SKIP 0 | PASS 2586 ]`. There was no roborev review, per garrick.
