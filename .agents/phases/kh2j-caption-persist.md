# Persistent caption at recording stop

Signed off by orchestrator, 2026-09-29.

## Problem and root cause

A caption active at `pz_record_stop()` fades over the final 0.25 seconds, leaving the last encoded frame without it. `caption_windows()` maps caption events to sampled output ticks, merges adjacent identical captions, and discards whether the final window was still open at stop. `caption_overlays()` currently assigns every window of at least three ticks a fade-out, including an open terminal window. A clear event can land on the terminal boundary (`n_ticks / fps`) without appearing in `sampled$vts`, so testing only the window's end time would incorrectly suppress that clear's fade.

## Decision and planned change

- In `R/caption.R`, carry an `open` boolean on caption windows: true only for a terminal window whose caption event has no later event closing it. Account for later events even when they fall after the last sampled tick; when coalescing identical adjacent windows, retain the terminal run's open status. A clear (NULL event) or replacement closes the previous caption window, including when its event is recorded at the stop boundary. Leave the existing short-window fade threshold and start-at-zero fade-in rule intact.
- In `caption_overlays()`, omit `fade_start` only for an open window; closed windows retain their current fade behavior. `screen_filter()` already emits a fade only when `fade_start` exists, for MP4/WebM and the GIF PNG-tick path. No recorder-state or filtergraph changes are planned.
- Add one sentence to the Captions bullet in `.agents/SPEC.md`: a caption still active at recording stop remains fully visible through the final frame in MP4, WebM, and GIF; explicitly clearing or replacing it still uses the usual fade-out.
- `caption_vtt()` reads only caption text and window times, not fade metadata; still compositing reads the current page caption rather than recorded windows. Preserve both paths unchanged and verify with focused tests.

## Red-first tests and verification (Stage 2)

1. In `tests/testthat/test-caption.R`, first add a decoded-last-frame MP4 test: a never-cleared caption over the light fixture should still make a central pixel/region of the bottom caption pill dark on the final frame, as on the first frame. Use enough ticks to enter the previous 0.25-second fade. If `av` and `gifski` are installed, cover the GIF last frame too. Record exact red FAIL/WARN/SKIP/PASS counts before changing production code. Wrap every Chrome-using test command in `.agents/chrome-lock.sh`.
2. Add pure `caption_windows()` tests for a terminal open caption, a clear or different replacement during the recording, a clear at `n_ticks / fps` after the last sampled vt (same `end`, but closed), and coalesced identical captions. Check a continued caption's VTT cue still reaches the terminal boundary. Test `caption_overlays()` with a page fixture: `fade_start = NULL` for open; a clear immediately before stop still sets `fade_start` for a window of at least three ticks; fade-in at tick zero remains NULL. Assert the resulting filter includes/excludes `fade=t=out` as appropriate if useful. The MP4 decoded test is the end-to-end check; add a decoded clear check only if inexpensive.
3. Run `.agents/chrome-lock.sh btw pkg test -f 'caption|record' --reporter minimal`, `air format --check .`, `jarl check .`, and `git diff --check`; report exact counts. No roxygen change is planned, so no documentation regeneration. After sign-off, commit the fix, tests, SPEC sentence, and this note with a signed conventional commit (`Refs: kata kh2j` in the body); append a three-line handoff and add a kata evidence comment. Do not merge, push, rebase, request review, or close the issue.

## Stage 1 handoff

Mechanism and maintainer decision agree: window openness is event-based, not inferred from its terminal time. Signed off by orchestrator, 2026-09-29.

## Stage 2 handoff

- Landed: event-based terminal-window openness suppresses fade-out only for never-closed captions; explicit clear/replacement retains fade. SPEC updated; no roxygen, recorder, VTT, or still-compositing changes.
- Next: orchestrator review and merge gate; user-facing roxygen prose is reserved for the orchestrator.
- Provisional decisions: none. Red-first `.agents/chrome-lock.sh btw pkg test -f 'caption' --reporter minimal`: FAIL 1/WARN 1/SKIP 0/PASS 105 (expected missing last-frame caption; warning from an initially precreated decode directory, fixed before green). Final `.agents/chrome-lock.sh btw pkg test -f 'caption|record' --reporter minimal`: FAIL 0/WARN 0/SKIP 0/PASS 938. `air format --check .`, `jarl check .`, and `git diff --check` passed.
