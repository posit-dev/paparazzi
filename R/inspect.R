#' @include overlay.R
NULL

#' Inspect the current page state
#'
#' @description
#' Prints a console summary of the page: URL, device, recording and cursor
#' state, and -- when `target` is given -- the target's matches resolved
#' relative to the current scope **without** auto-waiting: a single
#' resolution pass, each match shown as a short opening tag with its
#' visibility, enabled state, and box (long lists are truncated).
#'
#' The header names the context. At the root it reads `paparazzi page`.
#' In a scoped context from [pz_find()] it reads `paparazzi scope`, with
#' the scope stack right under it: live match counts for each level,
#' plus a warning when pinned elements have gone stale.
#'
#' `show = "screenshot"` additionally captures an annotated screenshot:
#' dashed outlines over the scope's elements, solid numbered outlines over
#' the target's matches, drawn under paparazzi's shadow-root overlay, so
#' they never appear in [pz_screenshot()] output. `show = "browser"` draws
#' the same outlines in the live page, leaves them, and opens the browser
#' via the page's `$view()`. `show = "auto"` picks `"screenshot"` in
#' interactive sessions and `"none"` otherwise.
#'
#' @inheritParams pz_act_click
#' @param target A CSS selector string, a [pz_loc()] spec, or a list of
#'   specs and strings (a union matching any of them). `NULL` (default)
#'   omits the target section.
#' @param path Where to write the annotated screenshot; `NULL` writes a
#'   temporary file. Only used with `show = "screenshot"`.
#' @param show How to visualize: `"auto"`, `"screenshot"` (annotated
#'   capture), `"browser"` (outlines left in the live page), or `"none"`.
#'
#' @return `ctx`, invisibly, so it can be dropped anywhere in a chain.
#' @examplesIf paparazzi:::examples_run(site = TRUE)
#' page <- pz_open(pz_example("tasks"))
#' page |> pz_inspect()
#'
#' # With a target: its matches, resolved inside the current scope
#' page |>
#'   pz_find(".task-list") |>
#'   pz_inspect(".task.done", show = "none")
#'
#' # An annotated screenshot outlines the scope and the numbered matches
#' page |>
#'   pz_find(".task-list") |>
#'   pz_inspect(".task-done", show = "screenshot", path = file.path(tempdir(), "inspect.png"))
#' pz_close(page)
#'
#' @export
pz_inspect <- function(
  ctx,
  target = NULL,
  ...,
  path = NULL,
  show = c("auto", "screenshot", "browser", "none")
) {
  check_context(ctx)
  check_dots_empty()
  show <- arg_match(show)
  if (identical(show, "auto")) {
    show <- if (interactive()) "screenshot" else "none"
  }
  check_string(path, allow_null = TRUE)
  if (!is.null(path) && !identical(show, "screenshot")) {
    cli::cli_abort(
      "{.arg path} is only used with {.code show = \"screenshot\"}.",
      class = "paparazzi_error_input"
    )
  }

  matches <- if (is.null(target)) NULL else inspect_resolve_matches(ctx, target)
  inspect_summary_print(ctx, matches)

  if (identical(show, "screenshot") || identical(show, "browser")) {
    scope_rects <- inspect_scope_rects(ctx)
    target_rects <- if (is.null(matches)) NULL else matches$rects
    overlay_draw(ctx, scope_rects, target_rects)
    if (identical(show, "browser")) {
      ctx$page$view()
    } else {
      withr::defer(try(overlay_clear(ctx), silent = TRUE))
      path <- path %||% tempfile(fileext = ".png")
      inspect_annotated_capture(ctx, scope_rects, target_rects, path)
      inspect_show(path)
    }
  }

  ctx_return(ctx)
}

inspect_resolve_matches <- function(ctx, target, call = caller_env()) {
  target_expr <- target_resolver(target, call = call)
  els <- loc_resolve_once(
    ctx,
    target_expr$fn,
    target_expr$description,
    call = call,
    root = scope_connected(ctx, call = call)
  )
  withr::defer(release_elements(els))

  rows <- list()
  rects <- tibble::tibble(
    x = numeric(),
    y = numeric(),
    width = numeric(),
    height = numeric()
  )
  if (els$count > 0L) {
    raw <- els_values(els, inspect_match_js, call = call)
    rows <- lapply(raw, function(v) {
      list(
        tag = v[[1]],
        visible = isTRUE(v[[2]]),
        enabled = isTRUE(v[[3]]),
        x = as.numeric(v[[4]]),
        y = as.numeric(v[[5]]),
        width = as.numeric(v[[6]]),
        height = as.numeric(v[[7]])
      )
    })
    rects <- tibble::tibble(
      x = map_dbl(rows, function(r) r$x),
      y = map_dbl(rows, function(r) r$y),
      width = map_dbl(rows, function(r) r$width),
      height = map_dbl(rows, function(r) r$height)
    )
  }

  list(
    description = target_expr$description,
    count = els$count,
    rows = rows,
    rects = rects
  )
}

# :disabled also covers controls disabled by an ancestor <fieldset disabled>.
inspect_match_js <- "function() {
  return this.map((el) => {
    const attrs = Array.from(el.attributes, (a) =>
      a.value === '' ? a.name : a.name + '=\"' + a.value + '\"'
    ).join(' ');
    const tag = '<' + el.tagName.toLowerCase() + (attrs ? ' ' + attrs : '') + '>';
    const r = el.getBoundingClientRect();
    return [
      tag,
      el.checkVisibility({ checkVisibilityCSS: true }),
      !el.matches(':disabled'),
      r.x, r.y, r.width, r.height
    ];
  });
}"

inspect_doc_rects <- function(ctx, rects) {
  if (nrow(rects) == 0L) {
    return(list())
  }
  scroll <- page_scroll(ctx)
  lapply(seq_len(nrow(rects)), function(i) {
    as.numeric(rects[i, ]) + c(scroll[[1]], scroll[[2]], 0, 0)
  })
}

inspect_scope_rects <- function(ctx) {
  scoped <- scope_top(ctx)
  if (is.null(scoped) || is.null(scoped$object_id)) {
    return(inspect_positive_rects(NULL))
  }
  inspect_positive_rects(tryCatch(el_rects(scoped), error = function(e) NULL))
}

inspect_positive_rects <- function(rects) {
  if (is.null(rects) || nrow(rects) == 0L) {
    return(tibble::tibble(
      x = numeric(),
      y = numeric(),
      width = numeric(),
      height = numeric()
    ))
  }
  rects[rects$width > 0 & rects$height > 0, ]
}

inspect_recording_state <- function(page) {
  rec <- page_recorder(page)
  recording <- if (is.null(rec) || !isTRUE(rec$active)) {
    "off"
  } else if (isTRUE(rec$paused)) {
    "paused"
  } else {
    "on"
  }
  cur <- page_cursor_peek(page)
  cursor <- if (is.null(cur) || !cursor_visible(page)) {
    "hidden"
  } else if (!is.null(cur$off_frame)) {
    "off-frame"
  } else if (isTRUE(cur$resting)) {
    "resting"
  } else {
    "visible"
  }
  list(recording = recording, cursor = cursor)
}

# The summary is composed as plain strings and emitted with cat_line():
# scope and target descriptions carry user-derived selectors whose braces
# would break cli templates, so page-derived content interpolates as
# values, never templates.
inspect_header <- function(label = "page") {
  width <- getOption("width", 80L)
  prefix <- paste0("\u2500\u2500 paparazzi ", label, " ")
  paste0(prefix, strrep("\u2500", max(1, as.integer(width) - nchar(prefix))))
}

inspect_summary_print <- function(ctx, matches = NULL) {
  scoped <- length(ctx$scope) > 0L
  if (ctx$page$is_closed()) {
    cli::cat_line(
      if (scoped) {
        "<paparazzi scope> (page closed)"
      } else {
        "<paparazzi page> (closed)"
      }
    )
    return(invisible(NULL))
  }
  view <- pz_js(
    ctx,
    "({href: location.href, width: window.innerWidth, height: window.innerHeight, dpr: window.devicePixelRatio, dark: matchMedia('(prefers-color-scheme: dark)').matches})"
  )
  scheme <- if (isTRUE(view$dark)) "dark" else "light"
  scale <- if (abs(view$dpr - round(view$dpr)) < 1e-9) {
    sprintf("%gx", as.integer(view$dpr))
  } else {
    paste0(view$dpr, "x")
  }
  rec <- inspect_recording_state(ctx$page)

  cli::cat_line(inspect_header(if (scoped) "scope" else "page"))
  if (scoped) {
    scope <- inspect_scope_entries(ctx)
    cli::cat_line(sprintf(
      "%-11s%s",
      "Scope",
      paste(c("root", scope$entries), collapse = " \u203a ")
    ))
    for (msg in scope$warnings) {
      cli::cli_inform(c("!" = "{msg}"), msg = msg)
    }
  }
  cli::cat_line(sprintf("%-11s%s", "URL", view$href))
  cli::cat_line(sprintf(
    "%-11s%s \u00d7 %s @%s \u00b7 %s",
    "Device",
    view$width,
    view$height,
    scale,
    scheme
  ))

  if (!is.null(matches)) {
    inspect_target_print(matches)
  }

  cli::cat_line(sprintf(
    "%-11s%s \u00b7 cursor %s",
    "Recording",
    rec$recording,
    rec$cursor
  ))
  invisible(NULL)
}

inspect_scope_entries <- function(ctx) {
  entries <- character()
  warnings <- character()
  for (pinned in ctx$scope) {
    desc <- format_scope_entry(pinned$description)
    state <- inspect_scope_live(pinned)
    if (state$gone) {
      entries <- c(entries, paste0(desc, " (gone)"))
      warnings <- c(
        warnings,
        paste0(
          "The scope ",
          desc,
          " no longer resolves; its pinned elements are gone ",
          "(probably after a navigation)."
        )
      )
    } else if (state$live < pinned$count) {
      entries <- c(
        entries,
        paste0(desc, " (", state$live, " of ", pinned$count, ")")
      )
      warnings <- c(
        warnings,
        paste0(
          pinned$count - state$live,
          if (pinned$count - state$live == 1L) " element" else " elements",
          " in the scope ",
          desc,
          " ",
          if (pinned$count - state$live == 1L) "is" else " are",
          " no longer in the page (probably re-rendered)."
        )
      )
    } else {
      entries <- c(entries, paste0(desc, " (", state$live, ")"))
    }
  }
  list(entries = entries, warnings = warnings)
}

inspect_scope_live <- function(pinned) {
  if (is.null(pinned$object_id)) {
    return(list(gone = TRUE, live = NA_integer_))
  }
  tryCatch(
    {
      res <- pinned$page$session$Runtime$callFunctionOn(
        "function() { return this.filter((el) => el && el.isConnected).length; }",
        objectId = pinned$object_id,
        returnByValue = TRUE,
        timeout_ = pinned$page$default_timeout
      )
      if (!is.null(res$exceptionDetails)) {
        list(gone = TRUE, live = NA_integer_)
      } else {
        list(gone = FALSE, live = as.integer(res$result$value))
      }
    },
    error = function(e) list(gone = TRUE, live = NA_integer_)
  )
}

format_scope_entry <- function(description) {
  description <- sub(" \\(which: first\\)$", " first", description)
  description <- sub(" \\(which: last\\)$", " last", description)
  sub(" \\(which: ([0-9]+)\\)$", " #\\1", description)
}

inspect_target_print <- function(matches) {
  phrase <- if (matches$count == 0L) {
    "no matches"
  } else if (matches$count == 1L) {
    "1 match"
  } else {
    paste0(matches$count, " matches")
  }
  cli::cat_line(sprintf(
    "%-11s%s \u2192 %s",
    "Target",
    matches$description,
    phrase
  ))
  shown <- utils::head(matches$rows, 10)
  for (i in seq_along(shown)) {
    row <- shown[[i]]
    visible <- if (row$visible) "visible" else "hidden"
    enabled <- if (row$enabled) "enabled" else "disabled"
    cli::cat_line(sprintf("  %d  %s", i, inspect_short_tag(row$tag)))
    cli::cat_line(sprintf(
      "     %s \u00b7 %s \u00b7 at %.0f,%.0f \u00b7 %.0f \u00d7 %.0f",
      visible,
      enabled,
      row$x,
      row$y,
      row$width,
      row$height
    ))
  }
  if (matches$count > length(shown)) {
    cli::cat_line(sprintf(
      "     \u2026 and %d more",
      matches$count - length(shown)
    ))
  }
  invisible(NULL)
}

inspect_short_tag <- function(tag, width = 60) {
  if (nchar(tag) <= width) {
    tag
  } else {
    paste0(substr(tag, 1, width - 1), "\u2026")
  }
}

overlay_draw <- function(ctx, scope_rects, target_rects) {
  keep <- if (is.null(target_rects)) {
    integer()
  } else {
    which(target_rects$width > 0 & target_rects$height > 0)
  }
  targets <- if (length(keep) == 0L) {
    list()
  } else {
    rects <- inspect_doc_rects(ctx, target_rects[keep, , drop = FALSE])
    Map(function(rect, n) c(rect, n), rects, keep)
  }
  data <- jsonlite::toJSON(list(
    scope = if (is.null(scope_rects)) {
      list()
    } else {
      inspect_doc_rects(ctx, inspect_positive_rects(scope_rects))
    },
    targets = targets
  ))
  pz_js(ctx, paste0("(", overlay_draw_js, ")(", data, ")"), await = FALSE)
  invisible(TRUE)
}

overlay_draw_js <- paste0(
  "function(data) {",
  OVERLAY_HOST_JS,
  "  root.querySelectorAll('.pz-inspect').forEach((n) => n.remove());
  const layer = document.createElement('div');
  layer.className = 'pz-inspect';
  const box = (r, style) => {
    const d = document.createElement('div');
    d.style.cssText = style +
      'position:absolute;box-sizing:border-box;pointer-events:none;' +
      'left:' + r[0] + 'px;top:' + r[1] + 'px;width:' + r[2] + 'px;height:' + r[3] + 'px;';
    layer.appendChild(d);
  };
  for (const r of data.scope) {
    box(r, 'border:2px dashed #f59e0b;');
  }
  data.targets.forEach((r) => {
    box(r, 'border:2px solid #e11d48;');
    const b = document.createElement('div');
    b.textContent = String(r[4]);
    b.style.cssText = 'position:absolute;box-sizing:border-box;pointer-events:none;' +
      'left:' + r[0] + 'px;top:' + Math.max(r[1] - 20, 0) + 'px;min-width:20px;height:20px;' +
      'padding:0 5px;background:#e11d48;color:#fff;font:600 12px/20px monospace;text-align:center;border-radius:4px;';
    layer.appendChild(b);
  });
  root.appendChild(layer);
  return true;
}"
)

overlay_clear <- function(ctx) {
  pz_js(
    ctx,
    paste0(
      "(() => { const h = document.getElementById('",
      OVERLAY_HOST_ID,
      "'); ",
      "if (h && h.shadowRoot) h.shadowRoot.querySelectorAll('.pz-inspect').forEach((n) => n.remove()); ",
      "return true; })()"
    ),
    await = FALSE
  )
  invisible(TRUE)
}

inspect_outlines_hide <- function(ctx) {
  pz_js(
    ctx,
    paste0(
      "(() => { const h = document.getElementById('",
      OVERLAY_HOST_ID,
      "'); ",
      "if (!h || !h.shadowRoot) return null; ",
      "const layers = h.shadowRoot.querySelectorAll('.pz-inspect'); ",
      "if (!layers.length) return null; ",
      "const prev = []; ",
      "layers.forEach((n) => { prev.push(n.style.display); n.style.display = 'none'; }); ",
      "return prev; })()"
    ),
    await = FALSE
  )
}

inspect_outlines_restore <- function(ctx, display) {
  if (is.null(display)) {
    return(invisible(NULL))
  }
  values <- jsonlite::toJSON(as.character(unlist(display)))
  pz_js(
    ctx,
    paste0(
      "(() => { const h = document.getElementById('",
      OVERLAY_HOST_ID,
      "'); ",
      "if (!h || !h.shadowRoot) return; ",
      "const prev = ",
      values,
      "; ",
      "h.shadowRoot.querySelectorAll('.pz-inspect').forEach((n, i) => { n.style.display = prev[i]; }); ",
      "})()"
    ),
    await = FALSE
  )
  invisible(TRUE)
}

inspect_annotated_capture <- function(ctx, scope_rects, target_rects, path) {
  rects <- rbind(
    inspect_positive_rects(scope_rects),
    inspect_positive_rects(target_rects)
  )
  clip <- if (nrow(rects) == 0L) {
    clip_viewport(ctx)
  } else {
    pad <- 16
    clip_rects_union(
      ctx,
      tibble::tibble(
        x = rects$x - pad,
        y = rects$y - pad,
        width = rects$width + 2 * pad,
        height = rects$height + 2 * pad
      )
    )
  }
  res <- screenshot_capture(ctx, clip)
  writeBin(jsonlite::base64_dec(res$data), path)
  invisible(path)
}

inspect_show <- function(path) {
  viewer <- getOption("viewer")
  if (rlang::is_interactive() && is.function(viewer)) {
    try(viewer(preview_stage(path)), silent = TRUE)
  }
  cli::cli_inform("Annotated screenshot: {.file {path}}")
  invisible(path)
}
