# Phase note: advanced interactions (kata paparazzi#pat5)

Mechanism decisions for `pz_select_text()`, `pz_scroll()`, and
`pz_drag()`. Durable requirements live in `.agents/SPEC.md` (sections
"Actions", "Multiple matches", "Directions"); this note holds
mechanism-level choices and session handoffs for this phase only.
Builds on the action pipeline (`actions.md`: `action_elements()`,
`el_pointer_point()`, `dispatch_mouse()`, `action_cdp()`).

## Decisions

- **Selection.** A TreeWalker (SHOW_TEXT) over the target element;
  the concatenated node data is searched for the exact substring; one
  DOM Range spans the start/end (node, offset) pair, so a match
  crossing inline tags is a single selection. `window.getSelection()`
  replaces its ranges with it -- the real selection, so typing
  afterwards (pz_type with `target = NULL`) replaces it. A
  contenteditable target is focused too (a user dragging across
  editable text focuses it; that focus is what lets the insert land);
  static targets are not focused. Text not found is
  `paparazzi_error_text`; empty `text` is an input error. Into view
  via `el_scroll_into_view()` only -- no pointer dispatch, so no
  actionability wait (same shape as pz_focus).
- **Scroll.** Exactly one of target/by/to, validated. `target`:
  resolve + plain `el_scroll_into_view()`. `by = c(x, y)` / `to =
  <direction>`: the "current scope's container" is, scoped, the scope
  element's nearest scrollable ancestor-or-self (JS walk: overflow
  auto|scroll plus content overflow); at root, the document
  (`document.scrollingElement`). Application is instant JS --
  `scrollBy({behavior: "instant"})` for by, direct scrollLeft /
  scrollTop assignment for to (sides/corners/center per the direction
  vocabulary via `parse_direction()`) -- matching the existing
  instant-scroll precedent of `el_scroll_into_view()`; the recording
  task stages the animated mouseWheel variant at this seam. One JS
  function serves both rootings: `callFunctionOn` on the pinned set
  as `this`, or `Runtime$evaluate` with `this` an empty array (root).
- **Drag.** Source and destination centers via `el_pointer_point()`
  (the actionability wait belongs on a pointer action). Destination
  point first, then source, then one non-scrolling rect re-read of
  the destination: each element's scroll can shift the other's rect,
  and the drop point must be final. Non-draggable source: real mouse
  move/press/move/release through the existing `dispatch_mouse()`.
  Draggable source (own or inherited `draggable` attribute, or the
  img/`<a href>` defaults): CDP drag interception, verified end to
  end in chromote -- register the `Input.dragIntercepted` callback
  FIRST (the event method auto-sends `Input.enable`), enable
  `setInterceptDrags`, move+press at the source, move to the
  destination, then poll the child loop (`pz_poll`) for the event,
  which carries the page's own DragData (what its dragstart handler
  put on the dataTransfer). Then `setInterceptDrags(FALSE)` BEFORE
  the mouse release -- releasing with interception still on cancels
  the drag and the replayed events never land -- release, and
  `dispatchDragEvent` dragEnter/dragOver/drop at the destination with
  the captured data: trusted DnD events with the real payload. A
  dragstart canceled by the page never intercepts; the poll's
  timeout path disables interception and releases the button before
  re-raising. Drop targets must `preventDefault()` dragover for a
  drop to fire (HTML5); the fixture's dropzone does.
- **Seams for recording (rvj4).** The destination move in the mouse
  drag and the intercepted move in the DnD path become cursor glides;
  select_text's instant Range becomes a staged mouse drag across the
  text; scroll's JS application becomes animated mouseWheel events
  over the container. All three live inside the helpers added here
  (`dispatch_mouse_drag()`, `drag_html5()`, `scroll_apply_js`,
  `select_text_js`); no staging hooks are built now.

## Handoff log

(newest first; three lines per session: landed / next / provisional)

- 2026-09-25 (pat5): landed the phase note and the three actions
  (select_text Range+Selection, scroll by/to/into-view with the
  container walk, drag mouse + CDP drag interception replay), the
  advanced.html fixture with helper-advanced.R, and acceptance tests
  (selection across inline tags, scoped and root scroll, box drag,
  HTML5 DnD payload). Next: roborev review, then cursor staging (rvj4)
  animates at the seams above. Provisional: `pz_scroll(by/to)` falls
  back to the document when no scope ancestor scrolls -- revisit only
  if a real page wants an error instead.
