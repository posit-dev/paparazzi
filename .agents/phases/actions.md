# Phase note: pointer and keyboard actions (kata paparazzi#2fc0)

Mechanism decisions for the first actions task, resolved before code.
Durable requirements live in `.agents/SPEC.md` (sections "Actions" and
"Argument order"); this note holds mechanism-level choices and session
handoffs for this phase only. Builds on the resolution engine
(`loc_resolve()`, `multiple = "error"`) and geometry helpers
(`el_scroll_into_view()`, `el_rects()`).

## Decisions

- **File layout.** `R/actions.R` (the six exported actions + internal
  dispatch helpers), `R/keys.R` (key-syntax parsing + CDP key mapping;
  internal only). Tests mirror: `tests/testthat/test-actions.R`,
  `tests/testthat/test-keys.R`. New fixture
  `tests/testthat/fixtures/actions.html` (one fixture per task; do not
  touch elements.html/geometry.html/page.html). Helper
  `local_actions_page()` added to `tests/testthat/helper-page.R`.
- **Action pipeline (element actions).** resolve via
  `loc_resolve(ctx, target, multiple = "error")` -> `el_scroll_into_view()`
  -> `el_rects()` -> dispatch at the rect CENTER (rects are
  viewport-relative and stale after scroll, so the order matters) ->
  `release_elements()` (via on.exit). The scroll+rect+center step is
  one internal helper, `el_pointer_point(els, call)`; it is the seam
  where the cursor/staging task (rvj4) swaps in the animated scroll and
  cursor glide. Do not build staging hooks beyond isolating this
  helper.
- **CDP input dispatch.** Real `Input.dispatchMouseEvent` /
  `Input.dispatchKeyEvent` / `Input.insertText`, never JS `.click()`.
  Every CDP command gets `timeout_ = ctx$page$default_timeout`; a
  chromote "timed out" error is re-raised as `paparazzi_error_timeout`
  naming the action and target (same mapping as loc_resolve_once(),
  via a small internal wrapper in actions.R).
- **Mouse fields.** Coordinates are viewport CSS pixels (matching
  getBoundingClientRect). pz_click: mouseMoved (button "none",
  buttons 0) -> mousePressed (button "left", buttons 1, clickCount 1)
  -> mouseReleased (button "left", buttons 0, clickCount 1), all at the
  same point; pointerType "mouse". The leading move keeps pointer state
  real for the cursor task. pz_hover: mouseMoved only.
- **target = NULL semantics** (SPEC table; scope stack is still empty
  until the pz_find task lands, but write the branch now against the
  documented shape: top of `ctx$scope` is a pinned paparazzi_elements
  set, owned by the scope -- never released by actions):
  - scoped: click/hover/type/focus act on the scope element set;
    count > 1 errors like any multi-match.
  - root: click/hover/focus error with `paparazzi_error_target`
    ("needs a target", hint to pass a selector or pz_loc()); type/press
    go to the focused element (no resolution; press needs none anyway).
- **pz_type focus.** With an explicit target: focus via the SAME real
  click pipeline (move/press/release at the center), then
  `Input.insertText(text)`. Chosen over JS `.focus()` so pointer state
  stays real for rvj4; insertText is instant and fine pre-recording.
  Consequence: the caret lands where the click lands (as with a real
  user). With target = NULL at root: plain insertText to whatever is
  focused; if nothing editable is focused it no-ops, matching browser
  behavior (documented).
- **pz_press key syntax.** `key` is a character vector; each element is
  `Mod+Mod+Key`. Modifiers: Control, Shift, Alt, Meta (matched
  case-insensitively, normalized; duplicates error). The key token is
  either a named key from a small data-driven table (Enter, Tab,
  Escape, Backspace, Delete, Insert, Home, End, PageUp, PageDown,
  ArrowLeft/Up/Right/Down, Space, F1-F12) or a single printable
  character (letters, digits, common US punctuation). Unknown
  modifier/key -> `paparazzi_error_key` naming the bad token.
  Following Playwright's USKeyboardLayout: an uppercase letter (or a
  shifted symbol) auto-adds Shift -- so "Control+A" sends
  Control+Shift+A, exactly like Playwright; tests assert this.
  Dispatch per element: modifier keyDowns in order (rawKeyDown,
  cumulative modifiers mask), main keyDown, main keyUp, modifier keyUps
  in reverse. Main keyDown is "keyDown" WITH the text field when the
  key produces text and neither Control nor Meta is held; otherwise
  "rawKeyDown". Modifiers bitmask: Alt 1, Control 2, Meta 4, Shift 8.
  A vector presses each combo fully (down+up) in sequence.
  key/code/keyCode live in one named-list table in keys.R so the
  mapping can grow.
- **pz_focus / pz_blur.** focus: resolve (erroring on NULL at root,
  like click), scroll into view, then `el.focus()` via els_call().
  blur: scoped -> blur the scope element; root ->
  `document.activeElement.blur()` (no-op when body is focused). These
  are element-state methods, not input events; JS focus/blur is
  correct here (Playwright does the same).
- **Auto-wait.** Comes free from loc_resolve() (waits for >= 1 match up
  to the session timeout). No per-call timeout argument: the confirmed
  SPEC signature table gives actions `(ctx, target = NULL, ...)` /
  `(ctx, text/key, ...)` with dots checked empty; the session default
  (`page$default_timeout`, settable) is the knob. The task body's
  "per-call timeout" is satisfied by the resolve machinery's timeout
  parameter, used internally.
- **Multiple matches.** All element actions use
  `loc_resolve(multiple = "error")` -- the engine's
  `paparazzi_error_multiple` already exists.
- **Fixture.** `actions.html`: a form with `#name` (text input),
  `#bio` (textarea), `#save` (button), two `button.dup` (multi-match
  error tests), and a tall spacer pushing one `#below-fold` button out
  of the initial viewport (auto-scroll test). A sink script records
  real events into `window.__pzLog`: for click/mousedown/mouseup/
  mousemove/keydown/keyup/input/focus/blur push
  `{type, id, key, isTrusted, value}` (fields that don't apply are
  null). Tests read it back with `pz_js()`; `isTrusted: true` is the
  assertion that separates CDP-dispatched events from JS .click().
- **Validation.** text: check_string; key: check_character(min_length
  = 1, no NA); target: as_loc via loc_resolve; dots:
  check_dots_empty. Errors via cli with `paparazzi_error_*` classes.

## Handoff log

(newest first; three lines per session: landed / next / provisional)

- 2026-09-24 (close): landed the phase note (8bceb54), keys.R
  parser (7701f68), fixture (076d2dc), the six actions (31d659e),
  and review fixes (Shift shifts the character, modifier keyUp drops
  its own bit, trailing-"+" rejected, scoped blur multi-match check).
  574 tests green; roborev 1227 (codex) closed, dispositions on the
  issue. Declined: per-call timeout arg (SPEC's confirmed signatures
  give actions none -- session default_timeout is the knob).
  Backlogged as 5vak: actionability waiting (no click on hidden/
  zero-sized elements). Note for the pz_find task: an explicit target
  on a scoped context currently acts on the pinned set (dormant
  branch) -- resolve-within-scope lands with pz_find.
- 2026-09-24 (start): claimed 2fc0, stamped work.branch=kata-2fc0;
  harness green at 3f392e7 (305 tests). Blockers a3vj + gayb closed;
  loc_resolve()/el_rects()/el_scroll_into_view() delivered as promised.
  Decisions above resolved before code. Next: keys.R + fixture in
  parallel, then R/actions.R + tests, then roborev (codex).
