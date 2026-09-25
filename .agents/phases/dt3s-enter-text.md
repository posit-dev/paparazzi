# Phase note: Enter text for `pz_press()` (paparazzi#dt3s)

## Problem

`Enter` is missing its character in the key table. As a result, `pz_press()` sends a raw key event without text, so Chrome does not produce Enter's `keypress` default actions for implicit form submission or textarea line breaks.

## Change

Add `text = "\r"` to the Enter key-table entry (and NumpadEnter if the table supports it). Reuse `key_events()`' existing text-producing keyDown logic: text is suppressed while Control or Meta is held, but retained for Shift+Enter. No new dispatch mechanism or timer is needed.

## Tests

- Unit: parsed Enter event has `text = "\r"`; Control+Enter and Meta+Enter suppress text; Shift+Enter retains it.
- Browser: Enter submits a form with a text input; Enter and Shift+Enter insert textarea newlines.
- Run `Rscript -e 'testthat::test_local(filter = "keys|actions")'` and record totals.

Signed off: orchestrator (pre-approved small fix)

## Handoff

- Landed: Enter maps to carriage return; unit and browser coverage exercises modifier suppression, implicit submit, and textarea newlines.
- Next: report verification and commit evidence on paparazzi#dt3s; leave issue open as requested.
- Provisional: NumpadEnter is not in the current key table, so no mapping was added.
