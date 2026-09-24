# The pointer and keyboard actions. Input goes through CDP's Input
# domain -- real trusted events, never JS .click() substitutes. The one
# sanctioned exception is element focus()/blur() in pz_focus()/pz_blur()
# (element-state methods, not input events; Playwright does the same).

# The pinned element set at the top of the scope stack, or NULL at
# the root. The set is owned by the scope that pinned it: actions use
# it but never release it. scope_root() (scope.R) adds the detach
# check every consumer runs once per call; scope_top() is the raw
# stack read, for routing decisions that don't consume the scope.
scope_top <- function(ctx) {
  if (length(ctx$scope) == 0) {
    NULL
  } else {
    ctx$scope[[length(ctx$scope)]]
  }
}

check_scope_single <- function(scoped, call = caller_env()) {
  if (scoped$count > 1) {
    cli::cli_abort(
      c(
        "Found {scoped$count} elements in the current scope.",
        i = "Narrow the scope, or target one element with {.fn pz_loc} and {.arg which}."
      ),
      class = "paparazzi_error_multiple",
      call = call
    )
  }
}

# The element set an element action operates on, detach-checked. NULL
# means the current context: the pinned set itself at a scoped
# context, used as-is and never released (its scope owns it), erroring
# on multiple matches like loc_resolve() does; at the root, NULL needs
# a target. An explicit target resolves lazily INSIDE the current
# scope (auto-waiting, so re-renders within the scope are fine) and is
# released after the action. Returns list(els, pinned): a pinned set
# must NOT be released by the caller.
action_elements <- function(ctx, target, call = caller_env()) {
  if (is.null(target)) {
    scoped <- scope_root(ctx, call = call)
    if (is.null(scoped)) {
      cli::cli_abort(
        c(
          "{.arg target} is needed at the root context.",
          i = "Pass a CSS selector or a {.fn pz_loc} spec."
        ),
        class = "paparazzi_error_target",
        call = call
      )
    }
    check_scope_single(scoped, call = call)
    return(list(els = scoped, pinned = TRUE))
  }
  list(
    els = loc_resolve(ctx, target, multiple = "error", call = call),
    pinned = FALSE
  )
}

# One actionability probe: [visible, x, y, width, height] for the
# first element. Visible is checkVisibility() with checkVisibilityCSS,
# the same definition pz_expect_visible() uses, so "visible" means one
# thing across actions and expectations. A zero-size probe means there
# is no point to dispatch at (the center of an empty box is its corner).
pointer_actionable_js <- "function() {
  if (!this.length) return null;
  const el = this[0];
  const r = el.getBoundingClientRect();
  return [
    el.checkVisibility({ checkVisibilityCSS: true }) ? 1 : 0,
    r.x, r.y, r.width, r.height
  ];
}"

# Scroll the first element into view and return the center of its
# bounding rect as c(x, y) (viewport CSS pixels, matching
# getBoundingClientRect), auto-waiting until the element is
# actionable: visible and with a non-empty box. Resolution auto-wait
# only covers ">= 1 match", so without this wait a hidden or zero-sized
# match would dispatch at (0, 0) and hit whatever sits there. Rects are
# viewport-relative and go stale after the scroll, so each attempt
# scrolls first, then reads. This helper is the seam where the
# cursor/staging work swaps in the animated scroll and the cursor
# glide; keep scroll + rect + center together.
el_pointer_point <- function(ctx, els, call = caller_env()) {
  point <- NULL
  pz_poll(
    fn = function() {
      el_scroll_into_view(els, call = call)
      probe <- els_call(els, pointer_actionable_js, call = call)
      if (
        length(probe) == 5L && probe[1] == 1 && probe[4] > 0 && probe[5] > 0
      ) {
        point <<- c(
          x = probe[2] + probe[4] / 2,
          y = probe[3] + probe[5] / 2
        )
        TRUE
      } else {
        FALSE
      }
    },
    timeout = ctx$page$default_timeout,
    loop = ctx$page$child_loop,
    what = paste0(els$description, " to become visible with a non-empty box"),
    call = call
  )
  point
}

# Every CDP command from the actions runs with the page's default
# timeout; a chromote command timeout is re-raised as
# paparazzi_error_timeout naming the action and its target (the same
# mapping as loc_resolve_once()). `cmd` stays a lazy promise, so the
# dispatch itself is forced under the tryCatch.
action_cdp <- function(ctx, action, target = NULL, cmd, call = caller_env()) {
  timeout <- ctx$page$default_timeout
  tryCatch(
    cmd,
    error = function(e) {
      if (grepl("timed out", conditionMessage(e), ignore.case = TRUE)) {
        cli::cli_abort(
          if (is.null(target)) {
            "Timed out after {timeout}s {action}."
          } else {
            "Timed out after {timeout}s {action} {target}."
          },
          class = "paparazzi_error_timeout",
          call = call,
          parent = e
        )
      }
      stop(e)
    }
  )
}

# One Input.dispatchMouseEvent at `point`, pointerType "mouse";
# `action` and `target` name the dispatch in timeout errors.
dispatch_mouse <- function(
  ctx,
  action,
  target,
  type,
  point,
  button,
  buttons,
  clickCount,
  call = caller_env()
) {
  action_cdp(
    ctx,
    action = action,
    target = target,
    call = call,
    cmd = ctx$page$session$Input$dispatchMouseEvent(
      type = type,
      x = point[["x"]],
      y = point[["y"]],
      button = button,
      buttons = buttons,
      clickCount = clickCount,
      pointerType = "mouse",
      timeout_ = ctx$page$default_timeout
    )
  )
}

# The real pointer sequence behind pz_click() and pz_type()'s
# focus-via-click: a move to the point first so pointer state stays
# real (:hover, the cursor), then a left-button press and release at the
# same point.
dispatch_click <- function(ctx, action, target, point, call = caller_env()) {
  dispatch_mouse(
    ctx,
    action,
    target,
    "mouseMoved",
    point,
    button = "none",
    buttons = 0,
    clickCount = 0,
    call = call
  )
  dispatch_mouse(
    ctx,
    action,
    target,
    "mousePressed",
    point,
    button = "left",
    buttons = 1,
    clickCount = 1,
    call = call
  )
  dispatch_mouse(
    ctx,
    action,
    target,
    "mouseReleased",
    point,
    button = "left",
    buttons = 0,
    clickCount = 1,
    call = call
  )
}

insert_text <- function(ctx, target, text, call = caller_env()) {
  action_cdp(
    ctx,
    "typing into",
    target,
    call = call,
    cmd = ctx$page$session$Input$insertText(
      text,
      timeout_ = ctx$page$default_timeout
    )
  )
}

#' Click an element
#'
#' Auto-waits for the element to be actionable -- visible with a
#' non-empty box, the same "visible" [pz_expect_visible()] uses -- then
#' scrolls it into view (instantly) and clicks the center of it with
#' real browser input events: a mouse move to the point, then a
#' left-button press and release. The page sees a trusted pointer
#' sequence -- exactly what a user's click produces -- so `:hover`
#' state, focus, and click handlers all behave as they would live.
#'
#' @param ctx A paparazzi context.
#' @param target A CSS selector string, a [pz_loc()] spec, or a list of
#'   specs (a union matching any of them). `NULL` uses the current
#'   scope; at the root context a target is required.
#' @param ... Checked empty; reserved for future use.
#' @return `ctx`, invisibly.
#' @seealso [pz_hover()], [pz_type()], [pz_press()]
#' @export
pz_click <- function(ctx, target = NULL, ...) {
  check_context(ctx)
  check_dots_empty()
  call <- current_env()
  found <- action_elements(ctx, target, call = call)
  if (!found$pinned) {
    on.exit(release_elements(found$els), add = TRUE)
  }
  point <- el_pointer_point(ctx, found$els, call = call)
  dispatch_click(ctx, "clicking", found$els$description, point, call = call)
  invisible(ctx)
}

#' Hover the pointer over an element
#'
#' Auto-waits for the element to be actionable -- visible with a
#' non-empty box -- then scrolls it into view (instantly) and moves the
#' pointer to the center of it with a real `mousemove` event, without
#' pressing any button. This is what drives `:hover` styles and
#' `mouseenter`/`mouseover` handlers.
#'
#' @param ctx A paparazzi context.
#' @param target A CSS selector string, a [pz_loc()] spec, or a list of
#'   specs (a union matching any of them). `NULL` uses the current
#'   scope; at the root context a target is required.
#' @param ... Checked empty; reserved for future use.
#' @return `ctx`, invisibly.
#' @seealso [pz_click()]
#' @export
pz_hover <- function(ctx, target = NULL, ...) {
  check_context(ctx)
  check_dots_empty()
  call <- current_env()
  found <- action_elements(ctx, target, call = call)
  if (!found$pinned) {
    on.exit(release_elements(found$els), add = TRUE)
  }
  point <- el_pointer_point(ctx, found$els, call = call)
  dispatch_mouse(
    ctx,
    "hovering over",
    found$els$description,
    "mouseMoved",
    point,
    button = "none",
    buttons = 0,
    clickCount = 0,
    call = call
  )
  invisible(ctx)
}

#' Type text into an element
#'
#' @description
#' With a `target`, auto-waits for the element to be actionable --
#' visible with a non-empty box -- then scrolls it into view, clicks
#' the center of it (real mouse events, so the element genuinely gains
#' focus), and inserts `text` at the caret -- the caret lands where the
#' click lands, just like a real user. With `target = NULL` at the
#' root context, inserts into whatever element currently has focus;
#' if nothing editable is focused, the text goes nowhere, exactly like
#' typing into a page with no focused field.
#'
#' Insertion is instant (one `insertText`); natural, per-keystroke
#' typing arrives with the recording task. For a value-setting primitive
#' that works on selects, checkboxes, and range inputs, see
#' `pz_set_value()` (a later task).
#'
#' @param ctx A paparazzi context.
#' @param text A string to type.
#' @param ... Checked empty; reserved for future use.
#' @param target A CSS selector string, a [pz_loc()] spec, or a list of
#'   specs (a union matching any of them). `NULL` uses the current
#'   scope or, at the root context, the focused element.
#' @return `ctx`, invisibly.
#' @seealso [pz_press()] for key combos (Enter, Control+A, ...) and
#'   [pz_click()].
#' @export
pz_type <- function(ctx, text, ..., target = NULL) {
  check_context(ctx)
  check_dots_empty()
  check_string(text)
  call <- current_env()

  # Root with no target: insert into whatever currently has focus.
  # Nothing editable focused means the text goes nowhere, matching what
  # a real keypress does in that situation.
  if (is.null(target) && is.null(scope_top(ctx))) {
    insert_text(ctx, "the focused element", text, call = call)
    return(invisible(ctx))
  }

  found <- action_elements(ctx, target, call = call)
  if (!found$pinned) {
    on.exit(release_elements(found$els), add = TRUE)
  }
  point <- el_pointer_point(ctx, found$els, call = call)
  # Focus comes from the real click pipeline (not JS .focus()) so
  # pointer state stays real.
  dispatch_click(ctx, "typing into", found$els$description, point, call = call)
  insert_text(ctx, found$els$description, text, call = call)
  invisible(ctx)
}

#' Press key combinations
#'
#' @description
#' Presses one or more key combinations against whatever the page
#' currently has focused, e.g. `"Enter"`, `"Control+A"`,
#' `c("Shift+Tab", "Escape")`. A vector presses each combination fully
#' (down then up) in order. Specs are `"Mod+Mod+Key"` strings with the
#' modifiers Control, Shift, Alt, and Meta (matched case-insensitively)
#' and a named key (Enter, Tab, Escape, Backspace, arrows, F1-F12, ...) or
#' a single printable character. Following Playwright, an uppercase
#' letter or shifted symbol implies Shift: `"Control+A"` sends
#' Control+Shift+A.
#'
#' Keys only reach focused elements; call [pz_click()] or [pz_focus()]
#' first to focus the element you're typing into.
#'
#' @param ctx A paparazzi context.
#' @param key A character vector of key specs.
#' @param ... Checked empty; reserved for future use.
#' @return `ctx`, invisibly.
#' @seealso [pz_type()] to insert text.
#' @export
pz_press <- function(ctx, key, ...) {
  check_context(ctx)
  check_dots_empty()
  check_character(key)

  call <- current_env()
  session <- ctx$page$session
  timeout <- ctx$page$default_timeout
  for (spec in key) {
    events <- key_events(key_parse(spec, call = call))
    for (event in events) {
      action_cdp(
        ctx,
        "pressing keys",
        call = call,
        cmd = do.call(
          session$Input$dispatchKeyEvent,
          c(event, list(timeout_ = timeout))
        )
      )
    }
  }
  invisible(ctx)
}

#' Focus an element
#'
#' Scrolls the element into view (instantly) and focuses it via the
#' browser's element focus method, so the page shows focus rings and
#' enabled-input styles exactly as a user would see them. Focus is an
#' element-state change, not an input event, so the direct method call
#' is the faithful implementation (Playwright does the same).
#'
#' @param ctx A paparazzi context.
#' @param target A CSS selector string, a [pz_loc()] spec, or a list of
#'   specs (a union matching any of them). `NULL` uses the current
#'   scope; at the root context a target is required.
#' @param ... Checked empty; reserved for future use.
#' @return `ctx`, invisibly.
#' @seealso [pz_blur()], [pz_type()]
#' @export
pz_focus <- function(ctx, target = NULL, ...) {
  check_context(ctx)
  check_dots_empty()
  call <- current_env()
  found <- action_elements(ctx, target, call = call)
  if (!found$pinned) {
    on.exit(release_elements(found$els), add = TRUE)
  }
  el_scroll_into_view(found$els, call = call)
  els_call(
    found$els,
    "function() { if (this.length) this[0].focus(); }",
    call = call
  )
  invisible(ctx)
}

#' Blur the focused element
#'
#' Removes focus from the current scope's element, or at the root
#' context from whatever element currently has focus (`document
#' .activeElement`). A no-op when the body is focused. Useful to clear
#' focus rings before a screenshot.
#'
#' @param ctx A paparazzi context.
#' @param ... Checked empty; reserved for future use.
#' @return `ctx`, invisibly.
#' @seealso [pz_focus()]
#' @export
pz_blur <- function(ctx, ...) {
  check_context(ctx)
  check_dots_empty()
  call <- current_env()
  scoped <- scope_root(ctx, call = call)
  if (!is.null(scoped)) {
    check_scope_single(scoped, call = call)
    els_call(
      scoped,
      "function() { if (this.length) this[0].blur(); }",
      call = call
    )
  } else {
    action_cdp(
      ctx,
      "blurring",
      "the focused element",
      call = call,
      cmd = ctx$page$session$Runtime$evaluate(
        "document.activeElement.blur()",
        returnByValue = TRUE,
        timeout_ = ctx$page$default_timeout
      )
    )
  }
  invisible(ctx)
}
