annotation_page <- function(.env = parent.frame()) {
  page <- local_page(.env = .env)
  pz_js(
    page,
    paste0(
      "document.body.innerHTML = '<div id=\"fixed\" style=\"position:fixed;top:20px;left:30px;width:90px;height:35px\"></div>' +",
      "'<div id=\"outer\" style=\"position:absolute;top:110px;left:30px;width:260px;height:90px;overflow:auto\">' +",
      "'<div style=\"height:160px\"></div><div class=\"mark\" id=\"inner\" style=\"height:30px;width:80px\"></div></div>' +",
      "'<div class=\"mark\" id=\"box\" style=\"position:absolute;left:200px;top:310px;width:100px;height:50px\"></div>' +",
      "'<div style=\"height:1800px\"></div>';"
    )
  )
  page
}

annotation_state <- function(page) {
  pz_js(
    page,
    paste0(
      "(() => { const layer = document.getElementById('paparazzi-overlay-root')?.shadowRoot?.querySelector('.pz-annotations');",
      "if (!layer) return null; return [...layer.querySelectorAll('.pz-annotation')].map(n =>",
      "({rect:[parseFloat(n.style.left),parseFloat(n.style.top),parseFloat(n.style.width),parseFloat(n.style.height)],",
      "visible:n.style.display !== 'none', label:n.textContent, color:n.style.borderColor,",
      "animations:n.getAnimations().length})); })()"
    )
  )
}

test_that("boxes draw for every match, replace by id, and clear without leaking to find", {
  page <- annotation_page()
  page |> pz_stage_annotate(color = "rgb(255, 0, 0)", font_size = 18)
  expect_identical(
    pz_annotate(
      page,
      ".mark",
      id = "group",
      label = TRUE,
      pad = 4,
      reveal = "none"
    ),
    page
  )
  boxes <- annotation_state(page)
  expect_length(boxes, 2)
  expect_equal(vapply(boxes, `[[`, "", "label"), c("1", "2"))
  expect_equal(
    as.numeric(unlist(boxes[[2]]$rect)),
    c(196, 306, 108, 58),
    tolerance = 1
  )
  expect_identical(boxes[[1]]$color, "rgb(255, 0, 0)")
  expect_equal(pz_get_count(page, ".pz-annotation"), 0)
  page |> pz_annotate("#fixed", id = "group", label = "A", reveal = "none")
  expect_length(annotation_state(page), 1)
  expect_identical(annotation_state(page)[[1]]$label, "A")
  page |> pz_annotate("#box", reveal = "none")
  expect_length(annotation_state(page), 2)
  page |> pz_annotate_clear("group")
  expect_length(annotation_state(page), 1)
  page |> pz_annotate_clear("spotlight") |> pz_annotate_clear("caption")
  expect_length(annotation_state(page), 1)
  page |> pz_annotate_clear()
  expect_length(annotation_state(page), 0)
})

test_that("boxes follow page scroll, inner scrolling, fixed position and layout shift", {
  page <- annotation_page()
  page |> pz_annotate("#box", id = "box", reveal = "none")
  page |> pz_annotate("#inner", id = "inner", reveal = "none")
  page |> pz_annotate("#fixed", id = "fixed", reveal = "none")
  # #inner starts scrolled out of #outer's box, so its mark is hidden;
  # bring it into the container's view before measuring movement.
  pz_js(page, "document.getElementById('outer').scrollTop = 100")
  pz_poll(
    function() isTRUE(annotation_state(page)[[2]]$visible),
    timeout = 5,
    loop = page$child_loop,
    what = "the inner mark to become visible in the container"
  )
  expect_true(annotation_state(page)[[2]]$visible)
  before <- annotation_state(page)
  pz_js(
    page,
    "window.scrollTo(0, 80); document.getElementById('outer').scrollTop = 130; document.getElementById('box').style.top = '350px'"
  )
  pz_poll(
    function() {
      now <- annotation_state(page)
      # One scroll handler updates all annotations in the same tick; the box
      # delta is exact, so anchor the poll on it and the fixed annotation.
      length(now) == 3L &&
        abs(
          as.numeric(now[[1]]$rect[[2]]) -
            (as.numeric(before[[1]]$rect[[2]]) - 40)
        ) <
          2 &&
        abs(
          as.numeric(now[[3]]$rect[[2]]) -
            as.numeric(before[[3]]$rect[[2]])
        ) <
          2
    },
    timeout = 5,
    loop = page$child_loop,
    what = "the annotations to track the scroll and layout shift"
  )
  after <- annotation_state(page)
  expect_equal(
    as.numeric(after[[1]]$rect[[2]]),
    as.numeric(before[[1]]$rect[[2]]) - 40,
    tolerance = 2
  )
  expect_equal(
    as.numeric(after[[2]]$rect[[2]]),
    as.numeric(before[[2]]$rect[[2]]) - 110,
    tolerance = 2
  )
  expect_equal(
    as.numeric(after[[3]]$rect[[2]]),
    as.numeric(before[[3]]$rect[[2]]),
    tolerance = 2
  )
  pz_js(page, "document.getElementById('inner').style.display = 'none'")
  pz_poll(
    function() isFALSE(annotation_state(page)[[2]]$visible),
    timeout = 5,
    loop = page$child_loop,
    what = "the inner mark to hide with its target"
  )
  expect_false(annotation_state(page)[[2]]$visible)
  pz_js(page, "document.getElementById('inner').style.display = ''")
  pz_poll(
    function() isTRUE(annotation_state(page)[[2]]$visible),
    timeout = 5,
    loop = page$child_loop,
    what = "the inner mark to reappear with its target"
  )
  expect_true(annotation_state(page)[[2]]$visible)
  pz_js(page, "document.getElementById('outer').scrollTop = 0")
  pz_poll(
    function() isFALSE(annotation_state(page)[[2]]$visible),
    timeout = 5,
    loop = page$child_loop,
    what = "the inner mark to hide out of view"
  )
  expect_false(annotation_state(page)[[2]]$visible)
  pz_js(page, "document.getElementById('box').remove()")
  pz_poll(
    function() isFALSE(annotation_state(page)[[1]]$visible),
    timeout = 5,
    loop = page$child_loop,
    what = "the box mark to hide with its removed target"
  )
  expect_false(annotation_state(page)[[1]]$visible)
})

test_that("annotations belong to the current document and layer boots after navigation", {
  page <- local_nav_page()
  page |> pz_annotate("body", id = "old", reveal = "none")
  expect_length(annotation_state(page), 1)
  page |> pz_nav_goto(nav_fixture_url("b"))
  expect_length(annotation_state(page), 0)
  page |> pz_annotate("body", id = "new", reveal = "none")
  expect_length(annotation_state(page), 1)
  page |> pz_annotate_clear("new")
  expect_length(annotation_state(page), 0)
})

test_that("fade outside recording is instant, and invalid types fail", {
  page <- annotation_page()
  page |> pz_annotate("#box", id = "x")
  expect_equal(annotation_state(page)[[1]]$animations, 0)
  page |> pz_annotate_clear("x")
  expect_length(annotation_state(page), 0)
  expect_error(pz_annotate(page, "#box", type = "unknown"))
  expect_error(
    pz_annotate(
      page,
      "#box",
      type = c("box", "circle", "underline", "highlight")
    ),
    "type"
  )
  expect_error(pz_annotate(page, "#box", reveal = "unknown"))
  expect_error(
    pz_annotate(
      page,
      "#box",
      reveal = c("fade", "draw", "pop", "slide", "wipe", "none")
    ),
    "reveal"
  )
  expect_error(pz_annotate(page, "#box", id = "caption"))
})

test_that("marks reject empty style strings", {
  page <- annotation_page()
  expect_error(pz_annotate(page, "#box", color = ""), "color.*empty string")
  expect_error(
    pz_annotate(page, "#box", font_family = ""),
    "font_family.*empty string"
  )
})

test_that("scoped targets, stage defaults and empty screenshot sync behave", {
  page <- annotation_page()
  shot <- withr::local_tempfile(fileext = ".png")
  expect_no_error(pz_annotate_clear(page))
  expect_no_error(pz_screenshot(page, shot))
  scoped <- pz_find(page, "#outer")
  scoped |> pz_annotate("#inner", id = "inside", label = 7, reveal = "none")
  expect_identical(annotation_state(page)[[1]]$label, "7")
  page |> pz_annotate_clear()
  pz_annotate(scoped, id = "container", reveal = "none")
  expect_length(annotation_state(page), 1)
  expect_equal(
    as.numeric(unlist(annotation_state(page)[[1]]$rect)),
    as.numeric(unlist(pz_js(
      page,
      "(() => { const r = document.querySelector('#outer').getBoundingClientRect(); return [r.left, r.top, r.width, r.height]; })()"
    ))),
    tolerance = 1
  )
  page |> pz_annotate_clear()
  page |>
    pz_stage_annotate(
      color = "green",
      font_family = "monospace",
      font_size = 20
    )
  page |> pz_annotate("#box", label = "A", reveal = "none")
  expect_identical(annotation_state(page)[[1]]$color, "green")
  badge_style <- pz_js(
    page,
    "(() => { const s = document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotation span').style; return [s.fontSize, s.fontFamily]; })()"
  )
  expect_equal(unlist(badge_style), c("20px", "monospace"))
  page |>
    pz_annotate_clear() |>
    pz_stage_annotate(
      color = NULL,
      font_family = NULL,
      font_size = NULL
    )
  page |> pz_annotate("#box", reveal = "none")
  expect_identical(annotation_state(page)[[1]]$color, "rgb(225, 29, 72)")
  expect_error(pz_annotate(page, "#box", pad = c(1, 2)))
})

test_that("stills sync box after immediate shift and hide inspect outlines", {
  skip_if_not_installed("png")
  page <- annotation_page()
  path <- withr::local_tempfile(fileext = ".png")
  framed <- withr::local_tempfile(fileext = ".png")
  page |> pz_annotate("#box", id = "box", reveal = "none", color = "#ff0000")
  # Chrome has not had to paint a frame since this synchronous layout update.
  pz_js(page, "document.getElementById('box').style.top = '370px'")
  overlay_draw(
    page,
    NULL,
    data.frame(left = 200, top = 370, width = 100, height = 50)
  )
  page |> pz_screenshot(path)
  dpr <- page_dpr(page)
  img <- png::readPNG(path)
  at <- function(image, x, y) {
    as.numeric(image[round(y * dpr) + 1, round(x * dpr) + 1, 1:3])
  }
  expect_equal(at(img, 225, 371), c(1, 0, 0), tolerance = 0.04)
  expect_equal(at(img, 225, 311), c(1, 1, 1), tolerance = 0.04)
  # The inspect box at x=200..300 is rose, not red; it must not enter stills.
  expect_true(inspect_overlay_count(page) > 0)
  page |> pz_screenshot(framed, frame = "#box")
  cropped <- png::readPNG(framed)
  expect_equal(at(cropped, 25, 1), c(1, 0, 0), tolerance = 0.04)
  overlay_clear(page)
})

test_that("a recorded fade settles into captured frames and clears in reverse", {
  skip_if_no_av()
  skip_if_not_installed("png")
  page <- annotation_page()
  path <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(path, fps = 20, hold = c(0, 0), keep_frames = TRUE)
  defer_record_stop(page)
  page |>
    pz_annotate("#box", id = "animated", reveal = "fade", color = "#ff0000")
  dpr <- page_dpr(page)
  green_at_border <- function(file) {
    png::readPNG(file)[round(311 * dpr) + 1, round(225 * dpr) + 1, 2]
  }
  last_green <- function() {
    files <- page_recorder(page)$files
    if (!length(files)) {
      return(NA_real_)
    }
    green_at_border(tail(files, 1))
  }
  # Mid-animation pixels are covered by the controlled reveal tests.
  pz_poll(
    function() {
      isTRUE(last_green() < 0.1) &&
        annotation_state(page)[[1]]$animations == 0
    },
    timeout = 5,
    loop = page$child_loop,
    what = "a settled frame of the completed fade"
  )
  expect_equal(annotation_state(page)[[1]]$animations, 0)
  page |> pz_annotate_clear("animated")
  pz_poll(
    function() {
      isTRUE(last_green() > 0.9) && length(annotation_state(page)) == 0
    },
    timeout = 5,
    loop = page$child_loop,
    what = "a settled frame of the reversed fade"
  )
  expect_length(annotation_state(page), 0)
  page |> pz_record_stop()
  expect_true(file.exists(path))
})

test_that("a final clear retains the unannotated frame before the end hold", {
  skip_if_no_av()
  skip_if_not_installed("png")
  page <- annotation_page()
  # Styled scrollbars exercise classic gutters on overlay-scrollbar
  # platforms: the screencast surface is wider than the client viewport, so
  # settle captures that clip to the client area would mix frame sizes.
  pz_js(
    page,
    "document.head.insertAdjacentHTML('beforeend', '<style>::-webkit-scrollbar { width:15px; height:15px }</style>')"
  )
  expect_lt(
    pz_js(page, "window.visualViewport.width"),
    pz_js(page, "window.innerWidth")
  )
  pz_js(page, "document.getElementById('box').style.background = '#0000ff'")
  path <- withr::local_tempfile(fileext = ".mp4")
  pz_record_start(
    page,
    path,
    method = "screencast",
    fps = 20,
    hold = c(0, 0.5),
    keep_frames = TRUE
  )
  rec <- page_recorder(page)
  withr::defer(unlink(rec$frames_dir, recursive = TRUE))
  defer_record_stop(page)
  pz_poll(
    function() {
      if (!length(rec$files)) {
        return(FALSE)
      }
      marker <- png::readPNG(tail(rec$files, 1))[331, 251, 1:3]
      all(marker == c(0, 0, 1))
    },
    timeout = 5,
    loop = page$child_loop,
    what = "the unannotated reference frame with the blue box"
  )
  reference <- png::readPNG(tail(rec$files, 1))
  pz_annotate(page, "#box", type = "box", reveal = "fade")
  pz_annotate(page, "#fixed", type = "circle", reveal = "wipe")
  pz_annotate_callout(page, "Then press Add", target = "#box", reveal = "draw")
  pz_record_hold(page, 1)
  pz_poll(
    function() max(abs(png::readPNG(tail(rec$files, 1)) - reference)) > 0.5,
    timeout = 5,
    loop = page$child_loop,
    what = "a retained frame containing the annotations"
  )
  expect_gt(max(abs(png::readPNG(tail(rec$files, 1)) - reference)), 0.5)

  # Extend the browser's actual exits without changing the reported durations.
  # Completion must not depend on the nominal animation budget.
  pz_js(
    page,
    paste0(
      "const originalAnimate = Element.prototype.animate;",
      "Element.prototype.animate = function(frames, options) {",
      "return originalAnimate.call(this, frames, {...options, duration:options.duration * 4}); };"
    )
  )
  pz_annotate_clear(page)
  # Polling after clear would mask its obligation to retain the completed state.
  cleared <- tail(rec$files, 1)
  pz_record_stop(page)
  # Screencast frames and settle captures must be the same size: a
  # recording that mixes frame sizes corrupts the encoded output.
  expect_frame_files_size(rec$files, png_dimensions(rec$files[[1]]))
  # A silently failing settle capture would leave the polls satisfied by
  # later screencast frames instead of the retained completion frame.
  expect_equal(rec$n_errors, 0L)
  expect_equal(max(abs(png::readPNG(cleared) - reference)), 0)
  expect_equal(max(abs(png::readPNG(tail(rec$files, 1)) - reference)), 0)
})

test_that("a final reveal is complete in the retained poll frame", {
  skip_if_no_av()
  skip_if_not_installed("png")
  page <- annotation_page()
  path <- withr::local_tempfile(fileext = ".mp4")
  pz_record_start(
    page,
    path,
    method = "poll",
    fps = 20,
    hold = c(0, 0.5),
    keep_frames = TRUE
  )
  rec <- page_recorder(page)
  withr::defer(unlink(rec$frames_dir, recursive = TRUE))
  defer_record_stop(page)
  pz_js(
    page,
    paste0(
      "const originalAnimate = Element.prototype.animate;",
      "Element.prototype.animate = function(frames, options) {",
      "return originalAnimate.call(this, frames, {...options, duration:options.duration * 4}); };"
    )
  )
  pz_annotate(page, "#box", reveal = "fade", color = "#ff0000")
  dpr <- page_dpr(page)
  green_at_border <- function(file) {
    png::readPNG(file)[round(311 * dpr) + 1, round(225 * dpr) + 1, 2]
  }
  revealed <- tail(rec$files, 1)
  pz_record_stop(page)
  expect_lt(green_at_border(revealed), 0.1)
  expect_lt(green_at_border(tail(rec$files, 1)), 0.1)
})

test_that("a failing settle capture is counted and the recording continues", {
  skip_if_no_av()
  page <- annotation_page()
  path <- withr::local_tempfile(fileext = ".mp4")
  pz_record_start(page, path, hold = c(0, 0))
  defer_record_stop(page)
  # Only the settle-time forced captures pass scale explicitly; poll ticks
  # call record_capture() without it and keep working.
  original_capture <- record_capture
  with_mocked_bindings(
    pz_annotate(page, "#box") |> pz_annotate_clear(),
    record_capture = function(rec, page, vt, scale, extent) {
      if (missing(scale)) {
        return(original_capture(rec, page, vt))
      }
      stop("injected capture failure")
    }
  )
  rec <- page_recorder(page)
  expect_gt(rec$n_errors, 0L)
  # Later frames are not blocked by the failed settle capture.
  files_after <- length(rec$files)
  pz_poll(
    function() length(rec$files) > files_after,
    timeout = page$default_timeout,
    loop = page$child_loop,
    what = "recording frames after the failed settle"
  )
  # A working settle still retains its own completion frame after the
  # failure: the settle capture runs (explicit scale) and its file lands.
  errors_before <- rec$n_errors
  settle_captures <- 0L
  settle_file <- NULL
  with_mocked_bindings(
    pz_annotate(page, "#box"),
    record_capture = function(rec, page, vt, scale, extent) {
      if (missing(scale)) {
        return(original_capture(rec, page, vt))
      }
      settle_captures <<- settle_captures + 1L
      original_capture(rec, page, vt, scale = scale, extent = extent)
      settle_file <<- rec$pending$file
    }
  )
  expect_gt(settle_captures, 0L)
  expect_equal(rec$n_errors, errors_before)
  expect_true(settle_file %in% rec$files)
  pz_record_hold(page, 0.2)
  pz_record_stop(page)
  expect_true(file.exists(path))
})

test_that("a stuck settle capture is retired instead of blocking later frames", {
  skip_if_no_av()
  page <- annotation_page()
  page$default_timeout <- 3
  path <- withr::local_tempfile(fileext = ".mp4")
  pz_record_start(page, path, hold = c(0, 0))
  defer_record_stop(page)
  original_capture <- record_capture
  with_mocked_bindings(
    pz_annotate(page, "#box"),
    record_capture = function(rec, page, vt, scale, extent) {
      if (missing(scale)) {
        return(original_capture(rec, page, vt))
      }
      rec$pending <- new.env(parent = emptyenv())
    }
  )
  rec <- page_recorder(page)
  expect_gt(rec$n_errors, 0L)
  # Later frames are not blocked by the retired settle capture.
  files_after <- length(rec$files)
  pz_poll(
    function() length(rec$files) > files_after,
    timeout = page$default_timeout,
    loop = page$child_loop,
    what = "recording frames after the retired settle"
  )
  pz_record_hold(page, 0.2)
  pz_record_stop(page)
  expect_true(file.exists(path))
})

test_that("recorded clear removes all nodes after mixed exit animations", {
  skip_if_no_av()
  page <- annotation_page()
  pz_record_start(page, withr::local_tempfile(fileext = ".mp4"), hold = c(0, 0))
  defer_record_stop(page)
  pz_annotate(page, "#box", id = "shared", reveal = "fade")
  pz_annotate(page, "#box", id = "shared", reveal = "wipe")
  pz_annotate_callout(page, "Tip", target = "#box", id = "callout")
  pz_annotate_spotlight(page, "#box")
  pz_annotate_redact(page, "#box", id = "redaction")
  pz_annotate_clear(page)
  # Node removal runs in the browser animation's onfinish callback.
  pz_poll(
    function() {
      pz_js(
        page,
        "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations').children.length"
      ) ==
        0
    },
    timeout = 5,
    loop = page$child_loop,
    what = "the mixed exit animations to remove all annotation nodes"
  )
  expect_equal(
    pz_js(
      page,
      "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations').children.length"
    ),
    0
  )
  pz_record_stop(page)
})

test_that("recorded clear logs the caption clear before marks fade out", {
  skip_if_no_av()
  page <- annotation_page()
  pz_record_start(page, withr::local_tempfile(fileext = ".mp4"), hold = c(0, 0))
  defer_record_stop(page)
  pz_annotate(page, "#box", id = "fading", reveal = "fade")
  pz_annotate_caption(page, "Caption")
  rec <- page_recorder(page)
  before <- rec_vt(rec)
  pz_annotate_clear(page)
  after <- rec_vt(rec)
  cleared <- tail(rec$captions, 1)[[1]]
  expect_null(cleared$caption)
  expect_gte(cleared$vt, before)
  expect_lt(cleared$vt, after - 0.05)
  pz_record_stop(page)
})

test_that("paused recording skips fade on draw and clear", {
  skip_if_no_av()
  page <- annotation_page()
  path <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(path, fps = 10, hold = c(0, 0)) |> pz_record_pause()
  defer_record_stop(page)
  page |> pz_annotate("#box", id = "animated")
  expect_equal(annotation_state(page)[[1]]$animations, 0)
  page |> pz_annotate_clear("animated")
  expect_length(annotation_state(page), 0)
  page |> pz_record_resume() |> pz_record_stop()
})

test_that("redaction fills every match immediately and hides after disconnection", {
  skip_if_not_installed("png")
  page <- annotation_page()
  pz_js(
    page,
    "document.querySelectorAll('.mark').forEach(el => el.textContent = 'SECRET')"
  )
  page |> pz_stage_annotate(color = "#ff0000")
  expect_identical(
    pz_annotate_redact(page, ".mark", id = "secret", pad = 2),
    page
  )
  nodes <- pz_js(
    page,
    "(() => { const layer = document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations'); return [...layer.querySelectorAll('.pz-redaction')].map(n => ({x:parseFloat(n.style.left),y:parseFloat(n.style.top),visible:n.style.display !== 'none',animations:n.getAnimations().length,color:getComputedStyle(n).backgroundColor})); })()"
  )
  expect_length(nodes, 2)
  expect_equal(nodes[[2]]$x, 198, tolerance = 1)
  expect_identical(nodes[[2]]$color, "rgb(23, 23, 23)")
  expect_equal(nodes[[2]]$animations, 0)
  path <- withr::local_tempfile(fileext = ".png")
  page |> pz_screenshot(path)
  img <- png::readPNG(path)
  dpr <- page_dpr(page)
  at <- function(x, y) {
    as.numeric(img[round(y * dpr) + 1, round(x * dpr) + 1, 1:3])
  }
  expect_equal(at(220, 330), rep(23 / 255, 3), tolerance = 0.03)
  pz_js(page, "document.getElementById('box').remove()")
  pz_poll(
    function() {
      identical(
        pz_js(
          page,
          "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelectorAll('.pz-redaction')[1].style.display"
        ),
        "none"
      )
    },
    timeout = 5,
    loop = page$child_loop,
    what = "the removed target's redaction to hide"
  )
  after <- pz_js(
    page,
    "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelectorAll('.pz-redaction')[1].style.display"
  )
  expect_identical(after, "none")
  page |> pz_screenshot(path)
  img <- png::readPNG(path)
  expect_equal(at(220, 330), rep(1, 3), tolerance = 0.03)
  page |> pz_annotate_clear("secret")
  expect_length(annotation_state(page), 0)
})

annotation_drag_safety <- function(
  page,
  source = "document.getElementById('box')",
  footprint = "source.getBoundingClientRect()"
) {
  pz_js(
    page,
    paste0(
      "(() => { const layer = document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations');",
      "const source = ",
      source,
      ";",
      "return layer.pz.dragPreviewSafety(source, ",
      footprint,
      "); })()"
    )
  )
}

test_that("drag previews reject redacted sources and ancestors for fill and blur", {
  page <- annotation_page()
  pz_js(
    page,
    "document.getElementById('box').innerHTML = '<div id=child style=width:20px;height:20px></div>'"
  )
  for (method in c("fill", "blur")) {
    page |> pz_annotate_redact("#box", id = "secret", method = method)
    expect_identical(
      annotation_drag_safety(page),
      list(safe = FALSE, reason = "related-redaction")
    )
    expect_identical(
      annotation_drag_safety(page, "document.getElementById('child')"),
      list(safe = FALSE, reason = "related-redaction")
    )
  }
})

test_that("drag previews reject hidden redacted descendants before capture", {
  page <- annotation_page()
  pz_js(
    page,
    "document.getElementById('box').innerHTML = '<div id=secret style=width:20px;height:20px></div>'"
  )
  page |> pz_annotate_redact("#secret")
  pz_js(page, "document.getElementById('secret').style.display = 'none'")
  expect_identical(
    annotation_drag_safety(page),
    list(safe = FALSE, reason = "related-redaction")
  )
})

test_that("unrelated fill and blur masks permit drag previews without changing entries", {
  page <- annotation_page()
  for (method in c("fill", "blur")) {
    page |> pz_annotate_redact("#fixed", id = "secret", method = method)
    expect_identical(
      annotation_drag_safety(page),
      list(safe = TRUE, reason = "safe")
    )
    expect_equal(
      pz_js(
        page,
        "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelectorAll('.pz-redaction').length"
      ),
      1
    )
  }
  page |> pz_annotate_clear()
  expect_identical(
    annotation_drag_safety(page),
    list(safe = TRUE, reason = "safe")
  )
})

test_that("drag safety synchronizes padded mask overlap with the supplied footprint", {
  page <- annotation_page()
  pz_js(
    page,
    "document.getElementById('fixed').style.cssText = 'position:fixed;left:310px;top:310px;width:20px;height:50px'"
  )
  page |> pz_annotate_redact("#fixed", pad = 15)
  expect_identical(
    annotation_drag_safety(page),
    list(safe = FALSE, reason = "overlapping-redaction")
  )
  pz_js(page, "document.getElementById('fixed').style.left = '400px'")
  expect_identical(
    annotation_drag_safety(page),
    list(safe = TRUE, reason = "safe")
  )
  expect_identical(
    annotation_drag_safety(
      page,
      footprint = "{left:200,top:310,right:410,bottom:360,width:210,height:50}"
    ),
    list(safe = FALSE, reason = "overlapping-redaction")
  )
})

test_that("drag previews fail closed for missing, disconnected and cross-root sources", {
  page <- annotation_page()
  page |> pz_annotate_redact("#fixed")
  box <- "{left:200,top:310,right:300,bottom:360,width:100,height:50}"
  expect_identical(
    annotation_drag_safety(page, "null", box),
    list(safe = FALSE, reason = "unknown-source")
  )
  pz_js(
    page,
    "window.__source = document.getElementById('box'); window.__source.remove()"
  )
  expect_identical(
    annotation_drag_safety(page, "window.__source", box),
    list(safe = FALSE, reason = "unknown-source")
  )
  pz_js(
    page,
    "document.getElementById('fixed').attachShadow({mode:'open'}).innerHTML = '<div id=source style=width:20px;height:20px></div>'"
  )
  expect_identical(
    annotation_drag_safety(
      page,
      "document.getElementById('fixed').shadowRoot.getElementById('source')",
      box
    ),
    list(safe = FALSE, reason = "unknown-source")
  )
})

test_that("drag previews fail closed for stale masks, targets and unsupported methods", {
  page <- annotation_page()
  page |> pz_annotate_redact("#fixed", id = "secret")
  pz_js(
    page,
    "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-redaction').remove()"
  )
  expect_identical(
    annotation_drag_safety(page),
    list(safe = FALSE, reason = "unknown-state")
  )
  page |> pz_annotate_redact("#fixed", id = "secret")
  pz_js(page, "document.getElementById('fixed').remove()")
  expect_identical(
    annotation_drag_safety(page),
    list(safe = FALSE, reason = "unknown-state")
  )
  page |> pz_annotate_clear()
  pz_js(
    page,
    paste0(
      "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations').pz.redact(",
      "[document.getElementById('outer')], {id:'invalid',pad:[0,0,0,0],method:'pixelate',color:null,animate:false})"
    )
  )
  expect_identical(
    annotation_drag_safety(page),
    list(safe = FALSE, reason = "unknown-state")
  )
})

test_that("drag previews fail closed for cross-root redactions and untracked masks", {
  page <- annotation_page()
  page |> pz_annotate_redact("#fixed")
  pz_js(
    page,
    paste0(
      "(() => { const layer = document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations');",
      "const shadow = document.getElementById('fixed').attachShadow({mode:'open'});",
      "shadow.innerHTML = '<div style=width:20px;height:20px></div>';",
      "layer.pz.redact([shadow.firstChild], {id:'shadow',pad:[0,0,0,0],method:'fill',color:null,animate:false}); })()"
    )
  )
  expect_identical(
    annotation_drag_safety(page),
    list(safe = FALSE, reason = "unknown-state")
  )
  page |> pz_annotate_clear("shadow")
  pz_js(
    page,
    paste0(
      "(() => { const layer = document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations');",
      "layer.appendChild(layer.querySelector('.pz-redaction').cloneNode(true)); })()"
    )
  )
  expect_identical(
    annotation_drag_safety(page),
    list(safe = FALSE, reason = "unknown-state")
  )
})

test_that("drag safety uses the painted clip rather than the whole padded mask", {
  page <- annotation_page()
  pz_js(
    page,
    paste0(
      "document.getElementById('fixed').style.cssText = 'position:fixed;left:310px;top:310px;width:20px;height:50px;overflow:hidden';",
      "document.getElementById('fixed').innerHTML = '<div id=secret style=width:20px;height:50px></div>'"
    )
  )
  page |> pz_annotate_redact("#secret", pad = 20)
  expect_identical(
    annotation_drag_safety(page),
    list(safe = TRUE, reason = "safe")
  )
})

test_that("drag safety rejects invalid footprints", {
  page <- annotation_page()
  page |> pz_annotate_redact("#fixed")
  for (box in c(
    "null",
    "{left:0,top:0,right:1,bottom:1,width:Infinity,height:1}",
    "{left:0,top:0,right:1,bottom:1,width:1,height:NaN}",
    "{left:0,top:0,right:1,bottom:1,width:0,height:1}",
    "{left:0,top:0,right:1,bottom:1,width:1,height:-1}"
  )) {
    expect_identical(
      annotation_drag_safety(page, footprint = box),
      list(safe = FALSE, reason = "invalid-footprint")
    )
  }
})

test_that("redaction paints only inside a scrolling ancestor as its target moves", {
  skip_if_not_installed("png")
  page <- annotation_page()
  pz_js(
    page,
    paste0(
      "document.body.insertAdjacentHTML('beforeend', ",
      "'<div id=clip style=\"position:absolute;left:350px;top:100px;width:160px;height:100px;overflow:auto;background:white\">' +",
      "'<div style=\"height:70px\"></div><div id=secret style=\"margin-left:20px;width:90px;height:80px;background:white\">SECRET</div>' +",
      "'<div style=\"height:300px\"></div></div>')"
    )
  )
  page |> pz_annotate_redact("#secret", pad = 4)
  path <- withr::local_tempfile(fileext = ".png")
  pixel <- function(x, y) {
    page |> pz_screenshot(path)
    img <- png::readPNG(path)
    dpr <- page_dpr(page)
    as.numeric(img[round(y * dpr) + 1, round(x * dpr) + 1, 1:3])
  }
  expect_equal(pixel(380, 190), rep(23 / 255, 3), tolerance = 0.03)
  expect_equal(pixel(380, 202), rep(1, 3), tolerance = 0.03)
  pz_js(page, "document.getElementById('clip').scrollTop = 80")
  pz_poll(
    function() {
      all(
        abs(pixel(380, 110) - 23 / 255) < 0.03,
        abs(pixel(380, 190) - 1) < 0.03
      )
    },
    timeout = 5,
    loop = page$child_loop,
    what = "the redaction to follow the container scroll"
  )
  expect_equal(pixel(380, 110), rep(23 / 255, 3), tolerance = 0.03)
  expect_equal(pixel(380, 190), rep(1, 3), tolerance = 0.03)
  pz_js(page, "document.getElementById('clip').scrollTop = 250")
  pz_poll(
    function() {
      identical(
        pz_js(
          page,
          "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-redaction').style.display"
        ),
        "none"
      )
    },
    timeout = 5,
    loop = page$child_loop,
    what = "the fully scrolled-out redaction to hide"
  )
  expect_identical(
    pz_js(
      page,
      "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-redaction').style.display"
    ),
    "none"
  )
  expect_equal(pixel(380, 110), rep(1, 3), tolerance = 0.03)
  pz_js(page, "document.getElementById('clip').scrollTop = 0")
  pz_poll(
    function() {
      all(
        abs(pixel(380, 190) - 23 / 255) < 0.03,
        abs(pixel(380, 175) - 23 / 255) < 0.03
      )
    },
    timeout = 5,
    loop = page$child_loop,
    what = "the redaction to reappear scrolled back to the top"
  )
  expect_equal(pixel(380, 190), rep(23 / 255, 3), tolerance = 0.03)
  expect_equal(pixel(380, 175), rep(23 / 255, 3), tolerance = 0.03)
})

test_that("redaction padding stays clipped even when its target is uncut", {
  page <- local_page()
  pz_js(
    page,
    paste0(
      "document.body.innerHTML = '<div style=\"position:absolute;left:100px;top:100px;width:100px;height:100px;overflow:hidden;background:white\">' +",
      "'<div id=secret style=\"width:100px;height:100px\"></div></div>';",
      "document.body.style.background = 'white';"
    )
  )
  path <- withr::local_tempfile(fileext = ".png")
  page |> pz_annotate_redact("#secret", pad = 4) |> pz_screenshot(path)
  expect_png_pixel(page, path, 150, 150, rep(23, 3))
  expect_png_pixel(page, path, 150, 98, rep(255, 3))
  expect_png_pixel(page, path, 202, 150, rep(255, 3))
  expect_png_pixel(page, path, 150, 202, rep(255, 3))
  expect_png_pixel(page, path, 98, 150, rep(255, 3))
})

test_that("redaction intersects nested horizontal and vertical overflow clips", {
  skip_if_not_installed("png")
  page <- annotation_page()
  pz_js(
    page,
    paste0(
      "document.body.insertAdjacentHTML('beforeend', ",
      "'<div style=\"position:absolute;left:330px;top:100px;width:100px;height:110px;overflow-x:hidden\">' +",
      "'<div style=\"position:relative;left:-25px;top:30px;width:150px;height:55px;overflow-y:hidden\">' +",
      "'<div id=secret style=\"position:absolute;left:0;top:-25px;width:140px;height:110px\">SECRET</div>' +",
      "'</div></div>')"
    )
  )
  page |> pz_annotate_redact("#secret")
  path <- withr::local_tempfile(fileext = ".png")
  page |> pz_screenshot(path)
  img <- png::readPNG(path)
  dpr <- page_dpr(page)
  pixel <- function(x, y) {
    as.numeric(img[round(y * dpr) + 1, round(x * dpr) + 1, 1:3])
  }
  expect_equal(pixel(340, 145), rep(23 / 255, 3), tolerance = 0.03)
  expect_equal(pixel(320, 145), rep(1, 3), tolerance = 0.03)
  expect_equal(pixel(340, 115), rep(1, 3), tolerance = 0.03)
  expect_equal(pixel(340, 190), rep(1, 3), tolerance = 0.03)
})

test_that("positioned targets escape only overflow ancestors outside their containing block", {
  skip_if_not_installed("png")
  page <- annotation_page()
  pz_js(
    page,
    paste0(
      "document.body.insertAdjacentHTML('beforeend', ",
      "'<div style=\"position:absolute;left:330px;top:100px\">' +",
      "'<div style=\"width:80px;height:50px;overflow:hidden\">' +",
      "'<div id=escaped style=\"position:absolute;left:105px;top:15px;width:50px;height:30px\">SECRET</div>' +",
      "'<div id=escaped-fixed style=\"position:fixed;left:460px;top:130px;width:50px;height:30px\">SECRET</div>' +",
      "'</div></div>' +",
      "'<div style=\"position:absolute;left:330px;top:270px;width:100px;height:50px;overflow:hidden\">' +",
      "'<div id=clipped style=\"position:absolute;left:80px;top:30px;width:50px;height:40px\">SECRET</div></div>' +",
      "'<div style=\"position:absolute;left:330px;top:360px;width:100px;height:50px;overflow:hidden;transform:translateZ(0)\">' +",
      "'<div id=fixed-clipped style=\"position:fixed;left:80px;top:30px;width:50px;height:40px\">SECRET</div></div>')"
    )
  )
  page |>
    pz_annotate_redact("#escaped, #escaped-fixed, #clipped, #fixed-clipped")
  path <- withr::local_tempfile(fileext = ".png")
  page |> pz_screenshot(path)
  img <- png::readPNG(path)
  dpr <- page_dpr(page)
  pixel <- function(x, y) {
    as.numeric(img[round(y * dpr) + 1, round(x * dpr) + 1, 1:3])
  }
  expect_equal(pixel(445, 125), rep(23 / 255, 3), tolerance = 0.03)
  expect_equal(pixel(475, 145), rep(23 / 255, 3), tolerance = 0.03)
  expect_equal(pixel(420, 310), rep(23 / 255, 3), tolerance = 0.03)
  expect_equal(pixel(440, 310), rep(1, 3), tolerance = 0.03)
  expect_equal(pixel(420, 400), rep(23 / 255, 3), tolerance = 0.03)
  expect_equal(pixel(440, 400), rep(1, 3), tolerance = 0.03)
})

test_that("redaction covers visible content in the scrollport padding", {
  skip_if_not_installed("png")
  page <- annotation_page()
  pz_js(
    page,
    paste0(
      "document.body.insertAdjacentHTML('beforeend', ",
      "'<div style=\"position:absolute;left:350px;top:100px;width:80px;height:60px;padding:20px;overflow:hidden\">' +",
      "'<div id=padded-secret style=\"position:relative;left:-12px;top:-10px;width:60px;height:30px\">SECRET</div></div>')"
    )
  )
  page |> pz_annotate_redact("#padded-secret")
  path <- withr::local_tempfile(fileext = ".png")
  page |> pz_screenshot(path)
  img <- png::readPNG(path)
  dpr <- page_dpr(page)
  pixel <- function(x, y) {
    as.numeric(img[round(y * dpr) + 1, round(x * dpr) + 1, 1:3])
  }
  expect_equal(pixel(362, 115), rep(23 / 255, 3), tolerance = 0.03)
  expect_equal(pixel(348, 115), rep(1, 3), tolerance = 0.03)
})

test_that("redaction clips scaled overflow ancestors in viewport coordinates", {
  skip_if_not_installed("png")
  page <- annotation_page()
  pz_js(
    page,
    paste0(
      "document.body.insertAdjacentHTML('beforeend', ",
      "'<div style=\"position:absolute;left:330px;top:80px;width:80px;height:60px;overflow:hidden;transform:scale(2);transform-origin:top left\">' +",
      "'<div id=scaled-secret style=\"position:absolute;left:50px;top:40px;width:50px;height:50px\">SECRET</div></div>')"
    )
  )
  page |> pz_annotate_redact("#scaled-secret")
  path <- withr::local_tempfile(fileext = ".png")
  page |> pz_screenshot(path)
  img <- png::readPNG(path)
  dpr <- page_dpr(page)
  pixel <- function(x, y) {
    as.numeric(img[round(y * dpr) + 1, round(x * dpr) + 1, 1:3])
  }
  expect_equal(pixel(450, 180), rep(23 / 255, 3), tolerance = 0.03)
  expect_equal(pixel(500, 180), rep(1, 3), tolerance = 0.03)
  expect_equal(pixel(450, 210), rep(1, 3), tolerance = 0.03)
})

test_that("marks and badges hide on scrolled-out and visibility:hidden targets", {
  skip_if_not_installed("png")
  page <- local_page(pz_example("tasks"), color_scheme = "light")
  path <- withr::local_tempfile(fileext = ".png")
  page |> pz_screenshot(path)
  baseline <- png::readPNG(path)
  page |>
    pz_annotate(
      ".task-done",
      label = TRUE,
      reveal = "none",
      color = "rgb(255, 0, 0)"
    )
  # Annotation nodes are created in target order, so index i pairs the i-th
  # Done button with the i-th box.
  info <- pz_js(
    page,
    paste0(
      "(() => { const layer = document.getElementById('paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations');",
      "const nodes = [...layer.querySelectorAll('.pz-annotation')];",
      "const list = document.querySelector('.task-list').getBoundingClientRect();",
      "return {listBottom: list.bottom, viewport: [innerWidth, innerHeight],",
      "buttons: [...document.querySelectorAll('.task-done')].map((b, i) => {",
      "const r = b.getBoundingClientRect();",
      "return {rect: [r.left, r.top, r.width, r.height],",
      "clipped: r.top >= list.bottom || r.bottom <= list.top,",
      "shown: getComputedStyle(b).visibility === 'visible',",
      "annotated: nodes[i].style.display !== 'none'}; })}; })()"
    )
  )
  expect_length(info$buttons, 7)
  # Rows 6-7 sit at or below the list's bottom edge; the done row's own
  # Done button is visibility:hidden.
  expect_gt(sum(vapply(info$buttons, `[[`, TRUE, "clipped")), 0)
  for (b in info$buttons) {
    if (b$clipped || !b$shown) {
      expect_false(b$annotated)
    } else {
      expect_true(b$annotated)
    }
  }
  page |> pz_screenshot(path)
  marked <- png::readPNG(path)
  dpr <- page_dpr(page)
  at <- function(img, x, y) {
    as.numeric(img[round(y * dpr) + 1, round(x * dpr) + 1, 1:3])
  }
  red <- c(1, 0, 0)
  rects <- lapply(info$buttons, function(b) unlist(b$rect))
  # Control: a visible button's outline and badge really do paint.
  first <- rects[[Position(
    function(b) b$shown && !b$clipped,
    info$buttons
  )]]
  expect_equal(
    at(marked, first[1] + first[3] / 2, first[2] + 1),
    red,
    tolerance = 0.05
  )
  expect_equal(at(marked, first[1] + 2, first[2] - 6), red, tolerance = 0.05)
  # A scrolled-out button paints neither its box nor its badge over the
  # area below the list.
  checked <- 0
  for (rect in rects[vapply(info$buttons, `[[`, TRUE, "clipped")]) {
    if (rect[2] < info$listBottom + 24 || rect[2] + 2 >= info$viewport[[2]]) {
      next
    }
    checked <- checked + 1
    expect_equal(
      at(marked, rect[1] + rect[3] / 2, rect[2] + 1),
      at(baseline, rect[1] + rect[3] / 2, rect[2] + 1),
      tolerance = 0.03
    )
    expect_equal(
      at(marked, rect[1] + 2, rect[2] - 6),
      at(baseline, rect[1] + 2, rect[2] - 6),
      tolerance = 0.03
    )
  }
  expect_gt(checked, 0)
  # The hidden Done button shows no empty outline or badge.
  hb <- rects[[Position(function(b) !b$shown, info$buttons)]]
  expect_equal(
    at(marked, hb[1] + hb[3] / 2, hb[2] + 1),
    at(baseline, hb[1] + hb[3] / 2, hb[2] + 1),
    tolerance = 0.03
  )
  expect_equal(
    at(marked, hb[1] + 2, hb[2] - 6),
    at(baseline, hb[1] + 2, hb[2] - 6),
    tolerance = 0.03
  )
})

test_that("a fully visible new task keeps every padded outline edge", {
  page <- local_page(pz_example("tasks"), width = 992, height = 720)
  pz_js(
    page,
    "document.head.insertAdjacentHTML('beforeend', '<style>::-webkit-scrollbar { width:15px; height:15px }</style>')"
  )
  page |>
    pz_act_type("Prepare release notes", target = "#task-title") |>
    pz_act_click("#add-task")
  target <- pz_loc(".task", has_text = "Prepare release notes")
  pz_expect_visible(page, target)
  path <- withr::local_tempfile(fileext = ".png")
  red <- c(255, 0, 0)

  for (reveal in c("none", "draw")) {
    page |>
      pz_annotate(
        target,
        pad = 4,
        stroke_width = 4,
        color = "red",
        reveal = reveal,
        id = "new"
      ) |>
      pz_screenshot(path)
    # Capture can change scrollbar visibility and reflow a full-width row.
    rect <- pz_get_rect(page, target)
    expect_png_pixel(page, path, rect$x + rect$width / 2, rect$y - 2, red)
    expect_png_pixel(
      page,
      path,
      rect$x + rect$width + 2,
      rect$y + rect$height / 2,
      red
    )
    expect_png_pixel(
      page,
      path,
      rect$x + rect$width / 2,
      rect$y + rect$height + 2,
      red
    )
    expect_png_pixel(page, path, rect$x - 2, rect$y + rect$height / 2, red)
  }
})

test_that("flush fractional scaled targets keep all padded outline edges", {
  page <- local_page(test_path("fixtures", "annotation-clipping.html"))
  path <- withr::local_tempfile(fileext = ".png")
  styles <- c(
    "",
    "transform:none",
    "box-sizing:border-box",
    "overflow:scroll",
    "overflow:scroll;box-sizing:border-box;direction:rtl",
    "zoom:1.1",
    "zoom:1.5",
    "zoom:2"
  )
  red <- c(255, 0, 0)
  for (style in styles) {
    pz_js(
      page,
      paste0("document.getElementById('clip').style.cssText = '", style, "'")
    )
    rect <- pz_get_rect(page, "#target")
    page |>
      pz_annotate(
        "#target",
        pad = 6,
        stroke_width = 4,
        color = "red",
        id = "mark"
      ) |>
      pz_screenshot(path)
    expect_png_pixel(page, path, rect$x + rect$width / 2, rect$y - 4, red)
    expect_png_pixel(
      page,
      path,
      rect$x + rect$width + 4,
      rect$y + rect$height / 2,
      red
    )
    expect_png_pixel(
      page,
      path,
      rect$x + rect$width / 2,
      rect$y + rect$height + 4,
      red
    )
    expect_png_pixel(page, path, rect$x - 4, rect$y + rect$height / 2, red)
  }
})

test_that("genuinely subpixel-clipped sides do not regain their padded outline", {
  page <- local_page(test_path("fixtures", "annotation-clipping.html"))
  pz_js(page, "document.getElementById('target').style.left = '-0.015625px'")
  rect <- pz_get_rect(page, "#target")
  path <- withr::local_tempfile(fileext = ".png")
  page |>
    pz_annotate("#target", pad = 6, stroke_width = 4, color = "red") |>
    pz_screenshot(path)
  expect_png_pixel(
    page,
    path,
    rect$x - 4,
    rect$y + rect$height / 2,
    rep(255, 3)
  )
  expect_png_pixel(
    page,
    path,
    rect$x + rect$width + 4,
    rect$y + rect$height / 2,
    c(255, 0, 0)
  )
})

test_that("padding cannot reveal a target touching a fractional clip from outside", {
  page <- local_page(test_path("fixtures", "annotation-clipping.html"))
  pz_js(page, "document.getElementById('target').style.top = '100%'")
  rect <- pz_get_rect(page, "#target")
  path <- withr::local_tempfile(fileext = ".png")
  page |>
    pz_annotate("#target", pad = 6, stroke_width = 4, color = "red") |>
    pz_screenshot(path)
  expect_false(annotation_state(page)[[1]]$visible)
  expect_png_pixel(page, path, rect$x + rect$width / 2, rect$y - 4, rep(255, 3))
})

test_that("a subpixel-visible target still shows its mark", {
  page <- local_page(test_path("fixtures", "annotation-clipping.html"))
  pz_js(
    page,
    "document.getElementById('target').style.top = 'calc(100% - 0.015625px)'"
  )
  rect <- pz_get_rect(page, "#target")
  path <- withr::local_tempfile(fileext = ".png")
  page |>
    pz_annotate("#target", pad = 6, stroke_width = 4, color = "red") |>
    pz_screenshot(path)
  expect_true(annotation_state(page)[[1]]$visible)
  expect_png_pixel(
    page,
    path,
    rect$x + rect$width / 2,
    rect$y - 4,
    c(255, 0, 0)
  )
})

test_that("redactions stay inside fractional scaled overflow clips", {
  page <- local_page(test_path("fixtures", "annotation-clipping.html"))
  rect <- pz_get_rect(page, "#target")
  path <- withr::local_tempfile(fileext = ".png")
  page |> pz_annotate_redact("#target", pad = 6) |> pz_screenshot(path)
  expect_png_pixel(page, path, rect$x + rect$width / 2, rect$y + 2, rep(23, 3))
  expect_png_pixel(page, path, rect$x + rect$width / 2, rect$y - 2, rep(255, 3))
  expect_png_pixel(
    page,
    path,
    rect$x + rect$width + 2,
    rect$y + rect$height / 2,
    rep(255, 3)
  )
  expect_png_pixel(
    page,
    path,
    rect$x + rect$width / 2,
    rect$y + rect$height + 2,
    rep(255, 3)
  )
  expect_png_pixel(
    page,
    path,
    rect$x - 2,
    rect$y + rect$height / 2,
    rep(255, 3)
  )
})

test_that("only the cut side of a partially visible mark loses its padding", {
  page <- local_page()
  pz_js(
    page,
    paste0(
      "document.body.innerHTML = '<div style=\"position:absolute;left:100px;top:100px;width:100px;height:100px;overflow:hidden;background:white\">' +",
      "'<div id=marked style=\"position:relative;width:100px;height:100px\"></div></div>';",
      "document.body.style.background = 'white';"
    )
  )
  path <- withr::local_tempfile(fileext = ".png")
  red <- c(255, 0, 0)
  white <- c(255, 255, 255)
  cases <- list(
    top = "top:-20px;height:120px",
    right = "width:120px",
    bottom = "height:120px",
    left = "left:-20px;width:120px"
  )
  for (side in names(cases)) {
    pz_js(
      page,
      paste0(
        "document.getElementById('marked').style.cssText = ",
        "'position:relative;width:100px;height:100px;",
        cases[[side]],
        "'"
      )
    )
    page |>
      pz_annotate(
        "#marked",
        pad = c(4, 6, 8, 10),
        stroke_width = 4,
        color = "red",
        reveal = "none",
        id = "mark"
      ) |>
      pz_screenshot(path)
    expect_png_pixel(page, path, 150, 98, if (side == "top") white else red)
    expect_png_pixel(page, path, 204, 150, if (side == "right") white else red)
    expect_png_pixel(page, path, 150, 206, if (side == "bottom") white else red)
    expect_png_pixel(page, path, 92, 150, if (side == "left") white else red)
    expect_png_pixel(page, path, 150, 78, white)
    expect_png_pixel(page, path, 224, 150, white)
    expect_png_pixel(page, path, 150, 226, white)
    expect_png_pixel(page, path, 72, 150, white)
  }
})

test_that("a fully clipped target hides its mark even when padding overlaps", {
  page <- local_page()
  pz_js(
    page,
    paste0(
      "document.body.innerHTML = '<div style=\"position:absolute;left:100px;top:100px;width:100px;height:100px;overflow:hidden;background:white\">' +",
      "'<div id=marked style=\"position:relative;top:100px;width:100px;height:40px\"></div></div>';",
      "document.body.style.background = 'white';"
    )
  )
  path <- withr::local_tempfile(fileext = ".png")
  page |>
    pz_annotate(
      "#marked",
      pad = 4,
      label = "Hidden",
      stroke_width = 4,
      color = "red",
      reveal = "none"
    ) |>
    pz_screenshot(path)
  expect_false(annotation_state(page)[[1]]$visible)
  expect_png_pixel(page, path, 150, 198, c(255, 255, 255))
  expect_png_pixel(page, path, 100, 190, c(255, 255, 255))
})

test_that("padding does not reveal zero-size targets on a clipping edge", {
  page <- local_page()
  pz_js(
    page,
    paste0(
      "document.body.innerHTML = '<div style=\"position:absolute;left:100px;top:100px;width:100px;height:100px;overflow:hidden;background:white\">' +",
      "'<div class=mark style=\"position:relative;left:0;top:50px;width:0;height:0\"></div>' +",
      "'<div class=mark style=\"position:relative;left:50px;top:50px;width:0;height:0\"></div></div>';",
      "document.body.style.background = 'white';"
    )
  )
  path <- withr::local_tempfile(fileext = ".png")
  page |>
    pz_annotate(".mark", pad = 10, stroke_width = 4, color = "red") |>
    pz_screenshot(path)
  expect_false(annotation_state(page)[[1]]$visible)
  expect_true(annotation_state(page)[[2]]$visible)
  expect_png_pixel(page, path, 108, 150, rep(255, 3))
  expect_png_pixel(page, path, 158, 150, c(255, 0, 0))
})

test_that("a mark clips at the edge of a scrolling overflow ancestor", {
  skip_if_not_installed("png")
  page <- annotation_page()
  pz_js(
    page,
    paste0(
      "document.body.insertAdjacentHTML('beforeend', ",
      "'<div id=markclip style=\"position:absolute;left:350px;top:100px;width:160px;height:100px;overflow:auto;background:white\">' +",
      "'<div style=\"height:70px\"></div><div id=marked style=\"margin-left:20px;width:90px;height:80px\"></div>' +",
      "'<div style=\"height:300px\"></div></div>')"
    )
  )
  page |> pz_annotate("#marked", reveal = "none", color = "rgb(255, 0, 0)")
  path <- withr::local_tempfile(fileext = ".png")
  pixel <- function(x, y) {
    page |> pz_screenshot(path)
    img <- png::readPNG(path)
    dpr <- page_dpr(page)
    as.numeric(img[round(y * dpr) + 1, round(x * dpr) + 1, 1:3])
  }
  # The mark's left edge spans y 170..250; its container ends at y 200.
  expect_equal(pixel(371, 180), c(1, 0, 0), tolerance = 0.05)
  expect_equal(pixel(371, 205), c(1, 1, 1), tolerance = 0.03)
  pz_js(page, "document.getElementById('markclip').scrollTop = 250")
  pz_poll(
    function() isFALSE(annotation_state(page)[[1]]$visible),
    timeout = 5,
    loop = page$child_loop,
    what = "the mark to hide when scrolled out of its clip"
  )
  expect_false(annotation_state(page)[[1]]$visible)
  expect_equal(pixel(371, 110), c(1, 1, 1), tolerance = 0.03)
})

test_that("non-clipping inline and root body overflow do not hide redactions", {
  skip_if_not_installed("png")
  page <- annotation_page()
  pz_js(
    page,
    paste0(
      "document.body.style.overflow = 'hidden'; document.body.style.height = '60px';",
      "document.getElementById('fixed').innerHTML = '<span style=\"overflow:hidden\"><span id=inline-secret style=\"display:inline-block;width:50px;height:30px\">SECRET</span></span>';",
      "document.body.insertAdjacentHTML('beforeend', ",
      "'<div id=body-secret style=\"position:absolute;left:500px;top:310px;width:50px;height:30px;background:#ff0000\">SECRET</div>')"
    )
  )
  path <- withr::local_tempfile(fileext = ".png")
  page |> pz_screenshot(path)
  dpr <- page_dpr(page)
  expect_equal(
    as.numeric(png::readPNG(path)[
      round(335 * dpr) + 1,
      round(540 * dpr) + 1,
      1:3
    ]),
    c(1, 0, 0),
    tolerance = 0.03
  )
  page |> pz_annotate_redact("#inline-secret, #body-secret")
  page |> pz_screenshot(path)
  img <- png::readPNG(path)
  expect_equal(
    as.numeric(img[round(30 * dpr) + 1, round(40 * dpr) + 1, 1:3]),
    rep(23 / 255, 3),
    tolerance = 0.03
  )
  expect_equal(
    as.numeric(img[round(320 * dpr) + 1, round(510 * dpr) + 1, 1:3]),
    rep(23 / 255, 3),
    tolerance = 0.03
  )
})

test_that("redaction follows scroll and scoped targets without restyling elements", {
  page <- annotation_page()
  scoped <- pz_find(page, "#outer")
  scoped |> pz_annotate_redact("#inner", id = "inner")
  page |> pz_annotate_redact("#fixed", id = "fixed")
  rects <- function() {
    pz_js(
      page,
      "[...document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelectorAll('.pz-redaction')].map(n => [parseFloat(n.style.top), parseFloat(n.style.left)])"
    )
  }
  before <- rects()
  expect_identical(
    pz_js(page, "document.getElementById('inner').style.backgroundColor"),
    ""
  )
  pz_js(
    page,
    "window.scrollTo(0, 80); document.getElementById('outer').scrollTop = 30"
  )
  pz_poll(
    function() {
      now <- rects()
      # One scroll handler updates both redactions in the same tick; the
      # fixed one never moves, so anchor on the inner one having moved.
      length(now) == 2L &&
        abs(
          as.numeric(now[[1]][[1]]) -
            as.numeric(before[[1]][[1]])
        ) >
          2 &&
        abs(as.numeric(now[[2]][[1]]) - as.numeric(before[[2]][[1]])) < 2
    },
    timeout = 5,
    loop = page$child_loop,
    what = "the rects to track the scroll"
  )
  after <- rects()
  expect_equal(
    as.numeric(after[[1]][[1]]),
    as.numeric(before[[1]][[1]]) - 110,
    tolerance = 2
  )
  expect_equal(
    as.numeric(after[[2]][[1]]),
    as.numeric(before[[2]][[1]]),
    tolerance = 2
  )
  page |> pz_annotate_clear()
})

test_that("redaction uses the current scope and anonymous ids", {
  page <- annotation_page()
  scoped <- pz_find(page, "#outer")
  scoped |> pz_annotate_redact()
  expect_equal(
    pz_js(
      page,
      "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelectorAll('.pz-redaction').length"
    ),
    1
  )
  expect_equal(
    as.numeric(unlist(pz_js(
      page,
      "(() => { const n = document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-redaction'); return [parseFloat(n.style.left), parseFloat(n.style.top), parseFloat(n.style.width), parseFloat(n.style.height)]; })()"
    ))),
    as.numeric(unlist(pz_js(
      page,
      "(() => { const r = document.querySelector('#outer').getBoundingClientRect(); return [r.left, r.top, r.width, r.height]; })()"
    ))),
    tolerance = 1
  )
  page |> pz_annotate_redact()
  expect_equal(
    pz_js(
      page,
      "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelectorAll('.pz-redaction').length"
    ),
    2
  )
  page |> pz_annotate_clear()
  expect_equal(
    pz_js(
      page,
      "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelectorAll('.pz-redaction').length"
    ),
    0
  )
  pz_find(page, "#fixed, #box") |> pz_annotate_redact()
  expect_equal(
    pz_js(
      page,
      "[...document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelectorAll('.pz-redaction')].map(n => [parseFloat(n.style.left), parseFloat(n.style.top), parseFloat(n.style.width), parseFloat(n.style.height)]).sort((a, b) => a[1] - b[1])"
    ),
    pz_js(
      page,
      "['#fixed', '#box'].map(s => { const r = document.querySelector(s).getBoundingClientRect(); return [r.left, r.top, r.width, r.height]; })"
    ),
    tolerance = 1
  )
  page |> pz_annotate_clear()
})

test_that("redaction shares ids, stays above later marks, and rejects unsafe starts", {
  skip_if_not_installed("png")
  page <- annotation_page()
  page |> pz_annotate("#box", id = "shared", reveal = "none")
  page |>
    pz_annotate_redact("#box", id = "shared", color = "rgba(255, 0, 0, 0.5)")
  expect_length(annotation_state(page), 0)
  expect_equal(
    pz_js(
      page,
      "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelectorAll('.pz-redaction').length"
    ),
    1
  )
  page |> pz_annotate("#box", id = "mark", reveal = "none", color = "#00ff00")
  path <- withr::local_tempfile(fileext = ".png")
  page |> pz_screenshot(path)
  img <- png::readPNG(path)
  dpr <- page_dpr(page)
  rgb <- function(x, y) {
    as.numeric(img[round(y * dpr) + 1, round(x * dpr) + 1, 1:3])
  }
  expect_equal(
    rgb(225, 311),
    c(139 / 255, 11.5 / 255, 11.5 / 255),
    tolerance = 0.06
  )
  expect_equal(
    rgb(225, 330),
    c(139 / 255, 11.5 / 255, 11.5 / 255),
    tolerance = 0.06
  )
  page |> pz_annotate_redact("#fixed", id = "other", color = "not-a-color")
  page |> pz_screenshot(path)
  img <- png::readPNG(path)
  expect_equal(rgb(45, 35), rep(23 / 255, 3), tolerance = 0.03)
  pz_js(page, "document.getElementById('fixed').style.display = 'none'")
  pz_poll(
    function() {
      page |> pz_screenshot(path)
      img <<- png::readPNG(path)
      isTRUE(all.equal(rgb(45, 35), rep(1, 3), tolerance = 0.03))
    },
    timeout = 5,
    loop = page$child_loop,
    what = "the hidden target's redaction to stop painting"
  )
  page |> pz_screenshot(path)
  img <- png::readPNG(path)
  expect_equal(rgb(45, 35), rep(1, 3), tolerance = 0.03)
  expect_error(
    pz_annotate_redact(page, "#fixed", id = "shared"),
    "rendered box"
  )
  expect_equal(
    pz_js(
      page,
      "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelectorAll('.pz-redaction').length"
    ),
    2
  )
  expect_error(
    pz_annotate_redact(page, "#box", method = "blur", color = "red"),
    "color"
  )
  expect_error(pz_annotate_redact(page, "#box", method = "pixelate"))
  expect_error(pz_annotate_redact(page, "#box", id = "caption"))
  page |> pz_annotate_clear("shared")
  expect_equal(
    pz_js(
      page,
      "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelectorAll('.pz-redaction').length"
    ),
    1
  )
  page |> pz_annotate_clear()
  expect_equal(
    pz_js(
      page,
      "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelectorAll('.pz-redaction').length"
    ),
    0
  )
})

test_that("modal content cannot replace an existing redaction", {
  page <- annotation_page()
  page |> pz_annotate_redact("#box", id = "secret")
  pz_js(
    page,
    "document.body.insertAdjacentHTML('beforeend', '<dialog id=modal><div id=modal-secret>SECRET</div></dialog>'); document.getElementById('modal').showModal()"
  )
  expect_error(
    pz_annotate_redact(page, "#modal-secret", id = "secret"),
    "modal dialog or popover"
  )
  survivor <- pz_js(
    page,
    "(() => { const n = document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-redaction'); return [n.style.left, n.style.top, n.style.width, n.style.height]; })()"
  )
  expect_equal(unlist(survivor), c("200px", "310px", "100px", "50px"))
})

test_that("zero-height overflowing content cannot replace an existing redaction", {
  page <- annotation_page()
  page |> pz_annotate_redact("#box", id = "secret")
  pz_js(
    page,
    "document.body.insertAdjacentHTML('beforeend', '<div id=zero style=\"position:absolute;left:120px;top:160px;width:100px;height:0;overflow:visible\">SECRET</div>')"
  )
  expect_error(
    pz_annotate_redact(page, "#zero", id = "secret"),
    "nonzero width and height"
  )
  survivor <- pz_js(
    page,
    "(() => { const n = document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-redaction'); return [n.style.left, n.style.top, n.style.width, n.style.height]; })()"
  )
  expect_equal(unlist(survivor), c("200px", "310px", "100px", "50px"))
})

test_that("below-fold redaction covers a target-framed still without scrolling", {
  skip_if_not_installed("png")
  page <- annotation_page()
  pz_js(
    page,
    "document.body.insertAdjacentHTML('beforeend', '<div id=far style=\"position:absolute;left:120px;top:1500px;width:180px;height:90px;background:white;color:black\">SECRET</div>')"
  )
  expect_equal(pz_js(page, "window.scrollY"), 0)
  page |> pz_annotate_redact("#far")
  expect_equal(pz_js(page, "window.scrollY"), 0)
  path <- withr::local_tempfile(fileext = ".png")
  page |> pz_screenshot(path, frame = "#far")
  expect_equal(pz_js(page, "window.scrollY"), 0)
  img <- png::readPNG(path)
  expect_equal(mean(img[,, 1:3]), 23 / 255, tolerance = 0.025)
})

test_that("blur changes text pixels and hides when target stops rendering", {
  skip_if_not_installed("png")
  page <- annotation_page()
  pz_js(
    page,
    "document.body.insertAdjacentHTML('beforeend', '<div id=secret style=\"position:absolute;left:110px;top:410px;width:400px;height:120px;background:white;color:black;font:56px monospace\">SECRET</div>')"
  )
  before <- withr::local_tempfile(fileext = ".png")
  after <- withr::local_tempfile(fileext = ".png")
  page |> pz_screenshot(before)
  page |> pz_annotate_redact("#secret", method = "blur", id = "blur")
  expect_identical(
    pz_js(
      page,
      "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-redaction').style.backdropFilter"
    ),
    "blur(32px)"
  )
  page |> pz_screenshot(after)
  dpr <- page_dpr(page)
  rows <- (440:460) * dpr + 1
  cols <- (130:360) * dpr + 1
  sharp <- png::readPNG(before)[rows, cols, 1]
  soft <- png::readPNG(after)[rows, cols, 1]
  expect_gt(mean(abs(sharp - soft)), 0.05)
  pz_js(page, "document.getElementById('secret').style.display = 'none'")
  pz_poll(
    function() {
      identical(
        pz_js(
          page,
          "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-redaction').style.display"
        ),
        "none"
      )
    },
    timeout = 5,
    loop = page$child_loop,
    what = "the hidden target's redaction to hide"
  )
  expect_identical(
    pz_js(
      page,
      "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-redaction').style.display"
    ),
    "none"
  )
  pz_js(
    page,
    "document.getElementById('secret').style.display = ''; document.getElementById('secret').style.visibility = 'hidden'"
  )
  # The display is "none" before and after: this is a negative assertion over
  # an observation window (the recompute must not unhide), which a poll on the
  # display value cannot express.
  pump_loop(page$child_loop, 0.05)
  expect_identical(
    pz_js(
      page,
      "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-redaction').style.display"
    ),
    "none"
  )
  pz_js(page, "document.getElementById('secret').style.visibility = 'visible'")
  pz_poll(
    function() {
      identical(
        pz_js(
          page,
          "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-redaction').style.display"
        ),
        ""
      )
    },
    timeout = 5,
    loop = page$child_loop,
    what = "the restored target's redaction to reappear"
  )
  expect_identical(
    pz_js(
      page,
      "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-redaction').style.display"
    ),
    ""
  )
  pz_js(
    page,
    "document.getElementById('secret').innerHTML = '<span style=\"visibility:visible\">SECRET</span>'; document.getElementById('secret').style.visibility = 'hidden'"
  )
  pump_loop(page$child_loop, 0.05)
  expect_identical(
    pz_js(
      page,
      "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-redaction').style.display"
    ),
    ""
  )
})

test_that("poll captures started after redaction returns are covered", {
  skip_if_no_av()
  skip_if_not_installed("png")
  page <- annotation_page()
  path <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(path, fps = 12, hold = c(0, 0), keep_frames = TRUE)
  defer_record_stop(page)
  page |> pz_annotate_redact("#box", id = "secret")
  pending <- page_recorder(page)$pending
  deadline <- Sys.time() + 2
  while (
    identical(page_recorder(page)$pending, pending) &&
      !is.null(pending) &&
      Sys.time() < deadline
  ) {
    pump_loop(page$child_loop, 0.02)
  }
  expect_false(
    identical(page_recorder(page)$pending, pending) && !is.null(pending)
  )
  before <- length(page_recorder(page)$files)
  pz_poll(
    function() length(page_recorder(page)$files) > before,
    timeout = 5,
    loop = page$child_loop,
    what = "a capture started after the redaction"
  )
  captured <- page_recorder(page)$files
  dpr <- page_dpr(page)
  redacted <- vapply(
    captured[-seq_len(before)],
    function(file) {
      png::readPNG(file)[round(330 * dpr) + 1, round(225 * dpr) + 1, 1]
    },
    0.0
  )
  expect_true(all(abs(redacted - 23 / 255) < 0.04))
  page |> pz_annotate_clear("secret")
  expect_equal(
    pz_js(
      page,
      "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelectorAll('.pz-redaction').length"
    ),
    0
  )
  page |> pz_record_stop()
})

test_that("mark types and reveal styles are accepted and have type defaults", {
  page <- annotation_page()
  for (type in c("box", "circle", "underline", "highlight")) {
    page |> pz_annotate("#box", type = type, id = "mark", label = "A")
    expect_equal(annotation_state(page)[[1]]$label, "A")
    page |> pz_annotate_clear("mark")
  }
  for (reveal in c("draw", "pop", "slide", "wipe")) {
    page |> pz_annotate("#box", reveal = reveal, id = "mark")
    expect_length(annotation_state(page), 1)
    page |> pz_annotate_clear("mark")
  }
  expect_error(pz_annotate(page, "#box", type = "unknown"), "type")
  expect_error(pz_annotate(page, "#box", reveal = "unknown"), "reveal")
})

test_that("circle, underline, and highlight paint only their intended regions", {
  skip_if_not_installed("png")
  page <- annotation_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)
  pixel <- function(x, y) {
    image <- png::readPNG(path)
    as.numeric(image[round(y * dpr) + 1, round(x * dpr) + 1, 1:3])
  }
  page |> pz_annotate("#box", type = "circle", color = "#ff0000")
  page |> pz_screenshot(path)
  expect_lt(pixel(250, 311)[2], 0.15)
  expect_gt(pixel(250, 335)[2], 0.9)
  expect_gt(pixel(201, 311)[2], 0.9)
  page |> pz_annotate_clear()
  page |> pz_annotate("#box", type = "underline", color = "#ff0000", pad = 3)
  page |> pz_screenshot(path)
  expect_lt(pixel(250, 359)[2], 0.15)
  expect_gt(pixel(250, 308)[2], 0.9)
  expect_gt(pixel(250, 325)[2], 0.9)
  page |> pz_annotate_clear()
  pz_js(
    page,
    "document.getElementById('box').innerHTML = '<span style=\"font: bold 40px sans-serif;color:black\">IIII</span>'"
  )
  page |> pz_screenshot(path)
  unmarked <- png::readPNG(path)
  rows <- round((313:350) * dpr) + 1
  cols <- round((205:280) * dpr) + 1
  expect_lt(min(unmarked[rows, cols, 1]), 0.15)
  page |> pz_annotate("#box", type = "highlight", color = "#ff0000")
  page |> pz_screenshot(path)
  marked <- png::readPNG(path)
  expect_lt(min(marked[rows, cols, 1]), 0.4)
  expect_gt(max(marked[rows, cols, 1]) - min(marked[rows, cols, 1]), 0.5)
  expect_gt(pixel(250, 335)[1], 0.9)
  expect_lt(pixel(250, 335)[2], 0.8)
  expect_gt(pixel(250, 335)[2], 0.4)
  expect_gt(pixel(199, 335)[2], 0.9)
})

test_that("all reveals show sampled entry and reverse exit frames", {
  skip_if_not_installed("png")
  page <- annotation_page()
  page |>
    pz_annotate("#box", id = "boot", reveal = "none") |>
    pz_annotate_clear()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)
  sample <- function() {
    page |> pz_screenshot(path)
    image <- png::readPNG(path)
    image[round((308:363) * dpr) + 1, round((198:303) * dpr) + 1, 1:3]
  }
  for (reveal in c("fade", "draw", "pop", "slide", "wipe")) {
    pz_js(
      page,
      paste0(
        "(() => { const l=document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations');",
        "l.pz.draw([document.querySelector('#box')], {id:'test',type:'box',pad:[0,0,0,0],",
        "label:null,color:'#ff0000',strokeWidth:3,fontFamily:'sans-serif',fontSize:14,reveal:'",
        reveal,
        "',animate:true}); l.querySelector('.pz-annotation').getAnimations({subtree:true})[0].pause(); })()"
      )
    )
    entering <- lapply(c(0, 0.25, 0.5, 0.75, 1), function(fraction) {
      pz_js(
        page,
        paste0(
          "(() => { const a=document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotation').getAnimations({subtree:true})[0]; a.currentTime=",
          fraction,
          "*a.effect.getTiming().duration; })()"
        )
      )
      sample()
    })
    for (i in 2:4) {
      expect_gt(mean(abs(entering[[i]] - entering[[1]])), 0.001)
      expect_gt(mean(abs(entering[[i]] - entering[[5]])), 0.001)
    }
    pz_js(
      page,
      "(() => { const l=document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations'); window.__exitNode=l.querySelector('.pz-annotation'); l.pz.clear({id:'test',animate:true}); window.__exitNode.getAnimations({subtree:true})[0].pause(); })()"
    )
    leaving <- lapply(c(0, 0.25, 0.5, 0.75, 1), function(fraction) {
      pz_js(
        page,
        paste0(
          "(() => { const a=window.__exitNode.getAnimations({subtree:true})[0]; a.currentTime=",
          fraction,
          "*a.effect.getTiming().duration; })()"
        )
      )
      sample()
    })
    expect_lt(mean(abs(leaving[[1]] - entering[[5]])), 0.002)
    expect_lt(mean(abs(leaving[[5]] - entering[[1]])), 0.002)
    for (i in 2:4) {
      expect_gt(mean(abs(leaving[[i]] - leaving[[1]])), 0.001)
      expect_gt(mean(abs(leaving[[i]] - leaving[[5]])), 0.001)
    }
    pz_js(
      page,
      "window.__exitNode.remove()"
    )
    expect_length(annotation_state(page), 0)
  }
})

test_that("a recorded wipe becomes visible in captured frames and clears", {
  skip_if_no_av()
  skip_if_not_installed("png")
  page <- annotation_page()
  path <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(path, fps = 20, hold = c(0, 0), keep_frames = TRUE)
  defer_record_stop(page)
  page |> pz_annotate("#box", id = "wipe", reveal = "wipe", color = "#ff0000")
  dpr <- page_dpr(page)
  painted <- function(file) {
    img <- png::readPNG(file)
    region <- img[round((309:361) * dpr) + 1, round((199:301) * dpr) + 1, 1:3]
    sum(region[,, 1] > 0.9 & region[,, 2] < 0.35)
  }
  last_painted <- function() {
    files <- page_recorder(page)$files
    if (!length(files)) {
      return(NA_real_)
    }
    painted(tail(files, 1))
  }
  # Mid-animation pixels are covered by the controlled reveal tests.
  pz_poll(
    function() isTRUE(last_painted() > 100),
    timeout = 5,
    loop = page$child_loop,
    what = "a frame showing the wipe annotation"
  )
  page |> pz_annotate_clear("wipe")
  pz_poll(
    function() {
      isTRUE(last_painted() == 0) && length(annotation_state(page)) == 0
    },
    timeout = 5,
    loop = page$child_loop,
    what = "a settled frame of the reversed wipe"
  )
  expect_length(annotation_state(page), 0)
  page |> pz_record_stop()
  expect_true(file.exists(path))
})

test_that("draw leaves badge visible and removes it at start of reverse", {
  page <- annotation_page()
  page |>
    pz_annotate("#box", id = "boot", reveal = "none") |>
    pz_annotate_clear()
  pz_js(
    page,
    "(() => { const l=document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations'); l.pz.draw([document.querySelector('#box')], {id:'badge',type:'circle',pad:[0,0,0,0],label:'A',color:'red',strokeWidth:3,labelFill:'#171717',labelTextColor:'white',fontFamily:'sans-serif',fontSize:14,reveal:'draw',animate:true}); l.querySelector('.pz-annotation').getAnimations({subtree:true})[0].pause(); })()"
  )
  expect_equal(annotation_state(page)[[1]]$label, "A")
  pz_js(
    page,
    "(() => { const l=document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations'); window.__exitNode=l.querySelector('.pz-annotation'); l.pz.clear({id:'badge',animate:true}); window.__exitNode.getAnimations({subtree:true})[0].pause(); })()"
  )
  expect_equal(
    pz_js(
      page,
      "window.__exitNode.querySelector('span') === null"
    ),
    TRUE
  )
  pz_js(
    page,
    "window.__exitNode.remove()"
  )
})

test_that("default reveals animate entry and reverse clear during recording", {
  skip_if_no_av()
  page <- annotation_page()
  path <- withr::local_tempfile(fileext = ".mp4")
  pz_js(
    page,
    "window.__markAnimations = []; const originalAnimate = Element.prototype.animate; Element.prototype.animate = function(frames, options) { window.__markAnimations.push({frames, direction:options.direction, duration:options.duration}); return originalAnimate.call(this, frames, options); };"
  )
  page |> pz_record_start(path, fps = 10, hold = c(0, 0))
  defer_record_stop(page)
  for (type in c("box", "circle", "underline", "highlight")) {
    page |> pz_annotate("#box", type = type, id = "default")
    page |> pz_annotate_clear("default")
  }
  first <- pz_js(
    page,
    "window.__markAnimations.filter((_, i) => i % 2 === 0).map(animation => Object.keys(animation.frames[0]))"
  )
  expect_true("opacity" %in% first[[1]])
  expect_true("strokeDashoffset" %in% first[[2]])
  expect_true("transform" %in% first[[3]])
  expect_true("transform" %in% first[[4]])

  pz_js(page, "window.__markAnimations = []")
  page |>
    pz_annotate_spotlight("#box") |>
    pz_annotate_clear("spotlight") |>
    pz_annotate_callout("Tip", target = "#box", id = "tip") |>
    pz_annotate_clear("tip")
  animations <- pz_js(page, "window.__markAnimations")
  expect_length(animations, 4)
  expect_equal(
    vapply(animations, `[[`, character(1), "direction"),
    c("normal", "reverse", "normal", "reverse")
  )
  expect_true(all(vapply(animations, `[[`, numeric(1), "duration") > 0))
  expect_equal(names(animations[[1]]$frames[[1]]), "opacity")
  expect_equal(
    names(animations[[3]]$frames[[1]]),
    c("opacity", "transform")
  )
  page |> pz_record_stop()
})

test_that("clear returns the longest active exit duration", {
  page <- annotation_page()
  page |>
    pz_annotate("#box", id = "boot", reveal = "none") |>
    pz_annotate_clear()
  durations <- pz_js(
    page,
    "(() => { const l=document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations'); const el=document.querySelector('#box'); const o={type:'box',pad:[0,0,0,0],label:null,color:'red',strokeWidth:3,fontFamily:'sans-serif',fontSize:14,animate:true}; const short=l.pz.draw([el], {...o,id:'short',reveal:'fade'}); const long=l.pz.draw([el], {...o,id:'long',reveal:'wipe'}); const clear=l.pz.clear({id:null,animate:true}); [...l.children].forEach(n=>n.remove()); return [short,long,clear,l.pz.clear({id:null,animate:true})]; })()"
  )
  expect_equal(unlist(durations), c(250, 400, 400, 0))
})

test_that("a labeled wipe reveals the badge before its shape finishes", {
  skip_if_not_installed("png")
  page <- annotation_page()
  page |>
    pz_annotate("#box", id = "boot", reveal = "none") |>
    pz_annotate_clear()
  pz_js(
    page,
    "(() => { const l=document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations'); l.pz.draw([document.querySelector('#box')], {id:'labeled',type:'box',pad:[0,0,0,0],label:'A',color:'#ff0000',strokeWidth:3,labelFill:'#171717',labelTextColor:'white',fontFamily:'sans-serif',fontSize:14,reveal:'wipe',animate:true}); const a=l.querySelector('.pz-annotation').getAnimations({subtree:true})[0]; a.pause(); a.currentTime=200; })()"
  )
  path <- withr::local_tempfile(fileext = ".png")
  page |> pz_screenshot(path)
  img <- png::readPNG(path)
  dpr <- page_dpr(page)
  pixel <- function(x, y) {
    as.numeric(img[round(y * dpr) + 1, round(x * dpr) + 1, 1:3])
  }
  expect_lt(pixel(202, 300)[2], 0.2)
  expect_lt(pixel(275, 311)[2], 0.2)
  expect_gt(pixel(225, 311)[2], 0.9)
  pz_js(
    page,
    "(() => { const l=document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations'); window.__exitNode=l.querySelector('.pz-annotation'); return l.pz.clear({id:'labeled',animate:true}); })()"
  )
  expect_true(pz_js(
    page,
    "window.__exitNode.querySelector('span') === null"
  ))
  pz_js(
    page,
    "window.__exitNode.remove()"
  )
})

test_that("a drawn box has the same rounded outline as a still box", {
  page <- annotation_page()
  page |> pz_annotate("#box", type = "box", reveal = "draw")
  radius <- pz_js(
    page,
    "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotation svg rect')?.getAttribute('rx')"
  )
  expect_equal(as.numeric(radius), 3.5)
})


test_that("anonymous kinds coexist across shared-id replacement and clear", {
  page <- annotation_page()
  layer_counts <- function() {
    pz_js(
      page,
      paste0(
        "(() => { const l = document.getElementById('paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations'); ",
        "return ['pz-annotation','pz-callout','pz-redaction'].map(c => l.getElementsByClassName(c).length); })()"
      )
    )
  }
  page |> pz_annotate("#box", reveal = "none")
  page |> pz_annotate_callout("note", target = "#fixed", reveal = "none")
  page |> pz_annotate_redact("#inner")
  expect_equal(unlist(layer_counts()), c(1, 1, 1))
  page |> pz_annotate("#fixed", id = "shared", reveal = "none")
  page |>
    pz_annotate_callout(
      "replacement",
      target = "#box",
      id = "shared",
      reveal = "none"
    )
  expect_equal(unlist(layer_counts()), c(1, 2, 1))
  page |> pz_annotate_clear("shared")
  expect_equal(unlist(layer_counts()), c(1, 1, 1))
  page |> pz_annotate("#fixed", id = "__pz_auto_4", reveal = "none")
  page |> pz_annotate("#fixed", reveal = "none")
  page |> pz_annotate_clear("__pz_auto_4")
  expect_equal(unlist(layer_counts()), c(2, 1, 1))
  page |> pz_annotate_redact("#fixed", id = "shared")
  page |> pz_annotate("#box", id = "shared", reveal = "none")
  expect_equal(unlist(layer_counts()), c(3, 1, 1))
  page |> pz_annotate_clear()
  expect_equal(unlist(layer_counts()), c(0, 0, 0))
  expect_equal(
    pz_js(
      page,
      "document.getElementById('paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations').children.length"
    ),
    0
  )
})

test_that("overlay function sources parse in Chrome", {
  page <- local_page()
  parse_js <- function(source) {
    pz_js(
      page,
      paste0(
        "new Function('return (' + ",
        jsonlite::toJSON(source, auto_unbox = TRUE),
        " + ');'); true"
      )
    )
  }
  boot <- if (is.function(annotate_boot_js)) {
    annotate_boot_js()
  } else {
    annotate_boot_js
  }
  if (is.function(annotate_boot_js)) {
    source <- paste(
      readLines(
        system.file(
          "js",
          "annotate.js",
          package = "paparazzi",
          mustWork = TRUE
        ),
        warn = FALSE
      ),
      collapse = "\n"
    )
    expect_true(parse_js(source))
  }
  expect_true(parse_js(boot))
  expect_true(parse_js(cursor_command_js))
  expect_true(parse_js(
    if (grepl("const data = %s", overlay_draw_js, fixed = TRUE)) {
      sub("%s", "null", overlay_draw_js, fixed = TRUE)
    } else {
      overlay_draw_js
    }
  ))
  expect_error(system.file(
    "js",
    "annotate-missing.js",
    package = "paparazzi",
    mustWork = TRUE
  ))
  expect_error(parse_js("function( {"))
})

test_that("mark and redact padding rejects NULL", {
  page <- annotation_page()
  expect_error(pz_annotate(page, "#box", pad = NULL), "pad.*NULL")
  expect_error(pz_annotate_redact(page, "#box", pad = NULL), "pad.*NULL")
  expect_error(pz_annotate(page, "#box", reveal = NULL), "reveal")
})

test_that("auto reveals preserve the type defaults and zero padding", {
  page <- annotation_page()
  local_mocked_bindings(annotate_call = function(ctx, els, fn, options, what) {
    captured <<- options
  })
  captured <- NULL
  for (type in c("box", "circle", "underline", "highlight")) {
    pz_annotate(page, "#box", type = type)
    omitted <- captured
    pz_annotate(page, "#box", type = type, reveal = "auto", pad = 0)
    expect_identical(captured, omitted)
    expect_equal(captured$pad, rep(0, 4))
    expect_identical(captured$reveal, if (type == "box") "fade" else "draw")
  }
  pz_annotate_redact(page, "#box")
  omitted <- captured
  pz_annotate_redact(page, "#box", pad = 0)
  expect_identical(captured, omitted)
  expect_equal(captured$pad, rep(0, 4))
})

test_that("mark badges follow their mark unless overridden per call", {
  page <- annotation_page()
  badge_style <- function() {
    pz_js(
      page,
      "(() => { const s = getComputedStyle(document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotation span')); return [s.backgroundColor, s.color]; })()"
    )
  }
  page |> pz_annotate("#box", label = "A", reveal = "none", id = "mark")
  expect_equal(
    unlist(badge_style()),
    c("rgb(225, 29, 72)", "rgb(255, 255, 255)")
  )

  page |>
    pz_stage_annotate(color = "#16a34a") |>
    pz_annotate("#box", label = "A", reveal = "none", id = "mark")
  expect_equal(
    unlist(badge_style()),
    c("rgb(22, 163, 74)", "rgb(255, 255, 255)")
  )

  # Staged fill/text_color style callout chrome only, never mark badges.
  page |>
    pz_stage_annotate(fill = "#fef3c7", text_color = "#1c1917") |>
    pz_annotate("#box", label = "A", reveal = "none", id = "mark")
  expect_equal(
    unlist(badge_style()),
    c("rgb(22, 163, 74)", "rgb(255, 255, 255)")
  )

  page |>
    pz_annotate(
      "#box",
      label = "A",
      reveal = "none",
      id = "mark",
      label_fill = "#dbeafe",
      label_text_color = "#172554"
    )
  expect_equal(
    unlist(badge_style()),
    c("rgb(219, 234, 254)", "rgb(23, 37, 84)")
  )
  page |>
    pz_annotate_clear() |>
    pz_stage_annotate(color = NULL, fill = NULL, text_color = NULL)
})

test_that("mark badges size to their label, not their mark", {
  page <- annotation_page()
  badge_box <- function() {
    pz_js(
      page,
      "(() => { const r = document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotation span').getBoundingClientRect(); return [r.width, r.height]; })()"
    )
  }
  page |> pz_annotate("#fixed", label = "A", reveal = "none", id = "mark")
  one_line <- badge_box()[[2]]

  page |>
    pz_annotate(
      "#fixed",
      label = "#add-task-button",
      reveal = "none",
      id = "mark"
    )
  box <- badge_box()
  expect_gt(box[[1]], 90)
  expect_equal(box[[2]], one_line)

  long <- paste(rep("word", 30), collapse = " ")
  page |> pz_annotate("#fixed", label = long, reveal = "none", id = "mark")
  box <- badge_box()
  expect_lte(box[[1]], 20 * 14 + 10)
  expect_gt(box[[2]], one_line)
  page |> pz_annotate_clear()
})

test_that("marks validate label_fill, label_text_color and stroke_width", {
  page <- annotation_page()
  expect_error(
    pz_annotate(page, "#box", label = "A", label_fill = ""),
    "label_fill.*empty string"
  )
  expect_error(
    pz_annotate(page, "#box", label = "A", label_text_color = ""),
    "label_text_color.*empty string"
  )
  expect_error(pz_annotate(page, "#box", stroke_width = 0), "stroke_width")
  expect_error(pz_annotate(page, "#box", stroke_width = -1), "stroke_width")
})

test_that("stroke_width reaches mark shapes and is stageable", {
  page <- annotation_page()
  page |>
    pz_annotate("#box", type = "box", reveal = "none", id = "mark")
  # The declared width: computed border widths snap to device pixels, so
  # a fractional default reads back rounded at a device pixel ratio of 1.
  default_border <- pz_js(
    page,
    "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotation .pz-shape').style.borderTopWidth"
  )
  page |>
    pz_annotate(
      "#box",
      type = "box",
      reveal = "none",
      id = "mark",
      stroke_width = 6
    )
  expect_identical(
    pz_js(
      page,
      "getComputedStyle(document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotation .pz-shape')).borderTopWidth"
    ),
    "6px"
  )
  page |>
    pz_annotate(
      "#box",
      type = "circle",
      reveal = "none",
      id = "mark",
      stroke_width = 5
    )
  expect_equal(
    pz_js(
      page,
      "parseFloat(getComputedStyle(document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotation .pz-shape ellipse')).strokeWidth)"
    ),
    5
  )
  page |>
    pz_annotate(
      "#box",
      type = "underline",
      reveal = "none",
      id = "mark",
      stroke_width = 7
    )
  expect_identical(
    pz_js(
      page,
      "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotation .pz-shape').style.height"
    ),
    "7px"
  )
  page |>
    pz_stage_annotate(stroke_width = 2) |>
    pz_annotate("#box", type = "box", reveal = "none", id = "mark")
  expect_identical(
    pz_js(
      page,
      "getComputedStyle(document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotation .pz-shape')).borderTopWidth"
    ),
    "2px"
  )
  expect_identical(
    default_border,
    paste0(STAGE_DEFAULTS$annotate_stroke_width, "px")
  )
  page |> pz_annotate_clear() |> pz_stage_annotate(stroke_width = NULL)
})

annotation_badge_rects <- function(page) {
  pz_js(
    page,
    paste0(
      "(() => { const nodes = document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelectorAll('.pz-annotation');",
      "return [...nodes].map(n => { const badge = n.querySelector('span');",
      "const r = badge.getBoundingClientRect();",
      "const range = document.createRange(); range.selectNodeContents(badge);",
      "return {visible:n.style.display !== 'none',",
      "left:r.left,top:r.top,width:r.width,height:r.height,bottom:r.bottom,",
      "lines:range.getClientRects().length}; }); })()"
    )
  )
}

local_clipped_badge_page <- function(.env = parent.frame()) {
  page <- local_page(.env = .env)
  pz_js(
    page,
    paste0(
      "document.body.style.background = 'white';",
      "document.body.innerHTML = '<div id=horizontal style=\"position:absolute;left:100px;top:100px;width:100px;height:140px;overflow-x:hidden\">' +",
      "'<div id=vertical style=\"position:relative;left:-20px;top:20px;width:160px;height:70px;overflow-y:hidden\">' +",
      "'<div id=marked style=\"position:relative;top:-20px;width:110px;height:80px\"></div>' +",
      "'<div style=\"height:200px\"></div></div></div>';"
    )
  )
  page
}

test_that("the tasks Add badge stays on one line beyond its narrow button", {
  page <- local_page(
    pz_example("tasks"),
    color_scheme = "light",
    width = 1000,
    height = 720
  )
  page |>
    pz_annotate(
      "#add-task",
      label = "A",
      pad = 2,
      font_family = "monospace",
      id = "add"
    )
  one_line <- annotation_badge_rects(page)[[1]]$height
  page |>
    pz_annotate(
      "#add-task",
      label = "#add-task",
      pad = 2,
      font_family = "monospace",
      label_fill = "#ff00ff",
      id = "add"
    )
  path <- withr::local_tempfile(fileext = ".png")
  page |> pz_screenshot(path)
  badge <- annotation_badge_rects(page)[[1]]
  target <- pz_get_rect(page, "#add-task")
  expect_equal(badge$height, one_line)
  expect_equal(badge$lines, 1)
  expect_gt(badge$width, target$width)
  expect_gt(badge$left + badge$width - 2, target$x + target$width)
  expect_png_pixel(
    page,
    path,
    badge$left + badge$width - 2,
    badge$top + badge$height / 2,
    c(255, 0, 255)
  )
})

test_that("task title badges paint outside overflow wrappers in annotated crops", {
  page <- local_page(
    pz_example("tasks"),
    color_scheme = "light",
    width = 1000,
    height = 720
  )
  page |>
    pz_annotate(
      ".task-title",
      label = ".task-title",
      font_family = "monospace",
      label_fill = "#ff00ff"
    )
  spec <- pz_frame(list("h1", ".task-list"), pad = 24, target_box = "annotated")
  clip <- frame_clip(page, frame_effective(page, spec))
  path <- withr::local_tempfile(fileext = ".png")
  page |> pz_screenshot(path, frame = spec)
  badges <- annotation_badge_rects(page)
  titles <- pz_get_rect(page, ".task-title")
  visible <- vapply(badges, `[[`, TRUE, "visible")
  expect_gt(sum(visible), 0)
  expect_gt(sum(!visible), 0)
  expect_length(badges, nrow(titles))
  size <- png_dimensions(path) / page_dpr(page)
  for (i in which(visible)) {
    badge <- badges[[i]]
    expect_equal(badge$bottom, titles$y[i], tolerance = 0.1)
    point <- c(badge$left + 2 - clip$x, badge$top + badge$height / 2 - clip$y)
    expect_true(all(point >= 0 & point < size))
    expect_png_pixel(page, path, point[1], point[2], c(255, 0, 255))
  }
  # Hidden owners must not leak their badges back into the document.
  expect_true(all(vapply(badges[!visible], function(b) b$width == 0, TRUE)))
})

test_that("nested overflow clips shapes but anchors badges to the visible mark", {
  page <- local_clipped_badge_page()
  path <- withr::local_tempfile(fileext = ".png")
  for (type in c("box", "circle", "underline", "highlight")) {
    page |>
      pz_annotate(
        "#marked",
        type = type,
        label = "A",
        pad = 4,
        color = "red",
        label_fill = "#ff00ff",
        reveal = "none",
        id = "mark"
      ) |>
      pz_screenshot(path)
    badge <- annotation_badge_rects(page)[[1]]
    expect_equal(c(badge$left, badge$bottom), c(100, 120), tolerance = 0.1)
    expect_png_pixel(page, path, 102, 110, c(255, 0, 255))
    expect_png_pixel(page, path, 96, 150, rep(255, 3))
    expect_png_pixel(page, path, 150, 110, rep(255, 3))
    point <- switch(
      type,
      box = c(192, 150),
      circle = c(192, 140),
      underline = c(150, 180),
      highlight = c(150, 150)
    )
    expect_png_pixel(
      page,
      path,
      point[1],
      point[2],
      if (type == "highlight") c(255, 166, 166) else c(255, 0, 0)
    )
    pz_js(page, "document.getElementById('vertical').scrollTop = 30")
    pz_poll(
      function() abs(annotation_state(page)[[1]]$rect[[2]] - 66) < 0.1,
      timeout = 5,
      loop = page$child_loop,
      what = "the mark to follow the nested container scroll"
    )
    badge <- annotation_badge_rects(page)[[1]]
    expect_equal(c(badge$left, badge$bottom), c(100, 120), tolerance = 0.1)
    page |> pz_screenshot(path)
    expect_png_pixel(page, path, 102, 110, c(255, 0, 255))
    pz_js(page, "document.getElementById('vertical').scrollTop = 150")
    pz_poll(
      function() !annotation_badge_rects(page)[[1]]$visible,
      timeout = 5,
      loop = page$child_loop,
      what = "the fully clipped mark and badge to hide"
    )
    page |> pz_screenshot(path)
    expect_png_pixel(page, path, 102, 110, rep(255, 3))
    pz_js(page, "document.getElementById('vertical').scrollTop = 0")
    pz_poll(
      function() {
        state <- annotation_state(page)[[1]]
        state$visible && abs(state$rect[[2]] - 96) < 0.1
      },
      timeout = 5,
      loop = page$child_loop,
      what = "the mark to return to its unscrolled position"
    )
    pz_js(page, "document.getElementById('marked').style.display = 'none'")
    pz_poll(
      function() !annotation_badge_rects(page)[[1]]$visible,
      timeout = 5,
      loop = page$child_loop,
      what = "the non-rendered mark and badge to hide"
    )
    pz_js(page, "document.getElementById('marked').style.display = ''")
    pz_poll(
      function() annotation_badge_rects(page)[[1]]$visible,
      timeout = 5,
      loop = page$child_loop,
      what = "the restored mark and badge to reappear"
    )
    page |> pz_annotate_clear("mark")
    expect_length(annotation_state(page), 0)
    expect_equal(
      pz_js(
        page,
        "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations').children.length"
      ),
      0
    )
  }
})

test_that("a clipped recorded badge paints in retained frames and clears", {
  skip_if_no_av()
  skip_if_not_installed("png")
  page <- local_clipped_badge_page()
  path <- withr::local_tempfile(fileext = ".mp4")
  page |>
    pz_record_start(
      path,
      method = "poll",
      fps = 12,
      hold = c(0, 0),
      keep_frames = TRUE
    )
  rec <- page_recorder(page)
  withr::defer(unlink(rec$frames_dir, recursive = TRUE))
  defer_record_stop(page)
  dpr <- page_dpr(page)
  last_badge <- function() {
    if (!length(rec$files)) {
      return(rep(NA_real_, 3))
    }
    png::readPNG(tail(rec$files, 1))[
      round(110 * dpr) + 1,
      round(102 * dpr) + 1,
      1:3
    ]
  }
  page |>
    pz_annotate(
      "#marked",
      label = "A",
      pad = 4,
      label_fill = "#ff00ff",
      reveal = "fade",
      id = "mark"
    )
  pz_poll(
    function() isTRUE(all(abs(last_badge() - c(1, 0, 1)) < 0.03)),
    timeout = 5,
    loop = page$child_loop,
    what = "a retained frame containing the clipped target's badge"
  )
  page |> pz_annotate_clear("mark")
  pz_poll(
    function() isTRUE(all(abs(last_badge() - 1) < 0.03)),
    timeout = 5,
    loop = page$child_loop,
    what = "a retained frame without the cleared badge"
  )
  expect_length(annotation_state(page), 0)
  page |> pz_record_stop()
})

test_that("clipped badges retain reveal, reverse exit, and replacement semantics", {
  page <- local_clipped_badge_page()
  page |>
    pz_annotate("#marked", reveal = "none", id = "boot") |>
    pz_annotate_clear()
  path <- withr::local_tempfile(fileext = ".png")
  for (reveal in c("fade", "draw", "pop", "slide", "wipe")) {
    pz_js(
      page,
      paste0(
        "(() => { const l=document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations');",
        "l.pz.draw([document.querySelector('#marked')], {id:'mark',type:'box',pad:[4,4,4,4],",
        "label:'A',color:'red',strokeWidth:3,labelFill:'#ff00ff',labelTextColor:'white',fontFamily:'sans-serif',fontSize:14,",
        "reveal:'",
        reveal,
        "',animate:true}); const a=l.querySelector('.pz-annotation').getAnimations({subtree:true})[0];",
        "a.pause(); a.currentTime=",
        if (reveal %in% c("draw", "wipe")) "0.5" else "1",
        "*a.effect.getTiming().duration; })()"
      )
    )
    page |> pz_screenshot(path)
    expect_png_pixel(page, path, 102, 110, c(255, 0, 255))
    pz_js(
      page,
      paste0(
        "(() => { const l=document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations');",
        "window.__exitNode=l.querySelector('.pz-annotation'); l.pz.clear({id:'mark',animate:true});",
        "const a=window.__exitNode.getAnimations({subtree:true})[0]; a.pause(); a.currentTime=0; })()"
      )
    )
    has_badge <- pz_js(page, "window.__exitNode.querySelector('span') !== null")
    expect_identical(has_badge, !reveal %in% c("draw", "wipe"))
    page |> pz_screenshot(path)
    expect_png_pixel(
      page,
      path,
      102,
      110,
      if (has_badge) c(255, 0, 255) else rep(255, 3)
    )
    pz_js(
      page,
      "window.__exitNode.getAnimations({subtree:true})[0].finish()"
    )
    pz_poll(
      function() {
        pz_js(
          page,
          "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations').children.length"
        ) ==
          0
      },
      timeout = 5,
      loop = page$child_loop,
      what = "the completed reverse animation to remove its mark and badge"
    )
  }
  page |> pz_annotate("#marked", label = "Old", id = "mark")
  page |> pz_annotate("#marked", label = "New", id = "mark")
  expect_length(annotation_badge_rects(page), 1)
  expect_identical(annotation_state(page)[[1]]$label, "New")
  page |> pz_annotate_clear()
  expect_length(annotation_state(page), 0)
})

local_viewport_badge_page <- function(
  width = 1000,
  height = 720,
  .env = parent.frame()
) {
  page <- local_page(width = width, height = height, .env = .env)
  pz_js(
    page,
    paste0(
      "document.body.style.cssText='margin:0;background:white';",
      "document.body.innerHTML='<div id=edge style=\"position:absolute;left:400px;top:250px;width:30px;height:30px\"></div>';"
    )
  )
  page
}

viewport_badge_reference <- function(page, label, pad = 0) {
  page |>
    pz_annotate(
      "#edge",
      label = label,
      pad = pad,
      label_fill = "#ff00ff",
      color = "red",
      font_family = "monospace",
      reveal = "none",
      id = "edge"
    )
  annotation_badge_rects(page)[[1]]
}

expect_viewport_badge <- function(page, path, x, y, reference) {
  viewport <- unlist(pz_js(
    page,
    "[document.documentElement.clientWidth,document.documentElement.clientHeight]"
  ))
  # Far-edge clamps move one Chromium layout unit inward; near edges pin to zero.
  if (x > 0 && x == viewport[1] - reference$width) {
    x <- max(0, x - 1 / 64)
  }
  if (y > 0 && y == viewport[2] - reference$height) {
    y <- max(0, y - 1 / 64)
  }
  badge <- annotation_badge_rects(page)[[1]]
  expect_equal(c(badge$left, badge$top), c(x, y), tolerance = 0.001)
  expect_equal(
    c(badge$width, badge$height),
    c(reference$width, reference$height)
  )
  expect_gte(badge$left, -1e-6)
  expect_gte(badge$top, -1e-6)
  expect_lte(badge$left + badge$width, viewport[1] + 1e-6)
  expect_lte(badge$bottom, viewport[2] + 1e-6)
  size <- png_dimensions(path) / page_dpr(page)
  # These points use the expected placement, not the potentially offscreen DOM.
  points <- rbind(
    c(x + 2, y + reference$height / 2),
    c(x + reference$width - 2, y + reference$height / 2)
  )
  expect_true(all(points >= 0 & sweep(points, 2, size, `<`)))
  for (i in seq_len(nrow(points))) {
    expect_png_pixel(page, path, points[i, 1], points[i, 2], c(255, 0, 255))
  }
  ink <- png_canvas_eval(
    page,
    path,
    paste0(
      "const p=c.getImageData(",
      round((x + 5) * page_dpr(page)),
      ",",
      round((y + 2) * page_dpr(page)),
      ",",
      max(1, floor((reference$width - 10) * page_dpr(page))),
      ",",
      max(1, floor((reference$height - 4) * page_dpr(page))),
      ").data; let ink=0,fill=0; for(let i=0;i<p.length;i+=4) {",
      "if(p[i]>240 && p[i+1]>240 && p[i+2]>240) ink++;",
      "if(p[i]>240 && p[i+1]<10 && p[i+2]>240) fill++; } return {ink,fill};"
    )
  )
  expect_gt(ink$ink, 0)
  expect_gt(ink$fill, 0)
}

test_that("right-edge badges translate without squeezing medium or 20em labels", {
  page <- local_viewport_badge_page()
  path <- withr::local_tempfile(fileext = ".png")
  for (label in c("#add-task", paste(rep("word", 15), collapse = " "))) {
    pz_js(page, "document.getElementById('edge').style.left='400px'")
    reference <- viewport_badge_reference(page, label)
    expect_gt(reference$width, 30)
    pz_js(page, "document.getElementById('edge').style.left='970px'")
    page |> pz_screenshot(path)
    expect_viewport_badge(
      page,
      path,
      1000 - reference$width,
      250 - reference$height,
      reference
    )
    expect_png_pixel(page, path, 985, 251, c(255, 0, 0))
  }
})

test_that("top and top-right badges move down while retaining their label size", {
  page <- local_viewport_badge_page()
  path <- withr::local_tempfile(fileext = ".png")
  for (label in c("#add-task", paste(rep("word", 15), collapse = " "))) {
    for (pad in c(0, 4)) {
      pz_js(
        page,
        "document.getElementById('edge').style.left='400px'; document.getElementById('edge').style.top='250px'"
      )
      reference <- viewport_badge_reference(page, label, pad)
      pz_js(page, "document.getElementById('edge').style.top='0px'")
      page |> pz_screenshot(path)
      expect_viewport_badge(page, path, 400 - pad, 0, reference)
      pz_js(page, "document.getElementById('edge').style.left='970px'")
      page |> pz_screenshot(path)
      expect_viewport_badge(page, path, 1000 - reference$width, 0, reference)
    }
  }
})

test_that("left and bottom viewport edges use the same minimum translation", {
  page <- local_viewport_badge_page()
  path <- withr::local_tempfile(fileext = ".png")
  reference <- viewport_badge_reference(page, "#add-task", pad = 4)
  pz_js(page, "document.getElementById('edge').style.left='-6px'")
  page |> pz_screenshot(path)
  expect_viewport_badge(page, path, 0, 246 - reference$height, reference)

  pz_js(
    page,
    "document.getElementById('edge').style.left='400px'; document.getElementById('edge').style.top='250px'"
  )
  reference <- viewport_badge_reference(page, "A", pad = c(-40, 0, 50, 0))
  pz_js(page, "document.getElementById('edge').style.top='690px'")
  page |> pz_screenshot(path)
  expect_viewport_badge(page, path, 400, 720 - reference$height, reference)
})

test_that("viewport translation composes with the visible overflow anchor", {
  page <- local_viewport_badge_page()
  reference <- viewport_badge_reference(page, "#add-task", pad = 4)
  pz_js(
    page,
    paste0(
      "const edge=document.getElementById('edge'); edge.style.cssText='position:relative;left:-20px;top:-20px;width:80px;height:80px';",
      "const outer=document.createElement('div'); outer.style.cssText='position:absolute;left:970px;top:100px;width:30px;height:100px;overflow-x:hidden';",
      "const inner=document.createElement('div'); inner.style.cssText='width:100px;height:50px;overflow-y:hidden';",
      "edge.replaceWith(outer); outer.appendChild(inner); inner.appendChild(edge);"
    )
  )
  path <- withr::local_tempfile(fileext = ".png")
  page |> pz_screenshot(path)
  expect_viewport_badge(
    page,
    path,
    1000 - reference$width,
    100 - reference$height,
    reference
  )
  expect_equal(
    as.numeric(unlist(annotation_state(page)[[1]]$rect)),
    c(946, 76, 88, 88)
  )
  expect_png_pixel(page, path, 952, 120, rep(255, 3))
  expect_png_pixel(page, path, 990, 77, rep(255, 3))
  expect_png_pixel(page, path, 990, 162, rep(255, 3))
})

test_that("badge placement follows movement, scroll, and viewport resize", {
  page <- local_viewport_badge_page()
  reference <- viewport_badge_reference(page, "#add-task")
  pz_js(page, "document.getElementById('edge').style.left='calc(100vw - 30px)'")
  pz_poll(
    function() {
      badge <- annotation_badge_rects(page)[[1]]
      abs(badge$left + badge$width - (1000 - 1 / 64)) < 0.001
    },
    timeout = 5,
    loop = page$child_loop,
    what = "the badge to reach its right-edge viewport placement"
  )
  page |> pz_device(width = 600, height = 400)
  pz_poll(
    function() {
      badge <- annotation_badge_rects(page)[[1]]
      abs(badge$left + badge$width - (600 - 1 / 64)) < 0.001
    },
    timeout = 5,
    loop = page$child_loop,
    what = "the badge to follow the resized viewport edge"
  )
  pz_js(
    page,
    "document.getElementById('edge').style.left='300px'; document.body.style.height='1200px'; window.scrollTo(0,250)"
  )
  pz_poll(
    function() abs(annotation_badge_rects(page)[[1]]$top) < 0.001,
    timeout = 5,
    loop = page$child_loop,
    what = "the scrolled target's badge to stay at the viewport top"
  )
  path <- withr::local_tempfile(fileext = ".png")
  page |> pz_screenshot(path)
  expect_viewport_badge(page, path, 300, 0, reference)
  pz_js(page, "window.scrollTo(0,0)")
  pz_poll(
    function() {
      abs(annotation_badge_rects(page)[[1]]$top - (250 - reference$height)) <
        0.001
    },
    timeout = 5,
    loop = page$child_loop,
    what = "the badge to return to its preferred above-mark anchor"
  )
})

test_that("off-viewport badges stay with their targets in framed captures", {
  page <- local_viewport_badge_page()
  reference <- viewport_badge_reference(page, "#add-task", pad = 4)
  pz_js(page, "document.getElementById('edge').style.top='730px'")
  path <- withr::local_tempfile(fileext = ".png")
  page |> pz_screenshot(path)
  badge <- annotation_badge_rects(page)[[1]]
  expect_equal(c(badge$left, badge$bottom), c(396, 726), tolerance = 0.001)
  pz_js(page, "document.getElementById('edge').style.top='1500px'")
  spec <- pz_frame("#edge", target_box = "annotated", pad = 8)
  clip <- frame_clip(page, frame_effective(page, spec))
  page |> pz_screenshot(path, frame = spec)
  badge <- annotation_badge_rects(page)[[1]]
  expect_equal(badge$bottom, 1496, tolerance = 0.001)
  expect_equal(pz_js(page, "window.scrollY"), 0)
  expect_png_pixel(
    page,
    path,
    398 - clip$x,
    1496 - reference$height / 2 - clip$y,
    c(255, 0, 255)
  )
})

test_that("oversized badges pin to zero without viewport-dependent rewrapping", {
  page <- local_viewport_badge_page()
  reference <- viewport_badge_reference(
    page,
    paste(rep("word", 15), collapse = " ")
  )
  page |> pz_device(width = 200, height = 720)
  pz_js(page, "document.getElementById('edge').style.left='170px'")
  path <- withr::local_tempfile(fileext = ".png")
  page |> pz_screenshot(path)
  badge <- annotation_badge_rects(page)[[1]]
  expect_equal(badge$left, 0)
  expect_equal(
    c(badge$width, badge$height),
    c(reference$width, reference$height)
  )
  expect_gt(badge$width, 200)
  expect_png_pixel(page, path, 2, badge$top + badge$height / 2, c(255, 0, 255))
  page |> pz_device(width = 1000, height = 40)
  pz_js(
    page,
    "document.getElementById('edge').style.left='400px'; document.getElementById('edge').style.top='10px'"
  )
  page |> pz_screenshot(path)
  badge <- annotation_badge_rects(page)[[1]]
  expect_equal(badge$top, 0)
  expect_equal(
    c(badge$width, badge$height),
    c(reference$width, reference$height)
  )
  expect_gt(badge$height, 40)
  expect_png_pixel(page, path, 402, 20, c(255, 0, 255))
})

test_that("fractional zoomed badge sizes do not leak past the viewport edge", {
  page <- local_viewport_badge_page()
  pz_js(page, "document.documentElement.style.zoom='1.25'")
  reference <- viewport_badge_reference(page, "#add-task")
  pz_js(page, "document.getElementById('edge').style.left='776px'")
  path <- withr::local_tempfile(fileext = ".png")
  page |> pz_screenshot(path)
  expect_viewport_badge(
    page,
    path,
    1000 - reference$width,
    312.5 - reference$height,
    reference
  )
})

test_that("pop and slide do not feed animated sizes back into badge placement", {
  page <- local_viewport_badge_page()
  reference <- viewport_badge_reference(page, "#add-task")
  pz_js(
    page,
    "document.getElementById('edge').style.left='970px'; document.getElementById('edge').style.top='0px'"
  )
  for (reveal in c("pop", "slide")) {
    pz_js(
      page,
      paste0(
        "(() => { const l=document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations');",
        "l.pz.draw([document.getElementById('edge')],{id:'edge',type:'box',pad:[0,0,0,0],label:'#add-task',",
        "color:'red',strokeWidth:3,labelFill:'#ff00ff',labelTextColor:'white',fontFamily:'monospace',fontSize:14,",
        "reveal:'",
        reveal,
        "',animate:true}); l.querySelector('.pz-annotation').getAnimations({subtree:true})[0].pause(); })()"
      )
    )
    for (fraction in c(0, 0.5, 1)) {
      placement <- pz_js(
        page,
        paste0(
          "(() => { const l=document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations');",
          "const a=l.querySelector('.pz-annotation').getAnimations({subtree:true})[0]; a.currentTime=",
          fraction,
          "*a.effect.getTiming().duration; l.pz.sync();",
          "const b=l.querySelector('span'); return [parseFloat(b.style.left),parseFloat(b.style.top)]; })()"
        )
      )
      expect_equal(
        as.numeric(unlist(placement)),
        c(30 - reference$width - 1 / 64, 0),
        tolerance = 0.001
      )
    }
    page |> pz_annotate_clear("edge")
  }
  page |> pz_annotate("#edge", label = "Old", id = "edge")
  page |> pz_annotate("#edge", label = "New", id = "edge")
  expect_length(annotation_badge_rects(page), 1)
  expect_identical(annotation_state(page)[[1]]$label, "New")
  page |> pz_annotate_clear()
  expect_length(annotation_state(page), 0)
})

test_that("a recorded top-right badge appears in retained frames and clears", {
  skip_if_no_av()
  skip_if_not_installed("png")
  page <- local_viewport_badge_page()
  reference <- viewport_badge_reference(page, "#add-task")
  page |> pz_annotate_clear()
  pz_js(
    page,
    "document.getElementById('edge').style.left='970px'; document.getElementById('edge').style.top='0px'"
  )
  path <- withr::local_tempfile(fileext = ".mp4")
  page |>
    pz_record_start(
      path,
      method = "poll",
      fps = 12,
      hold = c(0, 0),
      keep_frames = TRUE
    )
  rec <- page_recorder(page)
  withr::defer(unlink(rec$frames_dir, recursive = TRUE))
  defer_record_stop(page)
  dpr <- page_dpr(page)
  last_badge <- function() {
    if (!length(rec$files)) {
      return(rep(NA_real_, 3))
    }
    png::readPNG(tail(rec$files, 1))[
      round(reference$height / 2 * dpr) + 1,
      round((1000 - reference$width + 2) * dpr) + 1,
      1:3
    ]
  }
  page |>
    pz_annotate(
      "#edge",
      label = "#add-task",
      font_family = "monospace",
      label_fill = "#ff00ff",
      reveal = "fade",
      id = "edge"
    )
  pz_poll(
    function() isTRUE(all(abs(last_badge() - c(1, 0, 1)) < 0.03)),
    timeout = 5,
    loop = page$child_loop,
    what = "a retained frame showing the viewport-contained top-right badge"
  )
  page |> pz_annotate_clear("edge")
  pz_poll(
    function() isTRUE(all(abs(last_badge() - 1) < 0.03)),
    timeout = 5,
    loop = page$child_loop,
    what = "a retained frame without the cleared viewport badge"
  )
  expect_length(annotation_state(page), 0)
  page |> pz_record_stop()
})

test_that("interior zero-size marks clamp badges but viewport-edge points do not", {
  page <- local_viewport_badge_page()
  reference <- viewport_badge_reference(page, "#add-task", pad = 10)
  pz_js(
    page,
    "document.getElementById('edge').style.cssText='position:absolute;left:990px;top:5px;width:0;height:0'"
  )
  path <- withr::local_tempfile(fileext = ".png")
  page |> pz_screenshot(path)
  expect_true(annotation_state(page)[[1]]$visible)
  expect_viewport_badge(page, path, 1000 - reference$width, 0, reference)
  pz_js(page, "document.getElementById('edge').style.left='1000px'")
  page |> pz_screenshot(path)
  badge <- annotation_badge_rects(page)[[1]]
  expect_equal(c(badge$left, badge$bottom), c(990, -5), tolerance = 0.001)
})

test_that("padding alone cannot pull an off-viewport target's badge inward", {
  page <- local_viewport_badge_page()
  reference <- viewport_badge_reference(page, "#add-task", pad = 20)
  pz_js(
    page,
    "document.getElementById('edge').style.left='970px'; document.getElementById('edge').style.top='730px'"
  )
  path <- withr::local_tempfile(fileext = ".png")
  page |> pz_screenshot(path)
  badge <- annotation_badge_rects(page)[[1]]
  expect_equal(c(badge$left, badge$bottom), c(950, 710), tolerance = 0.001)
  expect_png_pixel(
    page,
    path,
    1000 - reference$width + 2,
    710 - reference$height / 2,
    rep(255, 3)
  )
})

test_that("badge bounds exclude forced classic scrollbars like recorder crops", {
  page <- local_viewport_badge_page()
  pz_js(
    page,
    paste0(
      "document.head.insertAdjacentHTML('beforeend', '<style>::-webkit-scrollbar{width:24px;height:18px;background:white}</style>');",
      "document.documentElement.style.overflow='scroll';",
      "document.body.style.width='2000px'; document.body.style.height='2000px';"
    )
  )
  pz_poll(
    function() {
      gap <- unlist(pz_js(
        page,
        "[innerWidth-document.documentElement.clientWidth,innerHeight-document.documentElement.clientHeight]"
      ))
      all(gap == c(24, 18))
    },
    timeout = 5,
    loop = page$child_loop,
    what = "the forced classic scrollbars to reserve 24px by 18px"
  )
  viewport <- unlist(pz_js(
    page,
    "[document.documentElement.clientWidth,document.documentElement.clientHeight]"
  ))
  outer <- unlist(pz_js(page, "[innerWidth,innerHeight]"))
  expect_equal(outer - viewport, c(24, 18))
  metrics <- page$session$Page$getLayoutMetrics()$cssVisualViewport
  expect_equal(c(metrics$clientWidth, metrics$clientHeight), viewport)
  path <- withr::local_tempfile(fileext = ".png")
  # Match recorder crops without the viewport expansion of framed stills.
  capture <- function() {
    pz_js(page, paste0(ANNOTATION_LAYER_JS, "?.sync()"))
    shot <- page$session$Page$captureScreenshot(
      format = "png",
      clip = list(
        x = 0,
        y = 0,
        width = viewport[1],
        height = viewport[2],
        scale = 1
      ),
      fromSurface = TRUE,
      captureBeyondViewport = FALSE
    )
    writeBin(jsonlite::base64_dec(shot$data), path)
  }

  reference <- viewport_badge_reference(page, "#add-task")
  pz_js(
    page,
    "document.getElementById('edge').style.left=(document.documentElement.clientWidth-30)+'px'"
  )
  capture()
  expect_viewport_badge(
    page,
    path,
    viewport[1] - reference$width,
    250 - reference$height,
    reference
  )
  expect_lte(
    annotation_badge_rects(page)[[1]]$left + reference$width,
    viewport[1] + 1e-6
  )
  expect_equal(
    png_dimensions(path),
    as.integer(round(viewport * page_dpr(page)))
  )

  pz_js(
    page,
    "document.getElementById('edge').style.left=(document.documentElement.clientWidth+1)+'px'"
  )
  capture()
  expect_equal(annotation_badge_rects(page)[[1]]$left, viewport[1] + 1)

  pz_js(page, "document.getElementById('edge').style.left='400px'")
  viewport_badge_reference(page, "#add-task", pad = 10)
  pz_js(
    page,
    "const edge=document.getElementById('edge'); edge.style.width='0px'; edge.style.height='0px'; edge.style.left=document.documentElement.clientWidth+'px'"
  )
  capture()
  expect_equal(annotation_badge_rects(page)[[1]]$left, viewport[1] - 10)

  pz_js(page, "document.getElementById('edge').style.left='400px'")
  viewport_badge_reference(page, "#add-task", pad = c(-40, 0, 50, 10))
  pz_js(
    page,
    "document.getElementById('edge').style.top=document.documentElement.clientHeight+'px'"
  )
  capture()
  expect_equal(annotation_badge_rects(page)[[1]]$bottom, viewport[2] + 40)

  pz_js(
    page,
    "document.getElementById('edge').style.cssText='position:absolute;left:400px;top:250px;width:30px;height:30px'"
  )
  reference <- viewport_badge_reference(page, "A", pad = c(-40, 0, 50, 0))
  pz_js(
    page,
    "document.getElementById('edge').style.top=(document.documentElement.clientHeight-30)+'px'"
  )
  capture()
  expect_viewport_badge(
    page,
    path,
    400,
    viewport[2] - reference$height,
    reference
  )
  expect_png_pixel(
    page,
    path,
    402,
    viewport[2] - reference$height - 1 / 64 + 4,
    c(255, 0, 255)
  )
})
