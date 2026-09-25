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
