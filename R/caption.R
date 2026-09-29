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
  screen_render(page, width, height, path, script)
}

screen_render <- function(page, width, height, path, script) {
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
  geometry <- session$Runtime$evaluate(
    expression = script,
    returnByValue = TRUE
  )
  result <- session$Page$captureScreenshot(
    format = "png",
    fromSurface = TRUE,
    captureBeyondViewport = TRUE,
    clip = list(x = 0, y = 0, width = width, height = height, scale = 1)
  )
  writeBin(jsonlite::base64_dec(result$data), path)
  invisible(geometry$result$value)
}

key_callout_render <- function(
  page,
  groups,
  width,
  height,
  scale,
  bottom_offset,
  path
) {
  data <- jsonlite::toJSON(
    list(
      groups = lapply(groups, as.list),
      scale = scale,
      bottom = bottom_offset
    ),
    auto_unbox = TRUE
  )
  script <- paste0(
    "(() => { const c=",
    data,
    ";",
    "document.documentElement.style.cssText='background:transparent;margin:0';",
    "document.body.style.cssText='background:transparent;margin:0';",
    "const row=document.createElement('div');",
    "Object.assign(row.style,{position:'fixed',left:'50%',bottom:c.bottom+'px',",
    "transform:'translateX(-50%)',display:'flex',flexWrap:'wrap',",
    "alignItems:'center',justifyContent:'center',maxWidth:'80vw',",
    "gap:(6*c.scale)+'px',fontFamily:'sans-serif',",
    "fontSize:(18*c.scale)+'px',color:'white'});",
    "c.groups.forEach((group,i)=>{",
    "if(i){const arrow=document.createElement('span');arrow.textContent='→';",
    "row.appendChild(arrow)}",
    "const chord=document.createElement('span');",
    "Object.assign(chord.style,{display:'inline-flex',flexWrap:'wrap',",
    "alignItems:'center',gap:(4*c.scale)+'px'});",
    "group.forEach((label,j)=>{",
    "if(j){const plus=document.createElement('span');plus.textContent='+';",
    "chord.appendChild(plus)}",
    "const cap=document.createElement('span');cap.textContent=label;",
    "Object.assign(cap.style,{display:'inline-block',",
    "padding:(5*c.scale)+'px '+(9*c.scale)+'px',",
    "borderRadius:(7*c.scale)+'px',background:'rgba(0,0,0,0.78)',",
    "border:'1px solid rgba(255,255,255,0.65)',",
    "boxSizing:'border-box'});chord.appendChild(cap)});",
    "row.appendChild(chord)});document.body.appendChild(row);",
    "return row.getBoundingClientRect().height})()"
  )
  screen_render(page, width, height, path, script)
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
    text <- gsub("\r\n?", "\n", window$caption$text)
    text <- gsub("&", "&amp;", text, fixed = TRUE)
    text <- gsub("<", "&lt;", text, fixed = TRUE)
    text <- gsub(">", "&gt;", text, fixed = TRUE)
    text <- gsub("\n(?:[ \t]*\n)+", "\n", text, perl = TRUE)
    text <- gsub("^(?:[ \t]*\n)+|(?:\n[ \t]*)+$", "", text, perl = TRUE)
    c(paste0(time(window$start), " --> ", time(window$end)), text, "")
  }))
  writeLines(c("WEBVTT", "", cues), path, useBytes = TRUE)
  invisible(path)
}


key_callout_windows <- function(rec, sampled) {
  events <- rec$keypresses
  if (!length(events)) {
    return(list())
  }
  vts <- sampled$vts
  first_tick <- function(vt) {
    match <- which(vts >= vt - 1e-9)
    if (length(match)) match[[1]] else length(vts) + 1L
  }
  starts <- vapply(events, function(event) first_tick(event$vt), integer(1))
  windows <- list()
  for (i in seq_along(events)) {
    start <- starts[[i]]
    last <- first_tick(events[[i]]$last)
    replacement <- if (i < length(events)) {
      starts[[i + 1L]]
    } else {
      sampled$n_ticks + 1L
    }
    end <- min(
      last + ceiling(1.25 * rec$fps),
      replacement,
      sampled$n_ticks + 1L
    )
    if (start >= end) {
      next
    }
    fade <- last + ceiling(rec$fps)
    windows[[length(windows) + 1L]] <- list(
      start = (start - 1L) / rec$fps,
      end = (end - 1L) / rec$fps,
      fade_start = (fade - 1L) / rec$fps,
      style = events[[i]]$style,
      keys = events[[i]]$keys
    )
  }
  windows
}

screen_scale <- function(rec, out) {
  home_width <- if (is.null(rec$crop)) {
    rec$camera_viewport_width
  } else {
    rec$crop$width
  }
  out$width / home_width
}

caption_overlays <- function(rec, page, out, windows, dir) {
  scale <- screen_scale(rec, out)
  lapply(seq_along(windows), function(i) {
    window <- windows[[i]]
    name <- paste0("caption-", i, ".png")
    height <- caption_render(
      page,
      window$caption,
      out$width,
      out$height,
      scale,
      file.path(dir, name)
    )
    span <- window$end - window$start
    fades <- span >= 3 / rec$fps
    list(
      file = name,
      start = window$start,
      end = window$end,
      fade_in = if (window$start > 0 && fades) window$start else NULL,
      fade_start = if (fades) window$end - min(0.25, span / 2) else NULL,
      height = height,
      side = window$caption$side
    )
  })
}

key_callout_overlays <- function(rec, page, out, windows, captions, dir) {
  scale <- screen_scale(rec, out)
  lapply(seq_along(windows), function(i) {
    window <- windows[[i]]
    bottom <- 24 * scale
    overlapping <- Filter(
      function(caption) {
        identical(caption$side, "bottom") &&
          caption$start < window$end &&
          window$start < caption$end
      },
      captions
    )
    if (length(overlapping)) {
      bottom <- bottom +
        max(vapply(overlapping, `[[`, numeric(1), "height")) +
        12 * scale
    }
    name <- paste0("key-", i, ".png")
    groups <- lapply(window$keys, function(key) {
      key_callout_labels(key$spec, key$resolved, window$style)
    })
    key_callout_render(
      page,
      groups,
      out$width,
      out$height,
      scale,
      bottom,
      file.path(dir, name)
    )
    list(
      file = name,
      start = window$start,
      end = window$end,
      fade_in = NULL,
      fade_start = if (window$fade_start < window$end) {
        window$fade_start
      } else {
        NULL
      }
    )
  })
}

screen_filter <- function(rec, sampled, out, overlays) {
  chains <- paste0("[in]", out$vfilter, "[b0]")
  for (i in seq_along(overlays)) {
    item <- overlays[[i]]
    fades <- character(0)
    if (!is.null(item$fade_in)) {
      fades <- c(
        fades,
        paste0(
          "fade=t=in:st=",
          sprintf("%.6f", item$fade_in),
          ":d=",
          sprintf("%.6f", min(0.25, (item$end - item$start) / 2)),
          ":alpha=1"
        )
      )
    }
    if (!is.null(item$fade_start)) {
      fades <- c(
        fades,
        paste0(
          "fade=t=out:st=",
          sprintf("%.6f", item$fade_start),
          ":d=",
          sprintf("%.6f", item$end - item$fade_start),
          ":alpha=1"
        )
      )
    }
    movie <- paste0(
      "movie=",
      item$file,
      ":loop=1,format=rgba,",
      "loop=",
      sampled$n_ticks,
      ":size=1:start=0,",
      "setpts=N/(",
      rec$fps,
      "*TB)",
      if (length(fades)) paste0(",", paste(fades, collapse = ",")) else "",
      "[c",
      i,
      "]"
    )
    output <- if (i == length(overlays)) "" else paste0("[b", i, "]")
    overlay <- paste0(
      "[b",
      i - 1L,
      "][c",
      i,
      "]overlay=0:0:enable='between(t,",
      sprintf("%.6f", item$start),
      ",",
      sprintf("%.6f", item$end - 0.000001),
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
