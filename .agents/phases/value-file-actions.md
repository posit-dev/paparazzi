# Phase note: value and file actions (kata paparazzi#jhrc)

Mechanism decisions for `pz_set_value()` / `pz_set_files()`, resolved
before code. Durable requirements live in `.agents/SPEC.md` ("Actions >
Setting values", "Argument order", "Multiple matches"); this note holds
mechanism-level choices and session handoffs for this phase only.
Builds on the action pipeline from the pointer/keyboard phase
(`action_elements()`, `release_elements()`, `action_cdp()`).

## Decisions

- **File layout.** Exported actions and internal JS/CDP helpers append
  to `R/actions.R`; tests append to `tests/testthat/test-actions.R`.
  New fixture `tests/testthat/fixtures/form.html` with its own
  `local_form_page()` helper in `tests/testthat/helper-form.R` (the
  shared `helper-page.R` stays untouched; one fixture per task). The
  fixture's event sink logs `input` and `change` (actions.html logs
  input only) plus a framework-style controlled input whose
  instance-level `value` accessor is trapped for counting.
- **No staging seam.** Both actions are pure DOM/CDP state changes with
  no coordinate dispatch: resolution (`loc_resolve(multiple =
  "error")`) -> scroll into view (instant) -> JS/CDP work. No
  actionability wait, per the pointer/keyboard phase's rationale (the
  hidden/zero-size hazard is pointer input at (0, 0)); setting values on
  hidden inputs is legitimate. "Instant even while recording" is a
  consequence of the design, not a flag.
- **pz_set_value mechanism.** One `Runtime.callFunctionOn` on the
  resolved element array, with the R value passed as a **callArgument**
  (`list(value = list(checked = <bool|null>, text = <string|null>))`),
  never string-embedded into JS. The JS returns a status object rather
  than throwing:
  - *Text-ish inputs and textareas* (text, password, search, url, tel,
    email, number, date, time, range, hidden, ...): call the **native
    prototype setter** — `Object.getOwnPropertyDescriptor(
    HTMLInputElement|HTMLTextAreaElement.prototype, "value").set` —
    bypassing instance-level overrides, so framework-controlled inputs
    (React & co.) observe the change. Then dispatch `input` and
    `change` (`new Event(t, { bubbles: true })`), in that order.
  - *Checkboxes and radios*: the R value must be `TRUE`/`FALSE`; it
    goes through the native `checked` setter on
    `HTMLInputElement.prototype`. The native setter does NOT maintain
    radio groups (that is pre-click activation behavior), so for a
    radio set to `TRUE` the JS also unchecks every other radio with
    the same `name` in the same form owner (or root tree) via the same
    native setter. Events as above.
  - *Native `<select>`*: match `<option>` by `value` only (SPEC;
    selectize etc. is `pz_set_shiny_input()`'s job, later). A missing
    option is an error naming the select and the value; a hit uses the
    native `HTMLSelectElement.prototype` value setter + events.
  - *Contenteditable* (incl. ProseMirror): detected via
    `el.isContentEditable`; the JS only reports the status and R runs
    the fallback: select all contents (a DOM `Range` over the element +
    window selection) after `el.focus()`, then `Input.insertText`.
    `insertText` fires trusted `input` events natively and replaces the
    selection, including with `""` (an active selection + empty insert
    deletes the selection -- verified in-browser). No `change` event:
    contenteditable has no value semantics.
  - *Verification.* After the native set, `el.value` must equal the
    requested text or the action errors ("the element kept ...").
    This catches invalid dates, malformed numbers, `maxlength`
    truncation, and clamped range values -- the browser silently
    sanitizes otherwise.
  - *Not a form control or contenteditable* (any other element): error
    naming the tag. All element/value mismatches raise class
    `paparazzi_error_value`; `change`/`input` are only dispatched by the
    set paths (checkboxes included, matching SPEC).
- **R value mapping.** `value` is a scalar: string, number, or logical.
    Numbers are coerced with `as.character()` (range takes 75, date
    takes "2026-01-01"). Logical is only for checkboxes/radios; a
    string/number there, or a logical elsewhere, is a
    `paparazzi_error_value` from the JS-side branch.
- **Focus.** The set paths `el.focus()` the element first (element-state
  method, the same sanctioned exception as `pz_focus()`), so the page
  shows the field focused exactly as after a user edit -- needed by the
  contenteditable fallback anyway (insertText needs a focused editable).
- **pz_set_files mechanism.** Validate `files` (character vector, no
  NA, every path must exist -> `paparazzi_error_input`; normalized to
  absolute real paths via `normalizePath(mustWork = TRUE)`). Then:
  resolve with `multiple = "error"` -> probe the element is
  `<input type="file">` (`paparazzi_error_value` otherwise) -> fetch the
  first element's OWN remote objectId (`callFunctionOn("function() {
  return this[0]; }", returnByValue = FALSE)`; the resolved set's
  objectId is the JS array, not the element) -> `DOM.setFileInputFiles`
  under `action_cdp()` (verified: it accepts a Runtime objectId
  directly; no describeNode round-trip needed) -> release the
  temporary element object. Files beyond an input's `multiple`
  attribute are dropped by the browser -- native semantics, not ours to
  guard.
- **Target = NULL.** Same `action_elements()` contract as the pointer
  actions: scoped context acts on its pinned element; root errors with
  `paparazzi_error_target`.

## Handoff log

(newest first; three lines per session: landed / next / provisional)

- 2026-09-24 (jhrc close): landed the phase note, form.html +
  helper-form.R, pz_set_value + pz_set_files in R/actions.R, and 55
  new test expectations in test-actions.R; suite 893 green. Mechanisms
  verified in a scratch browser first (setFileInputFiles takes a Runtime
  objectId and fires a trusted change; insertText("") with an active
  selection clears it; chromote unboxes length-1 vectors, so `files`
  goes as as.list()). Next: roborev + coordinator verification; the
  staging task should treat set_value/set_files as already-instant
  actions needing no cursor work. Provisional: verification-by-readback
  means a range value outside min/max errors instead of clamping
  silently; revisit only if a real case wants the clamp. Radios set via
  native setter get manual group unchecking (the browser reserves that
  for real clicks) -- no change events on the unchecked siblings.
