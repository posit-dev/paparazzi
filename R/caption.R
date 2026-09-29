#' Add a screen-space caption
#'
#' A caption stays on the page until replaced or cleared with
#' [pz_annotate_clear(id = "caption")][pz_annotate_clear()]. It persists
#' through navigation and across recordings, and appears on stills.
#'
#' @inheritParams pz_click
#' @param text Nonempty caption text. Newlines are preserved.
#' @param ... Checked empty.
#' @param side `"bottom"` (the default) or `"top"`.
#' @param color Text color. `NULL` always uses white, not the
#'   `annotate_color` mark accent in [pz_stage()].
#' @param font_family CSS font family. `NULL` uses the page's
#'   `annotate_font_family` setting in [pz_stage()] (initially sans-serif).
#' @param font_size Font size in CSS pixels. `NULL` uses 20, independent
#'   of the annotation badge size. Captions scale with the output.
#' @return `ctx`, invisibly.
#' @seealso [pz_annotate_clear()], [pz_record_start()], [pz_screenshot()]
#' @export
pz_annotate_caption <- function(
  ctx,
  text,
  ...,
  side = "bottom",
  color = NULL,
  font_family = NULL,
  font_size = NULL
) {
  check_context(ctx)
  check_dots_empty()
  check_string(text)
  if (!nzchar(text)) {
    cli::cli_abort("{.arg text} must be nonempty.")
  }
  side <- arg_match(side, c("bottom", "top"))
  color <- color %||% "white"
  font_family <- font_family %||% page_stage(ctx$page)$annotate_font_family
  font_size <- font_size %||% 20
  check_string(color)
  check_string(font_family)
  check_number_decimal(font_size, min = 0, allow_infinite = FALSE)
  if (!nzchar(color) || !nzchar(font_family) || font_size == 0) {
    cli::cli_abort("Caption style values must be nonempty and positive.")
  }
  rec <- page_recorder(ctx$page)
  if (!is.null(rec) && rec$active && rec$format == "gif") {
    rlang::check_installed(
      "av",
      reason = "to burn captions onto .gif recordings."
    )
  }
  page_set_caption(
    ctx$page,
    list(
      text = text,
      side = side,
      color = color,
      font_family = font_family,
      font_size = font_size
    )
  )
  invisible(ctx)
}

page_caption <- function(page) {
  page$.__enclos_env__$private$staging_$caption
}

page_set_caption <- function(page, caption) {
  page$.__enclos_env__$private$staging_$caption <- caption
  rec <- page_recorder(page)
  if (!is.null(rec) && rec$active) {
    rec$captions <- c(
      rec$captions,
      list(list(vt = rec_vt(rec), caption = caption))
    )
  }
  invisible(page)
}

caption_clear <- function(page) {
  if (!is.null(page_caption(page))) {
    page_set_caption(page, NULL)
  }
  invisible(page)
}

caption_render <- function(page, caption, width, height, font_scale, path) {
  session <- page$session$new_session()
  on.exit(session$close(), add = TRUE)
  session$Emulation$setDeviceMetricsOverride(
    width = as.integer(width),
    height = as.integer(height),
    deviceScaleFactor = 1,
    mobile = FALSE
  )
  session$Emulation$setDefaultBackgroundColorOverride(
    color = list(r = 0, g = 0, b = 0, a = 0)
  )
  data <- jsonlite::toJSON(
    list(
      text = caption$text,
      side = caption$side,
      color = caption$color,
      family = caption$font_family,
      size = caption$font_size * font_scale,
      padding = 9 * font_scale,
      offset = 24 * font_scale
    ),
    auto_unbox = TRUE
  )
  script <- paste0(
    "(() => { const c = ",
    data,
    "; ",
    "document.documentElement.style.cssText='background:transparent;margin:0';",
    "document.body.style.cssText='background:transparent;margin:0';",
    "const el=document.createElement('div'); el.textContent=c.text;",
    "Object.assign(el.style,{position:'fixed',left:'50%',",
    "[c.side]:c.offset+'px', transform:'translateX(-50%)',",
    "maxWidth:'80vw',boxSizing:'border-box',whiteSpace:'pre-wrap',",
    "overflowWrap:'anywhere',textAlign:'center',borderRadius:'12px',",
    "padding:c.padding+'px '+(c.padding*1.5)+'px',",
    "background:'rgba(0,0,0,0.72)',color:c.color,",
    "fontFamily:c.family,fontSize:c.size+'px',lineHeight:'1.35'});",
    "document.body.appendChild(el); return el.getBoundingClientRect().height; })()"
  )
  session$Runtime$evaluate(expression = script, returnByValue = TRUE)
  result <- session$Page$captureScreenshot(
    format = "png",
    fromSurface = TRUE,
    captureBeyondViewport = TRUE,
    clip = list(x = 0, y = 0, width = width, height = height, scale = 1)
  )
  writeBin(jsonlite::base64_dec(result$data), path)
  invisible(path)
}

caption_blend_still <- function(path, overlay) {
  base <- png::readPNG(path)
  top <- png::readPNG(overlay)
  top_alpha <- matrix(top[,, 4, drop = FALSE], nrow = dim(top)[1])
  rows <- which(rowSums(top_alpha > 0) > 0)
  if (!length(rows)) {
    return(invisible(path))
  }
  rows <- seq.int(min(rows), max(rows))
  alpha <- top_alpha[rows, , drop = FALSE]
  base_alpha <- if (dim(base)[3] == 4) {
    matrix(base[rows, , 4, drop = FALSE], nrow = length(rows))
  } else {
    matrix(1, nrow = length(rows), ncol = dim(base)[2])
  }
  out_alpha <- alpha + base_alpha * (1 - alpha)
  for (channel in 1:3) {
    bottom <- matrix(base[rows, , channel, drop = FALSE], nrow = length(rows))
    above <- matrix(top[rows, , channel, drop = FALSE], nrow = length(rows))
    base[rows, , channel] <- ifelse(
      out_alpha > 0,
      (above * alpha + bottom * base_alpha * (1 - alpha)) / out_alpha,
      0
    )
  }
  if (dim(base)[3] == 4) {
    base[rows, , 4] <- out_alpha
  }
  png::writePNG(base, path)
  invisible(path)
}

caption_windows <- function(rec, sampled) {
  events <- rec$captions
  if (!length(events)) {
    return(list())
  }
  vts <- sampled$vts
  active <- vapply(
    vts,
    function(vt) {
      matches <- which(vapply(
        events,
        function(event) event$vt <= vt + 1e-9,
        logical(1)
      ))
      if (length(matches)) tail(matches, 1L) else 0L
    },
    integer(1)
  )
  runs <- rle(active)
  starts <- cumsum(c(1L, head(runs$lengths, -1L)))
  windows <- lapply(which(runs$values > 0), function(i) {
    index <- runs$values[[i]]
    list(
      start = (starts[[i]] - 1) / rec$fps,
      end = (starts[[i]] + runs$lengths[[i]] - 1) / rec$fps,
      caption = events[[index]]$caption
    )
  }) |>
    Filter(f = function(window) !is.null(window$caption))
  merged <- list()
  for (window in windows) {
    last <- length(merged)
    if (
      last &&
        identical(merged[[last]]$caption, window$caption) &&
        merged[[last]]$end == window$start
    ) {
      merged[[last]]$end <- window$end
    } else {
      merged <- c(merged, list(window))
    }
  }
  merged
}

caption_vtt <- function(rec, windows) {
  path <- paste0(tools::file_path_sans_ext(rec$path), ".vtt")
  time <- function(seconds) {
    ms <- as.integer(round(seconds * 1000))
    sprintf(
      "%02d:%02d:%02d.%03d",
      ms %/% 3600000,
      (ms %/% 60000) %% 60,
      (ms %/% 1000) %% 60,
      ms %% 1000
    )
  }
  cues <- unlist(lapply(windows, function(window) {
    text <- gsub("&", "&amp;", window$caption$text, fixed = TRUE)
    text <- gsub("<", "&lt;", text, fixed = TRUE)
    text <- gsub(">", "&gt;", text, fixed = TRUE)
    text <- gsub("\n(?:[ \t]*\n)+", "\n", text, perl = TRUE)
    c(paste0(time(window$start), " --> ", time(window$end)), text, "")
  }))
  writeLines(c("WEBVTT", "", cues), path, useBytes = TRUE)
  invisible(path)
}

caption_filter <- function(rec, page, sampled, out, windows, dir) {
  base <- out$vfilter
  chains <- paste0("[in]", base, "[b0]")
  home_width <- if (is.null(rec$crop)) {
    pz_js(page, "window.innerWidth")
  } else {
    rec$crop$width
  }
  scale <- out$width / home_width
  for (i in seq_along(windows)) {
    window <- windows[[i]]
    file <- file.path(dir, paste0("caption-", i, ".png"))
    caption_render(page, window$caption, out$width, out$height, scale, file)
    fade <- min(0.25, (window$end - window$start) / 2)
    # Movie sources are bare filenames; with_dir() owns their lookup directory.
    # A caption at tick zero is already visible, not fading in.
    movie <- paste0(
      "movie=caption-",
      i,
      ".png:loop=1,format=rgba,",
      "loop=",
      sampled$n_ticks,
      ":size=1:start=0,",
      "setpts=N/(",
      rec$fps,
      "*TB)",
      if (window$start == 0) {
        ""
      } else {
        paste0(
          ",fade=t=in:st=",
          sprintf("%.6f", window$start),
          ":d=",
          sprintf("%.6f", fade),
          ":alpha=1"
        )
      },
      ",fade=t=out:st=",
      sprintf("%.6f", window$end - fade),
      ":d=",
      sprintf("%.6f", fade),
      ":alpha=1[c",
      i,
      "]"
    )
    output <- if (i == length(windows)) "" else paste0("[b", i, "]")
    overlay <- paste0(
      "[b",
      i - 1L,
      "][c",
      i,
      "]overlay=0:0:enable='between(t,",
      sprintf("%.6f", window$start),
      ",",
      sprintf("%.6f", window$end - 0.000001),
      ")'",
      output
    )
    chains <- c(chains, movie, overlay)
  }
  format <- if (identical(rec$format, "gif")) "rgb24" else "yuv420p"
  chains[[length(chains)]] <- paste0(
    chains[[length(chains)]],
    ",format=",
    format
  )
  paste(chains, collapse = ";")
}
