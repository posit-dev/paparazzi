#' Move the recording camera
#'
#' Moves an encode-time camera over a recording. The target is an element,
#' locator, or list of targets; without a target, the current scope is used
#' (at the root, a target is required). The camera does not change the live
#' page or still screenshots. Outside a recording it does nothing, and each
#' [pz_record_start()] begins at the recording frame.
#'
#' @inheritParams pz_click
#' @param zoom Magnification relative to the recording frame. `NULL` fits
#'   the target with padding, capped at the capture's pixel density.
#' @param pad Padding in CSS pixels around the target; one number or
#'   `c(top, right, bottom, left)`. Defaults to 24 pixels.
#' @param duration Movement duration in seconds. `NULL` chooses a duration
#'   based on the pan and zoom distance.
#' @return `ctx`, invisibly.
#' @export
pz_camera <- function(
  ctx,
  target = NULL,
  ...,
  zoom = NULL,
  pad = NULL,
  duration = NULL
) {
  check_context(ctx)
  check_dots_empty()
  check_number_decimal(
    zoom,
    min = 0,
    allow_infinite = FALSE,
    allow_null = TRUE
  )
  if (!is.null(zoom) && zoom == 0) {
    cli::cli_abort("{.arg zoom} must be greater than zero.")
  }
  check_number_decimal(
    duration,
    min = 0,
    allow_infinite = FALSE,
    allow_null = TRUE
  )
  pad <- check_pad(if (is.null(pad)) 24 else pad)
  if (is.null(target) && is.null(scope_top(ctx))) {
    cli::cli_abort("Supply a {.arg target} or use a scoped context.")
  }
  rec <- page_recorder(ctx$page)
  if (is.null(rec) || !rec$active) {
    return(invisible(ctx))
  }
  box <- frame_content_box(ctx, target, new_frame_spec())
  box <- box + c(-pad[4], -pad[1], pad[2], pad[3])
  frame_region(box)
  geometry <- page_geometry(ctx)
  box <- box + rep(c(geometry$scroll_x, geometry$scroll_y), 2)
  camera_move(ctx, rec, box, zoom = zoom, duration = duration)
  invisible(ctx)
}

#' Reset the recording camera
#'
#' Returns the camera to the recording frame (or the full viewport).
#' Outside a recording it does nothing.
#'
#' @inheritParams pz_click
#' @return `ctx`, invisibly.
#' @export
pz_camera_reset <- function(ctx) {
  check_context(ctx)
  rec <- page_recorder(ctx$page)
  if (is.null(rec) || !rec$active) {
    return(invisible(ctx))
  }
  camera_move(ctx, rec, reset = TRUE)
  invisible(ctx)
}

camera_move <- function(
  ctx,
  rec,
  box = NULL,
  zoom = NULL,
  duration = NULL,
  reset = FALSE
) {
  if (rec$format == "gif") {
    rlang::check_installed(
      "av",
      reason = "to apply the recording camera to GIFs."
    )
  }
  now <- rec_vt(rec)
  home <- camera_home(rec, ctx)
  density <- pz_js(ctx, "window.devicePixelRatio")
  scroll <- page_geometry(ctx)
  scroll <- c(scroll$scroll_x, scroll$scroll_y)
  from <- camera_at(rec$camera, now, home, density)
  if (isTRUE(attr(from, "reset"))) {
    from <- home + rep(scroll, 2)
  }
  from <- as.numeric(from)
  to <- if (reset) {
    home + rep(scroll, 2)
  } else {
    camera_shot(box, home, zoom, density)
  }
  if (is.null(duration)) {
    duration <- camera_duration(from, to, home)
  }
  rec$camera[[length(rec$camera) + 1L]] <- list(
    start = now,
    end = now + duration,
    box = box,
    zoom = zoom,
    reset = reset,
    scroll = scroll
  )
  if (duration > 0) {
    pump_loop(ctx$page$child_loop, duration)
  }
  invisible(rec)
}

camera_follow_move <- function(ctx, rect, duration) {
  page <- ctx$page
  rec <- page_recorder(page)
  if (is.null(rec) || !rec$active || !isTRUE(page_stage(page)$camera_follow)) {
    return(FALSE)
  }
  now <- rec_vt(rec)
  home <- camera_home(rec, ctx)
  geometry <- page_geometry(ctx)
  scroll <- c(geometry$scroll_x, geometry$scroll_y)
  density <- if (length(rec$files) && !is.null(rec$camera_viewport_width)) {
    png_read_size(rec$files[[1]])$width / rec$camera_viewport_width
  } else if (identical(rec$method, "screencast")) {
    1
  } else {
    pz_js(ctx, "window.devicePixelRatio")
  }
  at <- camera_at(rec$camera, now, home, density)
  current <- camera_viewport(
    as.numeric(at),
    scroll,
    home,
    reset = isTRUE(attr(at, "reset"))
  ) +
    rep(scroll, 2)
  target <- c(
    rect[["x"]],
    rect[["y"]],
    rect[["x"]] + rect[["width"]],
    rect[["y"]] + rect[["height"]]
  ) +
    rep(scroll, 2)
  shot <- camera_follow_shot(current, target, home, scroll)
  if (is.null(shot)) {
    return(FALSE)
  }
  # Stop-time home is not measured yet: encode reinterprets this zoom
  # against the final home, like automatic durations in manual moves.
  rec$camera[[length(rec$camera) + 1L]] <- list(
    start = now,
    end = now + duration,
    box = shot,
    zoom = (home[3] - home[1]) / (shot[3] - shot[1]),
    reset = FALSE,
    scroll = scroll,
    follow = TRUE
  )
  TRUE
}

camera_follow_shot <- function(current, target, home, scroll) {
  home_width <- home[3] - home[1]
  home_height <- home[4] - home[2]
  width <- current[3] - current[1]
  if (width >= home_width - 1e-7) {
    return(NULL)
  }
  padded <- target + c(-24, -24, 24, 24)
  if (
    all(padded[1:2] >= current[1:2] - 1e-7) &&
      all(padded[3:4] <= current[3:4] + 1e-7)
  ) {
    return(NULL)
  }
  width <- min(
    home_width,
    max(
      width,
      padded[3] - padded[1],
      (padded[4] - padded[2]) * home_width / home_height
    )
  )
  size <- c(width, width * home_height / home_width)
  origin <- pmin(pmax(current[1:2], padded[3:4] - size), padded[1:2])
  proposed <- c(origin, origin + size)
  shot <- camera_viewport(proposed, scroll, home) + rep(scroll, 2)
  if (all(abs(shot - current) < 1e-7)) NULL else shot
}

camera_home <- function(rec, ctx) {
  if (!is.null(rec$crop)) {
    return(c(
      rec$crop$x,
      rec$crop$y,
      rec$crop$x + rec$crop$width,
      rec$crop$y + rec$crop$height
    ))
  }
  # A stop-time frame has no measured home yet: estimate automatic
  # duration with the current viewport and resolve the shot at encode.
  geometry <- page_geometry(ctx)
  c(0, 0, geometry$viewport_width, geometry$viewport_height)
}

camera_shot <- function(target, home, zoom = NULL, density = 1) {
  width <- home[3] - home[1]
  height <- home[4] - home[2]
  if (is.null(zoom)) {
    fitted <- frame_grow_ratio(width / height, target, "center")
    shot_width <- min(width, max(fitted[3] - fitted[1], width / density))
  } else {
    shot_width <- width / max(zoom, 1)
  }
  center <- c((target[1] + target[3]) / 2, (target[2] + target[4]) / 2)
  half <- c(shot_width / 2, shot_width * height / width / 2)
  c(center - half, center + half)
}

camera_viewport <- function(shot, scroll, home, reset = FALSE) {
  if (reset) {
    return(home)
  }
  shot <- shot - rep(scroll, 2)
  width <- min(shot[3] - shot[1], home[3] - home[1])
  height <- min(shot[4] - shot[2], home[4] - home[2])
  x <- min(max((shot[1] + shot[3] - width) / 2, home[1]), home[3] - width)
  y <- min(max((shot[2] + shot[4] - height) / 2, home[2]), home[4] - height)
  c(x, y, x + width, y + height)
}

camera_duration <- function(from, to, home) {
  center <- function(box) c((box[1] + box[3]) / 2, (box[2] + box[4]) / 2)
  diagonal <- sqrt((home[3] - home[1])^2 + (home[4] - home[2])^2)
  d <- sqrt(sum((center(to) - center(from))^2)) /
    diagonal +
    0.5 * abs(log2((from[3] - from[1]) / (to[3] - to[1])))
  min(2, max(0.66, 0.66 + 2 * d))
}

camera_interpolate <- function(from, to, progress) {
  progress <- min(1, max(0, progress))
  eased <- if (progress < 0.5) 4 * progress^3 else 1 - 4 * (1 - progress)^3
  center <- function(box) c((box[1] + box[3]) / 2, (box[2] + box[4]) / 2)
  from_center <- center(from)
  to_center <- center(to)
  width <- (from[3] - from[1]) * ((to[3] - to[1]) / (from[3] - from[1]))^eased
  height <- (from[4] - from[2]) * ((to[4] - to[2]) / (from[4] - from[2]))^eased
  midpoint <- from_center + (to_center - from_center) * eased
  c(midpoint - c(width, height) / 2, midpoint + c(width, height) / 2)
}

camera_at <- function(moves, time, home, density) {
  current <- home
  if (!length(moves)) {
    return(structure(current, reset = TRUE))
  }
  prior <- NULL
  for (move in moves) {
    if (time < move$start) {
      break
    }
    if (!is.null(prior)) {
      progress <- if (prior$end <= prior$start) {
        1
      } else {
        (move$start - prior$start) / (prior$end - prior$start)
      }
      current <- camera_interpolate(current, prior$to, progress)
      if (prior$reset && progress >= 1) {
        current <- home + rep(move$scroll, 2)
      }
    } else {
      current <- home + rep(move$scroll, 2)
    }
    to <- if (move$reset) {
      home + rep(move$scroll, 2)
    } else {
      camera_shot(move$box, home, move$zoom, density)
    }
    prior <- list(
      start = move$start,
      end = move$end,
      to = to,
      reset = move$reset
    )
  }
  if (is.null(prior)) {
    return(structure(current, reset = TRUE))
  }
  progress <- if (prior$end <= prior$start) {
    1
  } else {
    (time - prior$start) / (prior$end - prior$start)
  }
  structure(
    camera_interpolate(current, prior$to, progress),
    reset = prior$reset && progress >= 1
  )
}

camera_filter <- function(rec, sampled, out, png_size, call = caller_env()) {
  density <- png_size$width / rec$camera_viewport_width
  sizes <- lapply(unique(sampled$files), png_read_size, call = call)
  if (
    any(vapply(sizes, function(size) !identical(size, png_size), logical(1)))
  ) {
    cli::cli_abort(
      "Camera recordings with a resized viewport are not yet supported.",
      class = "paparazzi_error_record",
      call = call
    )
  }
  if (
    !rec$camera_warned &&
      any(vapply(
        rec$camera,
        function(move) {
          !isTRUE(move$follow) && !is.null(move$zoom) && move$zoom > density
        },
        logical(1)
      ))
  ) {
    cli::cli_warn(
      "Camera zoom exceeds the capture's {density}x pixel density; the image may look soft."
    )
    rec$camera_warned <- TRUE
  }
  source <- if (is.null(out$crop)) {
    c(0, 0, png_size$width, png_size$height)
  } else {
    crop <- out$crop
    c(crop$x, crop$y, crop$x + crop$width, crop$y + crop$height)
  }
  home <- source / density
  corners <- matrix(0, nrow = sampled$n_ticks, ncol = 4)
  for (i in seq_len(sampled$n_ticks)) {
    at <- camera_at(
      rec$camera,
      sampled$vts[[i]],
      home,
      density
    )
    box <- camera_viewport(
      as.numeric(at),
      rec$scroll[[sampled$index[[i]]]],
      home,
      reset = isTRUE(attr(at, "reset"))
    )
    corners[i, ] <- box * density
  }
  x0 <- camera_expression(corners[, 1])
  y0 <- camera_expression(corners[, 2])
  x1 <- camera_expression(corners[, 3])
  y1 <- camera_expression(corners[, 4])
  format <- if (rec$format == "gif") "rgb24" else "yuv420p"
  paste0(
    "perspective=sense=source:eval=frame:interpolation=linear:",
    "x0=",
    x0,
    ":y0=",
    y0,
    ":x1=",
    x1,
    ":y1=",
    y0,
    ":x2=",
    x0,
    ":y2=",
    y1,
    ":x3=",
    x1,
    ":y3=",
    y1,
    ",scale=",
    out$width,
    ":",
    out$height,
    ",format=",
    format
  )
}

camera_expression <- function(values) {
  values <- sprintf("%.5f", values)
  runs <- rle(values)
  if (length(runs$values) == 1L) {
    return(runs$values[[1]])
  }
  starts <- cumsum(c(1L, head(runs$lengths, -1L)))
  build <- function(lo, hi) {
    if (lo == hi) {
      return(runs$values[[lo]])
    }
    mid <- (lo + hi) %/% 2L
    paste0(
      "if(lt(in\\,",
      starts[[mid + 1L]],
      ")\\,",
      build(lo, mid),
      "\\,",
      build(mid + 1L, hi),
      ")"
    )
  }
  build(1L, length(runs$values))
}
