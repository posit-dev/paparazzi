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
  page |> pz_stage(annotate_color = "rgb(255, 0, 0)", annotate_font_size = 18)
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
  before <- annotation_state(page)
  pz_js(
    page,
    "window.scrollTo(0, 80); document.getElementById('outer').scrollTop = 30; document.getElementById('box').style.top = '350px'"
  )
  pump_loop(page$child_loop, 0.07)
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
  pump_loop(page$child_loop, 0.07)
  expect_false(annotation_state(page)[[2]]$visible)
  pz_js(page, "document.getElementById('inner').style.display = ''")
  pump_loop(page$child_loop, 0.07)
  expect_true(annotation_state(page)[[2]]$visible)
  pz_js(page, "document.getElementById('box').remove()")
  pump_loop(page$child_loop, 0.07)
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

test_that("fade outside recording is instant, and unsupported types fail", {
  page <- annotation_page()
  page |> pz_annotate("#box", id = "x")
  expect_equal(annotation_state(page)[[1]]$animations, 0)
  page |> pz_annotate_clear("x")
  expect_length(annotation_state(page), 0)
  expect_error(pz_annotate(page, "#box", type = "circle"))
  expect_error(pz_annotate(page, "#box", reveal = "wipe"))
  expect_error(pz_annotate(page, "#box", id = "caption"))
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
  page |> pz_annotate_clear()
  page |>
    pz_stage(
      annotate_color = "green",
      annotate_font_family = "monospace",
      annotate_font_size = 20
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
    pz_stage(
      annotate_color = NULL,
      annotate_font_family = NULL,
      annotate_font_size = NULL
    )
  page |> pz_annotate("#box", reveal = "none")
  expect_identical(annotation_state(page)[[1]]$color, "rgb(225, 29, 72)")
  expect_error(pz_stage(page, annotate_font_size = 0))
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
  page |> pz_screenshot(framed, target = "#box")
  cropped <- png::readPNG(framed)
  expect_equal(at(cropped, 25, 1), c(1, 0, 0), tolerance = 0.04)
  overlay_clear(page)
})

test_that("fade produces recorded intermediate frames and clears in reverse", {
  skip_if_not_installed("av")
  skip_if_not_installed("png")
  page <- annotation_page()
  path <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(path, fps = 20, hold = c(0, 0), keep_frames = TRUE)
  defer_record_stop(page)
  page |>
    pz_annotate("#box", id = "animated", reveal = "fade", color = "#ff0000")
  expect_equal(annotation_state(page)[[1]]$animations, 0)
  # Under load the last capture of the pumped fade can still be in flight
  # mid-animation; keep capturing until a settled frame lands.
  pump_loop(page$child_loop, 0.5)
  files <- page_recorder(page)$files
  expect_gt(length(files), 1)
  dpr <- page_dpr(page)
  green_at_border <- function(file) {
    png::readPNG(file)[round(311 * dpr) + 1, round(225 * dpr) + 1, 2]
  }
  entering <- vapply(files, green_at_border, 0.0)
  expect_true(any(entering > 0.15 & entering < 0.85))
  expect_lt(tail(entering, 1), 0.1)
  page |> pz_annotate_clear("animated")
  expect_length(annotation_state(page), 0)
  leaving <- vapply(
    page_recorder(page)$files[-seq_along(files)],
    green_at_border,
    0.0
  )
  expect_true(any(leaving > 0.15 & leaving < 0.85))
  page |> pz_record_stop()
  expect_true(file.exists(path))
})

test_that("paused recording skips fade on draw and clear", {
  skip_if_not_installed("av")
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

test_that("redaction fills every match immediately and remains after disconnection", {
  skip_if_not_installed("png")
  page <- annotation_page()
  pz_js(
    page,
    "document.querySelectorAll('.mark').forEach(el => el.textContent = 'SECRET')"
  )
  page |> pz_stage(annotate_color = "#ff0000")
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
  pump_loop(page$child_loop, 0.05)
  after <- pz_js(
    page,
    "(() => { const n = document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelectorAll('.pz-redaction')[1]; return [n.style.display, parseFloat(n.style.left), parseFloat(n.style.top)]; })()"
  )
  expect_equal(unlist(after), c("", "198", "308"))
  page |> pz_screenshot(path)
  img <- png::readPNG(path)
  expect_equal(at(220, 330), rep(23 / 255, 3), tolerance = 0.03)
  page |> pz_annotate_clear("secret")
  expect_length(annotation_state(page), 0)
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
  pump_loop(page$child_loop, 0.06)
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
  pump_loop(page$child_loop, 0.05)
  page |> pz_screenshot(path)
  img <- png::readPNG(path)
  expect_equal(rgb(45, 35), rep(23 / 255, 3), tolerance = 0.03)
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

test_that("blur changes text pixels and keeps its box when target stops rendering", {
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
  skip_if_not_installed("av")
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
  pump_loop(page$child_loop, 0.3)
  captured <- page_recorder(page)$files
  expect_gt(length(captured), before)
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
