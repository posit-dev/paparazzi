# The pointer and keyboard actions. Input goes through CDP's Input
# domain -- real trusted events, never JS .click() substitutes. The one
# sanctioned exception is element focus()/blur() in pz_act_focus()/pz_act_blur()
# (element-state methods, not input events; Playwright does the same).
# Value and file setting is DOM state, not pointer input: the native
# prototype setters plus dispatched events (pz_set_value()), and
# DOM.setFileInputFiles (pz_set_files()).

#' How actions work
#'
#' @description
#' The contract shared by the `pz_act_*()` functions.
#'
#' @section Acting on the page:
#' The `pz_act_*()` functions use the page the way a person would. They send
#' real browser input, such as pointer moves, clicks and key presses, or use
#' the browser's own focus and text-selection methods. They never set a form
#' value directly.
#'
#' An action with a `target` looks for it in the current scope and waits until
#' it matches an element. Inside a scope, `target = NULL` acts on the scope's
#' element, and scrolling with `by` or `to` scrolls the scope's container. An
#' explicit target is scrolled into view first when needed. A few actions,
#' like [pz_act_press()], take no target and act on the focused element
#' instead.
#'
#' While the page is recording, actions are staged as [pz_stage()] sets them
#' up: the cursor glides to pointer targets, typing is paced, scrolls normally
#' use the mouse wheel, and the page holds for the staged `pause` afterward.
#' Without a recording, actions go straight to their final state.
#'
#' To set a value directly instead, without staging, use [pz_set_value()],
#' [pz_set_files()], or [pz_set_shiny_input()].
#'
#' @name paparazzi-actions
NULL

#' Click an element
#'
#' Auto-waits for the element to be actionable -- visible with a
#' non-empty box, the same "visible" [pz_expect_visible()] uses, and
#' receiving pointer events at its center (not covered by another
#' element) -- then scrolls it into view and clicks the center of it
#' with real browser input events: a mouse move to the point, then a
#' left-button press and release. The page sees a trusted pointer
#' sequence -- exactly what a user's click produces -- so `:hover` state, focus, and click
#' handlers all behave as they would live. While recording, the staging
#' settings ([pz_stage()]) animate the scroll, the cursor glide, and
#' the press; otherwise everything runs straight to the final state.
#'
#' @param ctx A paparazzi context.
#' @param target A CSS selector string, a [pz_loc()] spec, or a list of
#'   specs (a union matching any of them). `NULL` uses the current
#'   scope; at the root context a target is required.
#' @param ... Checked empty; reserved for future use.
#'
#' @return `ctx`, invisibly.
#'
#' @seealso [pz_act_hover()], [pz_act_type()], [pz_act_press()]
#'
#' @examplesIf paparazzi:::examples_run(site = TRUE)
#' page <- pz_open(pz_example("tasks"))
#' page |> pz_act_click("#toggle-help")
#' pz_get_text(page, target = "#toggle-help")
#'
#' # In a scoped context, target = NULL clicks the scope element
#' page |>
#'   pz_find(pz_loc(".task-done", within = pz_loc(".task", has_text = "bank"))) |>
#'   pz_act_click()
#' pz_get_count(page, target = ".task.done")
#' pz_close(page)
#'
#' @inheritSection paparazzi-actions Acting on the page
#'
#' @export
pz_act_click <- function(ctx, target = NULL, ...) {
  check_context(ctx)
  check_dots_empty()
  action_start(ctx)
  found <- action_elements(ctx, target)
  if (!found$pinned) {
    withr::defer(release_elements(found$els))
  }
  point <- el_pointer_point(ctx, found$els)
  dispatch_click(ctx, "clicking", found$els$description, point)
  stage_action_pause(ctx)
  ctx_return(ctx)
}

#' Hover the pointer over an element
#'
#' Auto-waits for the element to be actionable -- visible with a
#' non-empty box and receiving pointer events at its center (not covered
#' by another element) -- then scrolls it into view and moves the
#' pointer to the center of it with a real `mousemove` event, without
#' pressing any button. This is what drives `:hover` styles and
#' `mouseenter`/`mouseover` handlers.
#'
#' @inheritParams pz_act_click
#'
#' @return `ctx`, invisibly.
#'
#' @seealso [pz_act_click()]
#'
#' @examplesIf paparazzi:::examples_run(site = TRUE)
#' page <- pz_open(pz_example("tasks"))
#' passport <- pz_loc(".task", has_text = "passport")
#'
#' # Tasks change colour on :hover
#' pz_get_style(page, "background-color", target = passport)
#' page |> pz_act_hover(passport)
#' pz_get_style(page, "background-color", target = passport)
#' pz_close(page)
#'
#' @inheritSection paparazzi-actions Acting on the page
#'
#' @export
pz_act_hover <- function(ctx, target = NULL, ...) {
  check_context(ctx)
  check_dots_empty()
  action_start(ctx)
  found <- action_elements(ctx, target)
  if (!found$pinned) {
    withr::defer(release_elements(found$els))
  }
  point <- el_pointer_point(ctx, found$els)
  dispatch_mouse(
    ctx,
    "hovering over",
    found$els$description,
    "mouseMoved",
    point,
    button = "none",
    buttons = 0,
    clickCount = 0
  )
  stage_action_pause(ctx)
  ctx_return(ctx)
}

#' Type text into an element
#'
#' @description
#' With a `target`, auto-waits for the element to be actionable --
#' visible with a non-empty box and receiving pointer events at its center
#' (not covered by another element) -- then scrolls it into view, clicks
#' the center of it (real mouse events, so the element genuinely gains
#' focus), and inserts `text` at the caret -- the caret lands where the
#' click lands, just like a real user. With `target = NULL` at the
#' root context, inserts into whatever element currently has focus;
#' if nothing editable is focused, the text goes nowhere, exactly like
#' typing into a page with no focused field.
#'
#' Insertion is instant (one `insertText`), except while recording
#' with `typing = "natural"` (the default; see [pz_stage()]): one
#' `insertText` per character with randomized delays around
#' `typing_speed`, so the video shows the text appearing. While
#' recording, the cursor that clicked the field fades out so it doesn't
#' cover the text, and fades back in when the next action moves it. For
#' a value-setting primitive that works on selects, checkboxes, and range
#' inputs, see [pz_set_value()].
#'
#' @inheritParams pz_act_click
#' @param text A string to type.
#' @param target A CSS selector string, a [pz_loc()] spec, or a list of
#'   specs (a union matching any of them). `NULL` uses the current
#'   scope or, at the root context, the focused element.
#'
#' @return `ctx`, invisibly.
#'
#' @seealso [pz_act_press()] for key combos (Enter, Control+A, ...) and
#'   [pz_act_click()].
#'
#' @examplesIf paparazzi:::examples_run(site = TRUE)
#' page <- pz_open(pz_example("tasks"))
#' page |> pz_act_type("Buy milk", target = "#task-title")
#' pz_get_value(page, target = "#task-title")
#'
#' # Typing fires input events, so the page reacts: Add is now enabled
#' pz_expect_enabled(page, target = "#add-task")
#'
#' # At the root, target = NULL types into the focused element
#' page |> pz_act_type(" and eggs")
#' pz_get_value(page, target = "#task-title")
#' pz_close(page)
#'
#' @inheritSection paparazzi-actions Acting on the page
#'
#' @export
pz_act_type <- function(ctx, text, ..., target = NULL) {
  check_context(ctx)
  check_dots_empty()
  action_start(ctx)
  check_string(text)

  # Root with no target: insert into whatever currently has focus.
  # Nothing editable focused means the text goes nowhere, matching what
  # a real keypress does in that situation.
  if (is.null(target) && is.null(scope_top(ctx))) {
    if (
      stage_recording(ctx$page) && isTRUE(page_stage(ctx$page)$camera_follow)
    ) {
      rect <- pz_js(
        ctx,
        "(() => { const e = document.activeElement; if (!e || e === document.body) return null; const r = e.getBoundingClientRect(); return [r.x, r.y, r.width, r.height]; })()"
      )
      if (!is.null(rect)) {
        stage_follow_without_glide(
          ctx,
          set_names(unlist(rect), c("x", "y", "width", "height"))
        )
      }
    }
    insert_text(ctx, "the focused element", text)
    stage_action_pause(ctx)
    return(ctx_return(ctx))
  }

  found <- action_elements(ctx, target)
  if (!found$pinned) {
    withr::defer(release_elements(found$els))
  }
  # The scoped select-then-type step: the scope element holds the
  # page's real selection, and a keypress replaces it. The focusing
  # click below would collapse the selection first, so a scoped
  # element with an active selection is typed into directly (the
  # element is focused in the probe). Only the no-target path: an
  # explicit target keeps its click-to-focus.
  if (is.null(target) && isTRUE(els_call(found$els, type_selection_js))) {
    stage_follow_without_glide(ctx, action_target_rect(found$els))
    insert_text(ctx, found$els$description, text)
    stage_action_pause(ctx)
    return(ctx_return(ctx))
  }
  point <- el_pointer_point(ctx, found$els)
  # Focus comes from the real click pipeline (not JS .focus()) so
  # pointer state stays real.
  dispatch_click(ctx, "typing into", found$els$description, point)
  cursor_rest(ctx)
  insert_text(ctx, found$els$description, text)
  stage_action_pause(ctx)
  ctx_return(ctx)
}

#' Press key combinations
#'
#' @description
#' Presses one or more key combinations against whatever the page
#' currently has focused, e.g. `"Enter"`, `"Control+A"`,
#' `c("Shift+Tab", "Escape")`. A vector presses each combination fully
#' (down then up) in order. Specs are `"Mod+Mod+Key"` strings with the
#' modifiers Control, Shift, Alt, Meta, and Mod (matched case-insensitively)
#' and a named key (Enter, Tab, Escape, Backspace, arrows, F1-F12, ...) or
#' a single printable character. `Mod` resolves to Meta on browsers reporting
#' a Mac platform (`navigator.userAgentData.platform` or `navigator.platform`),
#' and Control otherwise. Following Playwright, an uppercase
#' letter or shifted symbol implies Shift: `"Control+A"` sends
#' Control+Shift+A.
#'
#' Keys only reach focused elements; call [pz_act_click()] or [pz_act_focus()]
#' first to focus the element you're typing into.
#'
#' @inheritParams pz_act_click
#' @param key A character vector of key specs.
#' @param show_keys `NULL` uses the page's [pz_stage()] setting (initially
#'   `"none"`). `"words"` shows named modifier keycaps, `"mac"` uses
#'   Mac symbols, and `"both"` shows `Mod` as `Ctrl / ⌘`.
#'   Keystroke callouts appear only in recordings; subsequent calls replace
#'   earlier ones. A vector is displayed as a single sequence. In a GIF
#'   recording, keystroke callouts need the av package.
#'
#' @return `ctx`, invisibly.
#'
#' @seealso [pz_act_type()] to insert text.
#'
#' @examplesIf paparazzi:::examples_run(site = TRUE)
#' page <- pz_open(pz_example("tasks"))
#' page |>
#'   pz_act_type("Buy milkk", target = "#task-title") |>
#'   pz_act_press("Backspace")
#' pz_get_value(page, target = "#task-title")
#'
#' # Enter submits the form; the page shows "Saving..." before the task appears
#' page |> pz_act_press("Enter")
#' pz_expect_text(page, "Saved", target = "#status")
#' pz_get_text(page, target = pz_loc(".task-title", which = "first"))
#'
#' # A vector presses keys in sequence; + joins keys pressed together
#' page |> pz_act_press(c("Tab", "Shift+Tab"))
#' pz_expect_focused(page, target = "#task-title")
#' pz_close(page)
#'
#' @inheritSection paparazzi-actions Acting on the page
#'
#' @export
pz_act_press <- function(ctx, key, ..., show_keys = NULL) {
  check_context(ctx)
  check_dots_empty()
  action_start(ctx)
  check_character(key)
  show_keys <- show_keys %||% page_stage(ctx$page)$show_keys
  show_keys <- arg_match(show_keys, c("none", "words", "mac", "both"))

  session <- ctx$page$session
  timeout <- ctx$page$default_timeout
  mod <- NULL
  if (any(grepl("(^|\\+)mod\\+", key, ignore.case = TRUE))) {
    mac <- pz_js(
      ctx,
      "/^mac/i.test(navigator.userAgentData?.platform || navigator.platform || '')"
    )
    mod <- if (isTRUE(mac)) "Meta" else "Control"
  }
  rec <- page_recorder(ctx$page)
  showing <- !is.null(rec) &&
    isTRUE(rec$active) &&
    !isTRUE(rec$paused) &&
    show_keys != "none"
  if (showing) {
    if (identical(rec$format, "gif")) {
      rlang::check_installed("av", reason = "to show keystrokes in GIFs.")
    }
    started <- rec_vt(rec)
    pressed <- vector("list", length(key))
  }
  for (i in seq_along(key)) {
    spec <- key[[i]]
    parsed <- key_parse(spec, mod = mod)
    events <- key_events(parsed)
    for (event in events) {
      action_cdp(
        ctx,
        "pressing keys",
        cmd = do.call(
          session$Input$dispatchKeyEvent,
          c(event, list(timeout_ = timeout))
        )
      )
    }
    if (showing) {
      pressed[[i]] <- list(spec = spec, resolved = parsed)
    }
  }
  if (showing) {
    rec$keypresses <- c(
      rec$keypresses,
      list(list(
        vt = started,
        last = rec_vt(rec),
        style = show_keys,
        keys = pressed
      ))
    )
  }
  stage_action_pause(ctx)
  ctx_return(ctx)
}

#' Focus an element
#'
#' Scrolls the element into view (instantly) and focuses it via the
#' browser's element focus method, so the page shows focus rings and
#' enabled-input styles exactly as a user would see them. Focus is an
#' element-state change, not an input event, so the direct method call
#' is the faithful implementation (Playwright does the same).
#'
#' @inheritParams pz_act_click
#'
#' @return `ctx`, invisibly.
#'
#' @seealso [pz_act_blur()], [pz_act_type()]
#'
#' @examplesIf paparazzi:::examples_run()
#' page <- pz_open(pz_example("tasks"))
#' page |> pz_act_focus("#task-title")
#' pz_expect_focused(page, target = "#task-title")
#' pz_close(page)
#'
#' @inheritSection paparazzi-actions Acting on the page
#'
#' @export
pz_act_focus <- function(ctx, target = NULL, ...) {
  check_context(ctx)
  check_dots_empty()
  action_start(ctx)
  found <- action_elements(ctx, target)
  if (!found$pinned) {
    withr::defer(release_elements(found$els))
  }
  el_scroll_into_view(found$els)
  els_call(
    found$els,
    "function() { if (this.length) this[0].focus(); }"
  )
  stage_action_pause(ctx)
  ctx_return(ctx)
}

#' Blur the focused element
#'
#' Removes focus from the current scope's element, or at the root
#' context from whatever element currently has focus (`document
#' .activeElement`). A no-op when the body is focused. Useful to clear
#' focus rings before a screenshot.
#'
#' @inheritParams pz_act_click
#'
#' @return `ctx`, invisibly.
#'
#' @seealso [pz_act_focus()]
#'
#' @examplesIf paparazzi:::examples_run()
#' page <- pz_open(pz_example("tasks"))
#' page |> pz_act_focus("#task-title")
#'
#' # Remove the focus ring, e.g. before a screenshot
#' page |> pz_act_blur()
#' pz_expect_focused(page, target = "#task-title", not = TRUE)
#' pz_close(page)
#'
#' @inheritSection paparazzi-actions Acting on the page
#'
#' @export
pz_act_blur <- function(ctx, ...) {
  check_context(ctx)
  check_dots_empty()
  action_start(ctx)
  scoped <- scope_root(ctx)
  if (!is.null(scoped)) {
    check_scope_single(scoped)
    els_call(
      scoped,
      "function() { if (this.length) this[0].blur(); }"
    )
  } else {
    action_cdp(
      ctx,
      "blurring",
      "the focused element",
      cmd = ctx$page$session$Runtime$evaluate(
        "document.activeElement.blur()",
        returnByValue = TRUE,
        timeout_ = ctx$page$default_timeout
      )
    )
  }
  stage_action_pause(ctx)
  ctx_return(ctx)
}

#' Set the value of a form control
#'
#' Auto-waits for a match, then sets the value instantly -- never staged
#' as typing, even while recording -- and dispatches `input` and
#' `change`, so the page reacts exactly as if a user had made the edit.
#' Framework-controlled inputs (React and friends) notice the change:
#' the value is assigned through the browser's native value setter, not
#' the instance-level property those frameworks intercept.
#'
#' Covers text inputs and textareas (clear with `pz_set_value(ctx, "")`),
#' native `<select>` elements (matched by option `value`), checkboxes
#' and radios (`TRUE`/`FALSE`; a radio set to `TRUE` unchecks the others
#' in its group), and range, date, and number inputs. A contenteditable
#' element (plain or framework-driven, e.g. ProseMirror) has its
#' content replaced in one step.
#'
#' @inheritParams pz_act_click
#' @param value A string (most controls), a number (range, number), or
#'   `TRUE`/`FALSE` (checkboxes, radios).
#'
#' @return `ctx`, invisibly.
#'
#' @seealso [pz_act_type()] for visible, keystroke-by-keystroke input and
#'   [pz_set_files()].
#'
#' @examplesIf paparazzi:::examples_run(site = TRUE)
#' page <- pz_open(pz_example("tasks"))
#' page |>
#'   pz_set_value("Buy milk", target = "#task-title") |>
#'   pz_set_value("high", target = "#task-priority") |>
#'   pz_set_value(TRUE, target = "#task-urgent")
#' pz_get_value(page, target = list("#task-title", "#task-priority"))
#' pz_expect_checked(page, target = "#task-urgent")
#'
#' # An empty string clears a text input
#' page |> pz_set_value("", target = "#task-title")
#' pz_expect_enabled(page, target = "#add-task", not = TRUE)
#' pz_close(page)
#'
#' @export
pz_set_value <- function(ctx, value, ..., target = NULL) {
  check_context(ctx)
  check_dots_empty()
  action_start(ctx)
  arg <- set_value_argument(value)

  found <- action_elements(ctx, target)
  if (!found$pinned) {
    withr::defer(release_elements(found$els))
  }
  el_scroll_into_view(found$els)

  res <- els_values(
    found$els,
    set_value_js,
    args = list(list(value = arg)),
    doing = "working with"
  )
  if (identical(res$status, "contenteditable")) {
    els_call(found$els, select_all_js)
    insert_text(ctx, found$els$description, arg$text)
    return(ctx_return(ctx))
  }
  if (!identical(res$status, "ok")) {
    cli::cli_abort(
      c(res$message, i = "Target: {found$els$description}"),
      class = "paparazzi_error_value"
    )
  }
  ctx_return(ctx)
}

#' Attach files to a file input
#'
#' Auto-waits for a match, then sets the input's files to the given
#' local files through the browser's own file-input channel, so the
#' input's `FileList` holds the real names, sizes, and contents, and
#' `change` fires exactly as if the files had been picked in a dialog.
#'
#' @inheritParams pz_act_click
#' @param files A character vector of paths to existing local files.
#'
#' @return `ctx`, invisibly.
#'
#' @seealso [pz_set_value()]
#'
#' @examplesIf paparazzi:::examples_run(site = TRUE)
#' notes <- file.path(tempdir(), "meeting-notes.txt")
#' writeLines("Agenda: plants, parcel, passport", notes)
#'
#' page <- pz_open(pz_example("tasks"))
#' page |> pz_set_files(notes, target = "#attachment")
#' pz_get_text(page, target = "#attachment-name")
#' pz_close(page)
#'
#' @export
pz_set_files <- function(ctx, files, ..., target = NULL) {
  check_context(ctx)
  check_dots_empty()
  action_start(ctx)
  files <- check_file_paths(files)

  found <- action_elements(ctx, target)
  if (!found$pinned) {
    withr::defer(release_elements(found$els))
  }
  el_scroll_into_view(found$els)
  if (
    !isTRUE(els_call(
      found$els,
      "function() { const el = this[0]; return el.tagName === 'INPUT' && el.type === 'file'; }"
    ))
  ) {
    cli::cli_abort(
      c("Target is not a file input.", i = "Target: {found$els$description}"),
      class = "paparazzi_error_value"
    )
  }

  # A resolved set's handle is the JS array of elements, not the
  # element; DOM.setFileInputFiles addresses the element itself.
  el_object_id <- els_first_object_id(found$els)
  withr::defer(try(
    found$els$page$session$Runtime$releaseObject(
      el_object_id,
      timeout_ = found$els$page$default_timeout
    ),
    silent = TRUE
  ))
  action_cdp(
    ctx,
    "setting files on",
    found$els$description,
    cmd = ctx$page$session$DOM$setFileInputFiles(
      # A single path must stay a one-element array in the CDP payload.
      as.list(files),
      objectId = el_object_id,
      timeout_ = ctx$page$default_timeout
    )
  )
  ctx_return(ctx)
}

#' Select text inside an element
#'
#' Auto-waits for a match, then highlights the exact `text` inside it
#' as if dragging across it: the substring is found among the element's
#' text nodes (so a match spanning inline tags, e.g. across an `<em>`
#' and a `<strong>`, is selected as one piece) and becomes the page's
#' real window selection. Typing afterwards replaces it -- call
#' [pz_act_type()] with `target = NULL`, which inserts into whatever has
#' focus.
#'
#' A contenteditable target is focused too (dragging across editable
#' text focuses it, and that focus is where the typing lands); a static
#' target is not.
#'
#' @inheritParams pz_act_click
#' @param text A string to select. Must appear exactly in the element,
#'   across tags if needed; not found is an error.
#' @param target A CSS selector string, a [pz_loc()] spec, or a list of
#'   specs (a union matching any of them). `NULL` uses the current
#'   scope; at the root context a target is required.
#'
#' @return `ctx`, invisibly.
#'
#' @seealso [pz_act_type()], [pz_set_value()]
#'
#' @examplesIf paparazzi:::examples_run(site = TRUE)
#' page <- pz_open(pz_example("tasks"))
#'
#' # Typing replaces the selection
#' page |>
#'   pz_find(pz_loc(".task", has_text = "Renew passport")) |>
#'   pz_act_click(".task-edit") |>
#'   pz_find(".task-title") |>
#'   pz_act_select_text("passport") |>
#'   pz_act_type("driving licence") |>
#'   pz_act_press("Enter") |>
#'   pz_get_text()
#' pz_close(page)
#'
#' @inheritSection paparazzi-actions Acting on the page
#'
#' @export
pz_act_select_text <- function(ctx, text, ..., target = NULL) {
  check_context(ctx)
  check_dots_empty()
  action_start(ctx)
  check_string(text)
  if (!nzchar(text)) {
    cli::cli_abort(
      "{.arg text} can't be empty.",
      class = "paparazzi_error_input"
    )
  }

  found <- action_elements(ctx, target)
  if (!found$pinned) {
    withr::defer(release_elements(found$els))
  }
  el_scroll_into_view(found$els)

  res <- els_values(
    found$els,
    select_text_js,
    args = list(list(value = text)),
    doing = "working with"
  )
  if (!identical(res$status, "ok")) {
    cli::cli_abort(
      c(
        "No {.str {text}} in {found$els$description}.",
        i = "The match must contain the exact text, across tags if needed."
      ),
      class = "paparazzi_error_text"
    )
  }
  stage_follow_without_glide(ctx, action_target_rect(found$els))
  stage_action_pause(ctx)
  ctx_return(ctx)
}

#' Scroll the page or an element into view
#'
#' @description
#' Exactly one of `target`, `by`, and `to`:
#'
#' - `target`: auto-waits for a match, then scrolls it into view
#'   (instantly outside a recording).
#' - `by = c(x, y)`: scrolls the current scope's scroll container --
#'   the scope element or its nearest scrollable ancestor, or the page
#'   itself at the root context -- by that many pixels.
#' - `to`: scrolls that same container to an edge or corner from the
#'   direction vocabulary: `"top"`, `"bottom"`, `"left"`, `"right"`,
#'   the four corners, or `"center"` (e.g. `"bottom"` scrolls to the
#'   end; `"top right"` to the top-right corner).
#'
#' Scrolling is instant outside a recording; while recording it is
#' staged as real mouse wheel events with the cursor over the
#' container, so the video shows the scroll. Wheel scrolling is
#' best-effort: if the page swallows the events, the instant scroll
#' still guarantees the final position.
#'
#' @inheritParams pz_act_click
#' @param target A CSS selector string, a [pz_loc()] spec, or a list of
#'   specs (a union matching any of them). Scrolled into view. `NULL`
#'   disables the element-target mode; use `by` or `to` instead.
#' @param by Offset in pixels, `c(x, y)` (or a single number for both
#'   axes). `NULL` disables the offset mode.
#' @param to A direction string: the sides, the four corners, or
#'   `"center"`. `NULL` disables the direction mode.
#' @param duration Seconds per staged wheel scroll; `NULL` computes the
#'   time from the scroll distance and `cursor_speed` in [pz_stage()].
#'   Applies only while recording, including `target` and any scroll
#'   needed to bring a scoped container into view. Use 0 to scroll
#'   instantly without wheel animation.
#'
#' @return `ctx`, invisibly.
#'
#' @seealso [pz_find()], [pz_act_click()]
#'
#' @examplesIf paparazzi:::examples_run(site = TRUE)
#' page <- pz_open(pz_example("tasks"), height = 600)
#'
#' # With a target, scroll it into view
#' page |> pz_act_scroll("#toggle-help")
#' pz_expect_in_viewport(page, target = "#toggle-help")
#'
#' # With `to` or `by`, scroll the current scope's container: here the list
#' page |>
#'   pz_find(".task-list") |>
#'   pz_act_scroll(to = "bottom")
#' pz_expect_in_viewport(page, target = pz_loc(".task", which = "last"))
#'
#' # At the root, the container is the page itself
#' page |> pz_act_scroll(to = "top")
#' pz_js(page, "window.scrollY")
#' pz_close(page)
#'
#' @inheritSection paparazzi-actions Acting on the page
#'
#' @export
pz_act_scroll <- function(
  ctx,
  target = NULL,
  ...,
  by = NULL,
  to = NULL,
  duration = NULL
) {
  check_context(ctx)
  check_dots_empty()
  check_number_decimal(
    duration,
    min = 0,
    allow_null = TRUE,
    allow_infinite = FALSE
  )
  action_start(ctx)
  modes <- c(target = !is.null(target), by = !is.null(by), to = !is.null(to))
  if (sum(modes) != 1L) {
    cli::cli_abort(
      "Supply exactly one of {.arg target}, {.arg by}, or {.arg to}.",
      class = "paparazzi_error_input"
    )
  }

  if (!is.null(target)) {
    found <- action_elements(ctx, target)
    if (!found$pinned) {
      withr::defer(release_elements(found$els))
    }
    stage_scroll_into_view(ctx, found$els, duration = duration)
    stage_action_pause(ctx)
    return(ctx_return(ctx))
  }

  by <- if (!is.null(by)) check_offset(by, arg = "by") else NULL
  to <- if (!is.null(to)) parse_direction(to, arg = "to") else NULL
  scoped <- scope_root(ctx)
  # by/to act on the scope's ONE container, before both the staged
  # wheel branch and the instant JS -- a multi-match scope has no
  # single container, the same error every scoped element action
  # raises.
  if (!is.null(scoped)) {
    check_scope_single(scoped)
  }
  if (stage_recording(ctx$page) && !isTRUE(duration == 0)) {
    scroll_staged(ctx, scoped, by, to, duration = duration)
    stage_action_pause(ctx)
    return(ctx_return(ctx))
  }
  if (!is.null(scoped)) {
    # Offsets serialize as JSON numbers: a scalar integer offset
    # keeps its integer type through check_offset()'s length-1 rep().
    arg <- if (!is.null(by)) {
      list(by = as.list(as.double(by)))
    } else {
      list(to = as.list(to))
    }
    els_values(
      scoped,
      scroll_apply_js,
      args = list(list(value = arg)),
      doing = "working with"
    )
  } else {
    res <- action_cdp(
      ctx,
      "scrolling",
      cmd = ctx$page$session$Runtime$evaluate(
        paste0(
          "(",
          scroll_apply_js,
          ").call([], ",
          scroll_arg_json(by, to),
          ")"
        ),
        returnByValue = TRUE,
        timeout_ = ctx$page$default_timeout
      )
    )
    cdp_check_exception(res, "scrolling")
  }
  stage_action_pause(ctx)
  ctx_return(ctx)
}

#' Drag an element to another element or by an offset
#'
#' @description
#' Auto-waits for the source to be actionable: visible, non-empty, and
#' receiving pointer events at its center (not covered by another element).
#' With `to`, the destination is checked for visibility and that it receives
#' the drop at its center after the source is brought into view.
#' It then drags with real mouse input: press at the source's center,
#' move to the destination, release. When the source is a
#' real HTML5 drag source (`draggable`, including inherited
#' `draggable` or the image/`<a href>` defaults), the drag runs through
#' the browser's drag pipeline instead: the press and move start a
#' genuine `dragstart` (so `dataTransfer` holds whatever the page put
#' there), and the drop is delivered to the destination as trusted
#' `dragenter`/`dragover`/`drop` events with that payload.
#'
#' While recording, the staging ([pz_stage()]) shows the press at the
#' source and glides the cursor while holding from the source to the
#' destination, so the drop lands as the cursor arrives. On the HTML5
#' path the carry runs between the page's `dragstart` and the replayed
#' `drop`, so `dragstart` styling stays visible through the carry.
#'
#' `to` names the element to drop onto; `by = c(x, y)` drops at that
#' offset in pixels from the source's center. Supply exactly one.
#'
#' @inheritParams pz_act_click
#' @param target A CSS selector string, a [pz_loc()] spec, or a list of
#'   specs (a union matching any of them). The drag source. Unlike most
#'   actions it is always required.
#' @param to A CSS selector string, a [pz_loc()] spec, or a list of
#'   specs (a union matching any of them): the drop target. `NULL` omits
#'   the absolute destination. Supply exactly one of `to` or `by`.
#' @param by Offset in pixels from the source's center, `c(x, y)` (or a
#'   single number for both axes). `NULL` disables the offset mode.
#'
#' @return `ctx`, invisibly.
#'
#' @seealso [pz_act_click()], [pz_act_hover()]
#'
#' @examplesIf paparazzi:::examples_run(site = TRUE)
#' page <- pz_open(pz_example("tasks"))
#' pz_get_text(page, target = ".task-title")
#'
#' # The tasks are HTML5 drag sources; drop "Water the plants" on the first task
#' page |>
#'   pz_act_drag(
#'     pz_loc(".task", has_text = "plants"),
#'     to = pz_loc(".task", which = "first")
#'   )
#' pz_get_text(page, target = ".task-title")
#' pz_close(page)
#'
#' @inheritSection paparazzi-actions Acting on the page
#'
#' @export
pz_act_drag <- function(ctx, target, to = NULL, ..., by = NULL) {
  check_context(ctx)
  check_dots_empty()
  action_start(ctx)
  # NULL must not reach the resolver, where it means document.body.
  to_dest <- !is.null(to)
  by_offset <- !is.null(by)
  if (!to_dest && !by_offset) {
    cli::cli_abort(
      "Supply {.arg to} or {.arg by}.",
      class = "paparazzi_error_input"
    )
  }
  if (to_dest && by_offset) {
    cli::cli_abort(
      "Supply either {.arg to} or {.arg by}, not both.",
      class = "paparazzi_error_input"
    )
  }

  found <- action_elements(ctx, target)
  if (!found$pinned) {
    withr::defer(release_elements(found$els))
  }

  if (!to_dest) {
    from <- el_pointer_point(ctx, found$els)
    offset <- check_offset(by, arg = "by")
    to_point <- c(
      x = from[["x"]] + offset[[1]],
      y = from[["y"]] + offset[[2]]
    )
  } else {
    dest <- loc_resolve(ctx, to, multiple = "error")
    withr::defer(release_elements(dest))
    # Destination point first: the source's scroll can shift the
    # destination rect, so the drop point is re-read once after (no
    # scroll, so it can't shift back). Both endpoints must then share
    # the viewport -- a real drag can't span two screens of a tall
    # page, and a drop dispatched off-screen lands on nothing.
    to_point <- el_actionable_point(ctx, dest)
    from <- el_pointer_point(ctx, found$els)
    probe <- els_values(dest, dest_point_js)
    if (isTRUE(probe$visible) && probe$width > 0 && probe$height > 0) {
      drop <- c(
        x = probe$x + probe$width / 2,
        y = probe$y + probe$height / 2
      )
      if (
        drop[[1]] < 0 ||
          drop[[1]] > probe$viewportWidth ||
          drop[[2]] < 0 ||
          drop[[2]] > probe$viewportHeight
      ) {
        cli::cli_abort(
          c(
            "The drag destination is outside the viewport after bringing the source into view.",
            i = "Both endpoints must be visible at once, like a real drag; scroll or scope so they are."
          ),
          class = "paparazzi_error_target"
        )
      }
      if (!is.null(probe$blocker)) {
        blocker_name <- format_pointer_blocker(probe$blocker)
        cli::cli_abort(
          c(
            "The drag destination {dest$description} does not receive pointer events at its center after bringing the source into view; blocked by {blocker_name}.",
            i = "Both endpoints must be visible at once, like a real drag; scroll or scope so they are."
          ),
          class = c("paparazzi_error_obstructed", "paparazzi_error_target")
        )
      }
      to_point <- drop
    } else {
      # The source's scroll hid or emptied the destination: its
      # earlier point is stale, so dropping there lands on whatever
      # moved in -- a failed final probe is a non-actionable
      # destination, not a fall-through.
      cli::cli_abort(
        c(
          "The drag destination is no longer visible with a non-empty box after bringing the source into view.",
          i = "Both endpoints must stay actionable at once, like a real drag; scroll or scope so they do."
        ),
        class = "paparazzi_error_target"
      )
    }
  }

  if (isTRUE(els_call(found$els, draggable_js))) {
    drag_html5(ctx, found$els, from, to_point)
  } else {
    dispatch_mouse_drag(
      ctx,
      "dragging",
      found$els$description,
      from,
      to_point
    )
  }
  stage_action_pause(ctx)
  ctx_return(ctx)
}

# Record before resolution or dispatch: either can trigger navigation.
action_start <- function(ctx) {
  ctx$page$.__enclos_env__$private$last_action_loader_ <-
    ctx$page$session$Page$getFrameTree(
      timeout_ = ctx$page$default_timeout
    )$frameTree$frame$loaderId
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

# Given a target and a viewport CSS point, return the receiving element's
# raw identity when it is not in the target's composed subtree. Keeping
# this separate lets destination probes use the same rule after source scroll.
pointer_hit_test_js <- "const pointerHitTest = (target, x, y) => {
  let hit = document.elementFromPoint(x, y);
  while (hit && hit.shadowRoot) {
    const inner = hit.shadowRoot.elementFromPoint(x, y);
    if (!inner || inner === hit) break;
    hit = inner;
  }
  for (let node = hit; node; node = node.parentNode || node.host) {
    if (node === target) return null;
  }
  return hit ? {
    tag: hit.tagName.toLowerCase(),
    id: hit.id,
    classes: Array.from(hit.classList)
  } : { tag: '', id: '', classes: [] };
};"

# A single post-scroll probe reads the center and verifies its event receiver.
pointer_actionable_js <- paste0(
  "function() {\n",
  pointer_hit_test_js,
  "
  if (!this.length) return { status: 'unavailable' };
  const el = this[0];
  const r = el.getBoundingClientRect();
  if (!el.checkVisibility({ checkVisibilityCSS: true }) ||
      r.width <= 0 || r.height <= 0) return { status: 'unavailable' };
  const x = r.x + r.width / 2;
  const y = r.y + r.height / 2;
  const blocker = pointerHitTest(el, x, y);
  return blocker ? { status: 'blocked', blocker } : { status: 'ok', x, y };
}"
)

format_pointer_blocker <- function(blocker) {
  if (!nzchar(blocker$tag)) {
    return("<none>")
  }
  classes <- unlist(blocker$classes, use.names = FALSE)
  paste0(
    blocker$tag,
    if (nzchar(blocker$id)) paste0("#", blocker$id),
    if (length(classes)) paste0(".", classes, collapse = "")
  )
}

# Scroll the first element into view and return the center of its
# bounding rect as c(x, y) (viewport CSS pixels), auto-waiting until it
# is actionable: visible, non-empty, and the topmost element at that
# point. Resolution auto-wait only covers ">= 1 match", so without this
# a hidden, zero-sized, or covered match would send input to whatever
# sits at the point. Rects go stale after the scroll, so each attempt
# scrolls first, then probes. The scroll and the post-poll cursor move
# are the staging seams (stage_scroll_into_view(), stage_move_cursor()).
el_pointer_point <- function(ctx, els, call = caller_env()) {
  point <- el_actionable_point(ctx, els, call = call)
  # The actionable point may sit on a descendant covering the target;
  # entry timing uses the RESOLVED target's rect, so glide-icon switches
  # happen at the target's edge, not a covering child's.
  rects <- el_rects(els, call = call)
  attr(point, "rect") <- c(
    x = rects$x[[1]],
    y = rects$y[[1]],
    width = rects$width[[1]],
    height = rects$height[[1]]
  )
  attr(point, "camera_follow") <- TRUE
  stage_move_cursor(ctx, point)
  point
}

action_target_rect <- function(els) {
  rects <- el_rects(els)
  c(
    x = rects$x[[1]],
    y = rects$y[[1]],
    width = rects$width[[1]],
    height = rects$height[[1]]
  )
}

el_actionable_point <- function(ctx, els, call = caller_env()) {
  point <- NULL
  blocker <- NULL
  timeout <- ctx$page$default_timeout
  tryCatch(
    pz_poll(
      fn = function() {
        blocker <<- NULL
        stage_scroll_into_view(ctx, els, call = call)
        probe <- els_values(els, pointer_actionable_js, call = call)
        if (identical(probe$status, "blocked")) {
          blocker <<- probe$blocker
          return(FALSE)
        }
        if (!identical(probe$status, "ok")) {
          return(FALSE)
        }
        point <<- c(x = probe$x, y = probe$y)
        TRUE
      },
      timeout = timeout,
      loop = ctx$page$child_loop,
      what = paste0(
        els$description,
        " to become visible with a non-empty box and receive pointer events"
      ),
      call = call
    ),
    paparazzi_error_timeout = function(e) {
      if (is.null(blocker)) {
        stop(e)
      }
      blocker_name <- format_pointer_blocker(blocker)
      cli::cli_abort(
        "Timed out after {timeout}s waiting for {els$description} to receive pointer events; blocked by {blocker_name}.",
        class = c("paparazzi_error_obstructed", "paparazzi_error_timeout"),
        call = call
      )
    }
  )
  point
}

# Use the page's default timeout; doing names the action and target.
action_cdp <- function(ctx, action, target = NULL, cmd, call = caller_env()) {
  cdp_call(
    cmd,
    ctx$page$default_timeout,
    doing = paste(c(action, target), collapse = " "),
    call = call
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

# The real pointer sequence behind pz_act_click() and pz_act_type()'s
# focus-via-click: a move to the point first so pointer state stays
# real (:hover, the cursor), then a left-button press and release at the
# same point. While recording with a visible cursor, the staging adds a
# short pause after the glide, plays the press scale-down around
# pressed/released, and holds briefly after; all of it is skipped
# otherwise (the SPEC matrix).
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
  staged <- stage_recording(ctx$page) && cursor_visible(ctx$page)
  if (staged) {
    pump_loop(ctx$page$child_loop, 0.15)
    cursor_press(ctx, TRUE)
    pump_loop(ctx$page$child_loop, 0.16)
  }
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
  if (staged) {
    cursor_press(ctx, FALSE)
    pump_loop(ctx$page$child_loop, 0.2)
  }
}

# Typing is instant everywhere except a recording with
# typing = "natural": one Input.insertText per character with a pumped,
# randomized delay around 1/typing_speed between characters (the
# recording captures the text growing; no typo simulation). The pumped
# delay keeps the recorder's ticks firing between keystrokes.
insert_text <- function(ctx, target, text, call = caller_env()) {
  page <- ctx$page
  stage <- page_stage(page)
  if (
    stage_recording(page) &&
      identical(stage$typing, "natural") &&
      nchar(text) > 1L
  ) {
    chars <- strsplit(text, "", fixed = TRUE)[[1]]
    for (char in chars) {
      insert_text_once(ctx, target, char, call = call)
      delay <- stats::runif(1L, 0.5, 1.5) / stage$typing_speed
      pump_loop(page$child_loop, delay, interval = min(delay, 0.03))
    }
    return(ctx_return(ctx))
  }
  insert_text_once(ctx, target, text, call = call)
}

insert_text_once <- function(ctx, target, text, call = caller_env()) {
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

# Does the element hold the page's active selection (pz_act_select_text's
# work), ready for a keypress to replace it? TRUE means the caller
# skips the focusing click -- a click collapses the selection -- and
# inserts instead; the focus the click would have produced is taken
# here, which keeps the selection (it lives inside the element).
type_selection_js <- "function() {
  const el = this[0];
  if (!el || !el.isContentEditable) {
    return false;
  }
  const sel = window.getSelection();
  if (!sel || sel.rangeCount === 0 || sel.isCollapsed) {
    return false;
  }
  if (!el.contains(sel.getRangeAt(0).commonAncestorContainer)) {
    return false;
  }
  el.focus();
  return true;
}"

# pz_set_value()'s `value` as the CDP callArgument the brancher reads: a
# kind discriminator ("text" or "checked") plus the value in both
# shapes, so the payload has the same shape for every R type.
set_value_argument <- function(value, call = caller_env()) {
  if (!is.character(value) && !is.numeric(value) && !is.logical(value)) {
    stop_input_type(
      value,
      "a string, a number, or TRUE/FALSE",
      arg = "value",
      call = call
    )
  }
  if (length(value) != 1L) {
    cli::cli_abort(
      "{.arg value} must be a single string, number, or TRUE/FALSE.",
      class = "paparazzi_error_input",
      call = call
    )
  }
  if (anyNA(value)) {
    cli::cli_abort(
      "{.arg value} can't be `NA`.",
      class = "paparazzi_error_input",
      call = call
    )
  }
  if (is.logical(value)) {
    list(kind = "checked", checked = value, text = "")
  } else {
    list(kind = "text", checked = FALSE, text = as.character(value))
  }
}

# The first element's own remote objectId. The caller releases the
# returned object; a detached element surfaces as the raw chromote
# error, like every other callFunctionOn.
els_first_object_id <- function(els, call = caller_env()) {
  timeout <- els$page$default_timeout
  res <- cdp_call(
    els$page$session$Runtime$callFunctionOn(
      "function() { return this[0]; }",
      objectId = els$object_id,
      returnByValue = FALSE,
      timeout_ = timeout
    ),
    timeout,
    paste("working with elements matching", els$description),
    call = call
  )
  res$result$objectId
}

# pz_set_value()'s whole element branch. The native prototype setters
# bypass instance-level value/checked overrides (what framework
# controlled inputs install), and the readback goes through the native
# getter for the same reason. Errors are statuses, not exceptions, so
# the R side wraps them in paparazzi_error_value.
set_value_js <- "function(value) {
  const el = this[0];
  if (el.isContentEditable) {
    if (value.kind !== 'text') {
      return {
        status: 'error',
        message: 'A contenteditable element takes a string, not TRUE/FALSE.'
      };
    }
    return { status: 'contenteditable' };
  }
  const isControl =
    el.tagName === 'SELECT' || el.tagName === 'INPUT' ||
    el.tagName === 'TEXTAREA';
  if (!isControl) {
    return {
      status: 'error',
      message: 'Target is a <' + el.tagName.toLowerCase() +
        '>, not a form control or contenteditable element.'
    };
  }
  if (el.tagName === 'INPUT' && el.type === 'file') {
    return {
      status: 'error',
      message: 'A file input takes files, not a value -- use pz_set_files().'
    };
  }
  el.focus();
  const dispatch = () => {
    el.dispatchEvent(new Event('input', { bubbles: true }));
    el.dispatchEvent(new Event('change', { bubbles: true }));
  };
  if (el.tagName === 'SELECT') {
    if (value.kind !== 'text') {
      return {
        status: 'error',
        message: 'A <select> takes an option value (a string), not TRUE/FALSE.'
      };
    }
    const has = Array.from(el.options).some((o) => o.value === value.text);
    if (!has) {
      return {
        status: 'error',
        message: 'No option with value \"' + value.text + '\".'
      };
    }
    Object.getOwnPropertyDescriptor(HTMLSelectElement.prototype, 'value')
      .set.call(el, value.text);
    dispatch();
    return { status: 'ok' };
  }
  const isCheckable = el.tagName === 'INPUT' &&
    (el.type === 'checkbox' || el.type === 'radio');
  if (isCheckable) {
    if (value.kind !== 'checked') {
      return {
        status: 'error',
        message: 'A ' + el.type + ' input takes TRUE or FALSE.'
      };
    }
    const setChecked = Object.getOwnPropertyDescriptor(
      HTMLInputElement.prototype,
      'checked'
    ).set;
    setChecked.call(el, value.checked);
    if (el.type === 'radio' && value.checked && el.name) {
      // The native checked setter doesn't maintain radio groups --
      // that's the browser's pre-click activation behavior -- so the
      // group is unchecked by hand. Per HTML a radio group is same
      // tree root AND same form owner AND same name: filtering by name
      // alone would uncheck same-name radios in other forms (relevant
      // once the element sits outside any form, where the candidates
      // come from the whole document), and candidates must come from
      // the root because a form attribute (form='...') associates a radio
      // with a form it isn't inside.
      const root = el.getRootNode();
      root.querySelectorAll('input[type=radio]').forEach((r) => {
        if (r !== el && r.name === el.name && r.form === el.form) {
          setChecked.call(r, false);
        }
      });
    }
    dispatch();
    return { status: 'ok' };
  }
  // Every other input type and textareas: the text path.
  if (value.kind !== 'text') {
    return {
      status: 'error',
      message: 'This ' + el.tagName.toLowerCase() +
        ' takes a string (or number), not TRUE/FALSE.'
    };
  }
  const proto = el.tagName === 'TEXTAREA'
    ? HTMLTextAreaElement.prototype
    : HTMLInputElement.prototype;
  const valueProp = Object.getOwnPropertyDescriptor(proto, 'value');
  // Capture the previous value before setting: if the browser rejects
  // or clamps the new one, restoring it keeps a failed set from
  // leaving the element mutated with no events fired.
  const previous = valueProp.get.call(el);
  valueProp.set.call(el, value.text);
  const kept = valueProp.get.call(el);
  if (kept !== value.text) {
    valueProp.set.call(el, previous);
    return {
      status: 'error',
      message: 'The element kept \"' + previous + '\" instead -- the browser ' +
        'rejected or clamped the value.'
    };
  }
  dispatch();
  return { status: 'ok' };
}"

# The contenteditable fallback's first half: focus the element and
# select all of its contents, so the insertText that follows replaces
# everything -- an insertText with an active selection, empty text
# included, deletes the selection.
select_all_js <- "function() {
  const el = this[0];
  el.focus();
  const range = document.createRange();
  range.selectNodeContents(el);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(range);
}"

# The exact-substring selection: a TreeWalker collects the target's
# text nodes, the concatenated data is searched, and one Range spans
# the start and end (node, offset) pair -- so a match crossing inline
# tags is a single selection. The Range becomes the window's only
# selection, the same state a mouse drag across the text produces.
select_text_js <- "function(text) {
  const el = this[0];
  const walker = document.createTreeWalker(el, NodeFilter.SHOW_TEXT);
  const nodes = [];
  let full = '';
  let node;
  while ((node = walker.nextNode())) {
    nodes.push({ node: node, start: full.length });
    full += node.data;
  }
  const idx = full.indexOf(text);
  if (idx === -1) {
    return { status: 'notfound' };
  }
  const end = idx + text.length;
  let startNode = null, startOffset = 0, endNode = null, endOffset = 0;
  for (const span of nodes) {
    const stop = span.start + span.node.data.length;
    if (startNode === null && idx < stop) {
      startNode = span.node;
      startOffset = idx - span.start;
    }
    if (end <= stop) {
      endNode = span.node;
      endOffset = end - span.start;
      break;
    }
  }
  const range = document.createRange();
  range.setStart(startNode, startOffset);
  range.setEnd(endNode, endOffset);
  const sel = window.getSelection();
  sel.removeAllRanges();
  sel.addRange(range);
  // A user dragging across editable text focuses it; that focus is
  // what lets typing replace the selection.
  if (el.isContentEditable) {
    el.focus();
  }
  return { status: 'ok' };
}"

# The by/to scroll, applied to the current scope's container: the scope
# element or its nearest scrollable ancestor (overflow auto|scroll
# plus actual overflow), falling back to the document. One function
# serves both rootings: callFunctionOn on the pinned set as `this`, or
# Runtime$evaluate with `this` an empty array (root -- the walk never
# starts, so the document wins). Application is instant JS, matching
# el_scroll_into_view()'s precedent; recording uses scroll_staged()
# for animated mouseWheel events.
scroll_apply_js <- "function(arg) {
  const isScrollable = (e) => {
    if (e === document.scrollingElement) {
      return true;
    }
    const s = getComputedStyle(e);
    if (!/(auto|scroll)/.test(s.overflow + ' ' + s.overflowX + ' ' + s.overflowY)) {
      return false;
    }
    return e.scrollHeight > e.clientHeight || e.scrollWidth > e.clientWidth;
  };
  let container = null;
  for (let e = this.length ? this[0] : null; e; e = e.parentElement) {
    if (isScrollable(e)) {
      container = e;
      break;
    }
  }
  if (!container) {
    container = document.scrollingElement;
  }
  if (arg.by) {
    container.scrollBy({
      left: arg.by[0],
      top: arg.by[1],
      behavior: 'instant'
    });
  } else {
    const has = (t) => arg.to.includes(t);
    const center = arg.to.length === 1 && arg.to[0] === 'center';
    if (has('left') || has('right') || center) {
      const max = container.scrollWidth - container.clientWidth;
      container.scrollLeft = center ? max / 2 : has('left') ? 0 : max;
    }
    if (has('top') || has('bottom') || center) {
      const max = container.scrollHeight - container.clientHeight;
      container.scrollTop = center ? max / 2 : has('top') ? 0 : max;
    }
  }
  return [container.scrollTop, container.scrollLeft];
}"

# The root-context scroll's call payload, inlined into the evaluated
# function call: callFunctionOn arguments aren't available to
# Runtime$evaluate, and the values are already validated (finite
# numbers by check_offset(), direction tokens by parse_direction()).
scroll_arg_json <- function(by = NULL, to = NULL) {
  if (!is.null(by)) {
    # as.double() first: a scalar integer offset (by = 100L) survives
    # check_offset() as an integer, and deparse(100L) is "100L" -- not
    # a JavaScript number. deparse() of a double is a valid JSON
    # number for every finite value (the only ones check_offset()
    # allows through).
    by <- as.double(by)
    paste0('{"by":[', deparse(by[[1]]), ',', deparse(by[[2]]), ']}')
  } else {
    paste0('{"to":[', paste(paste0('"', to, '"'), collapse = ","), ']}')
  }
}

# The destination's final point after the source settles: visibility,
# box, viewport, and the receiver at the box center.
dest_point_js <- paste0(
  "function() {\n",
  pointer_hit_test_js,
  "
  const el = this[0];
  const r = el.getBoundingClientRect();
  const visible = el.checkVisibility({ checkVisibilityCSS: true });
  return {
    visible, x: r.x, y: r.y, width: r.width, height: r.height,
    viewportWidth: window.innerWidth, viewportHeight: window.innerHeight,
    blocker: visible && r.width > 0 && r.height > 0
      ? pointerHitTest(el, r.x + r.width / 2, r.y + r.height / 2)
      : null
  };
}"
)

# Is the source a real HTML5 drag source? Own or inherited draggable
# attribute (the IDL property only reflects the element's own
# attribute, so inheritance needs the closest() walk; an explicit
# false opts out; the attribute keywords are case-insensitive), or the
# img / <a href> element defaults.
draggable_js <- "function() {
  const el = this[0];
  const own = el.getAttribute('draggable');
  if (own !== null && own !== '') {
    return own.toLowerCase() === 'true';
  }
  const inherited = el.closest('[draggable]');
  if (inherited) {
    return inherited.getAttribute('draggable').toLowerCase() === 'true';
  }
  return el.tagName === 'IMG' ||
    (el.tagName === 'A' && el.hasAttribute('href'));
}"

# The mouse drag: press at the source, one move to the destination,
# release. While recording with a visible cursor the press scale-down
# plays at the source and the cursor glides while holding BEFORE the
# move, so pointer-following pages react as the cursor arrives; without
# a recording everything runs straight through. A dispatch error between
# press and release leaves the button held, so the release is
# re-attempted on exit until the normal path completes it.
dispatch_mouse_drag <- function(
  ctx,
  action,
  target,
  from,
  to,
  call = caller_env()
) {
  staged <- stage_recording(ctx$page) && cursor_visible(ctx$page)
  pressed <- FALSE
  withr::defer(
    if (pressed) {
      try(
        dispatch_mouse(
          ctx,
          action,
          target,
          "mouseReleased",
          to,
          button = "left",
          buttons = 0,
          clickCount = 1,
          call = call
        ),
        silent = TRUE
      )
    }
  )
  dispatch_mouse(
    ctx,
    action,
    target,
    "mouseMoved",
    from,
    button = "none",
    buttons = 0,
    clickCount = 0,
    call = call
  )
  if (staged) {
    pump_loop(ctx$page$child_loop, 0.15)
    cursor_press(ctx, TRUE)
    pump_loop(ctx$page$child_loop, 0.16)
  }
  dispatch_mouse(
    ctx,
    action,
    target,
    "mousePressed",
    from,
    button = "left",
    buttons = 1,
    clickCount = 1,
    call = call
  )
  pressed <- TRUE
  if (staged) {
    cursor_show_at(ctx, to, pressed = TRUE)
  }
  dispatch_mouse(
    ctx,
    action,
    target,
    "mouseMoved",
    to,
    button = "left",
    buttons = 1,
    clickCount = 0,
    call = call
  )
  dispatch_mouse(
    ctx,
    action,
    target,
    "mouseReleased",
    to,
    button = "left",
    buttons = 0,
    clickCount = 1,
    call = call
  )
  pressed <- FALSE
  if (staged) {
    cursor_press(ctx, FALSE)
    pump_loop(ctx$page$child_loop, 0.2)
  }
}

# HTML5 drag-and-drop, intercept-then-replay. With interception on, the
# press-and-move starts a REAL drag (the page's dragstart runs), and the
# browser reports the resulting drag data -- what the page put on its
# dataTransfer -- as an Input.dragIntercepted event. The event callback
# must be registered first (the registration auto-enables the Input
# domain); the event arrives on chromote's child loop, so the wait is the
# standard pz_poll. Interception goes OFF before the release -- releasing
# with it still on cancels the drag and the replayed events never land --
# then the captured data is replayed onto the destination as
# dragEnter/dragOver/drop: trusted DnD events with the real payload.
# While recording with a visible cursor, the carry is staged between the
# intercepted dragstart and the replayed drop: the drag stays held
# (interception still on, button still down, nothing dispatched) while
# the cursor glides to the drop point, so the page's dragstart styling
# shows through the carry and the drop lands as the cursor arrives.
drag_html5 <- function(ctx, els, from, to, call = caller_env()) {
  session <- ctx$page$session
  timeout <- ctx$page$default_timeout
  staged <- stage_recording(ctx$page) && cursor_visible(ctx$page)
  data <- NULL
  dereg <- session$Input$dragIntercepted(
    callback_ = function(msg) data <<- msg$data
  )
  withr::defer(try(dereg(), silent = TRUE))

  settled <- FALSE
  # Any exit before the release leaves the button held and interception
  # on -- a CDP error mid-sequence, or a dragstart the page cancels (the
  # interception event never fires, so the poll times out). Both are
  # undone here; the latch drops once the normal path has released.
  withr::defer(
    if (!settled) {
      try(
        session$Input$setInterceptDrags(enabled = FALSE, timeout_ = timeout),
        silent = TRUE
      )
      try(
        dispatch_mouse(
          ctx,
          "dragging",
          els$description,
          "mouseReleased",
          to,
          button = "left",
          buttons = 0,
          clickCount = 1,
          call = call
        ),
        silent = TRUE
      )
    }
  )

  action_cdp(
    ctx,
    "dragging",
    els$description,
    call = call,
    cmd = session$Input$setInterceptDrags(enabled = TRUE, timeout_ = timeout)
  )
  dispatch_mouse(
    ctx,
    "dragging",
    els$description,
    "mouseMoved",
    from,
    button = "none",
    buttons = 0,
    clickCount = 0,
    call = call
  )
  if (staged) {
    pump_loop(ctx$page$child_loop, 0.15)
    cursor_press(ctx, TRUE)
    pump_loop(ctx$page$child_loop, 0.16)
  }
  dispatch_mouse(
    ctx,
    "dragging",
    els$description,
    "mousePressed",
    from,
    button = "left",
    buttons = 1,
    clickCount = 1,
    call = call
  )
  dispatch_mouse(
    ctx,
    "dragging",
    els$description,
    "mouseMoved",
    to,
    button = "left",
    buttons = 1,
    clickCount = 0,
    call = call
  )
  pz_poll(
    fn = function() !is.null(data),
    timeout = timeout,
    loop = ctx$page$child_loop,
    what = paste0("the drag from ", els$description, " to start"),
    call = call
  )

  if (staged) {
    cursor_show_at(ctx, to, pressed = TRUE)
  }
  action_cdp(
    ctx,
    "dragging",
    els$description,
    call = call,
    cmd = session$Input$setInterceptDrags(enabled = FALSE, timeout_ = timeout)
  )
  dispatch_mouse(
    ctx,
    "dragging",
    els$description,
    "mouseReleased",
    to,
    button = "left",
    buttons = 0,
    clickCount = 1,
    call = call
  )
  settled <- TRUE
  for (type in c("dragEnter", "dragOver", "drop")) {
    action_cdp(
      ctx,
      "dragging",
      els$description,
      call = call,
      cmd = session$Input$dispatchDragEvent(
        type = type,
        x = to[["x"]],
        y = to[["y"]],
        data = data,
        timeout_ = timeout
      )
    )
  }
  if (staged) {
    cursor_press(ctx, FALSE)
    pump_loop(ctx$page$child_loop, 0.2)
  }
}

# pz_set_files()'s `files`: paths to existing local files, normalized
# to the absolute paths the browser reads.
check_file_paths <- function(files, call = caller_env()) {
  check_character(files, call = call)
  missing <- files[!file.exists(files)]
  if (length(missing) > 0L) {
    cli::cli_abort(
      "File{?s} {.file {missing}} {?doesn't/don't} exist.",
      class = "paparazzi_error_input",
      call = call
    )
  }
  dirs <- files[dir.exists(files)]
  if (length(dirs) > 0L) {
    cli::cli_abort(
      "Path{?s} {.file {dirs}} {?is a directory/are directories}, not {?a file/files}.",
      class = "paparazzi_error_input",
      call = call
    )
  }
  unname(normalizePath(files, winslash = "/", mustWork = TRUE))
}
