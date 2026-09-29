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

test_that("fade outside recording is instant, and invalid types fail", {
  page <- annotation_page()
  page |> pz_annotate("#box", id = "x")
  expect_equal(annotation_state(page)[[1]]$animations, 0)
  page |> pz_annotate_clear("x")
  expect_length(annotation_state(page), 0)
  expect_error(pz_annotate(page, "#box", type = "unknown"))
  expect_error(pz_annotate(page, "#box", reveal = "unknown"))
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
  page |> pz_screenshot(path, target = "#far")
  expect_equal(pz_js(page, "window.scrollY"), 0)
  img <- png::readPNG(path)
  expect_equal(mean(img[,, 1:3]), 23 / 255, tolerance = 0.025)
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
        "label:null,color:'#ff0000',fontFamily:'sans-serif',fontSize:14,reveal:'",
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
      "(() => { const l=document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations'); l.pz.clear({id:'test',animate:true}); l.querySelector('.pz-exiting').getAnimations({subtree:true})[0].pause(); })()"
    )
    leaving <- lapply(c(0, 0.25, 0.5, 0.75, 1), function(fraction) {
      pz_js(
        page,
        paste0(
          "(() => { const a=document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-exiting').getAnimations({subtree:true})[0]; a.currentTime=",
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
      "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations').pz.finishClear()"
    )
    expect_length(annotation_state(page), 0)
  }
})

test_that("wipe sweeps through recorded frames and reverses on clear", {
  skip_if_not_installed("av")
  skip_if_not_installed("png")
  page <- annotation_page()
  path <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(path, fps = 20, hold = c(0, 0), keep_frames = TRUE)
  defer_record_stop(page)
  page |> pz_annotate("#box", id = "wipe", reveal = "wipe", color = "#ff0000")
  pump_loop(page$child_loop, 0.3)
  files <- page_recorder(page)$files
  dpr <- page_dpr(page)
  painted <- function(file) {
    img <- png::readPNG(file)
    region <- img[round((309:361) * dpr) + 1, round((199:301) * dpr) + 1, 1:3]
    sum(region[,, 1] > 0.9 & region[,, 2] < 0.35)
  }
  entering <- vapply(files, painted, 0)
  full <- max(entering)
  expect_gt(full, 100)
  expect_true(any(entering > full * 0.1 & entering < full * 0.9))
  page |> pz_annotate_clear("wipe")
  leaving <- vapply(page_recorder(page)$files[-seq_along(files)], painted, 0)
  expect_true(any(leaving > full * 0.1 & leaving < full * 0.9))
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
    "(() => { const l=document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations'); l.pz.draw([document.querySelector('#box')], {id:'badge',type:'circle',pad:[0,0,0,0],label:'A',color:'red',fontFamily:'sans-serif',fontSize:14,reveal:'draw',animate:true}); l.querySelector('.pz-annotation').getAnimations({subtree:true})[0].pause(); })()"
  )
  expect_equal(annotation_state(page)[[1]]$label, "A")
  pz_js(
    page,
    "(() => { const l=document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations'); l.pz.clear({id:'badge',animate:true}); l.querySelector('.pz-exiting').getAnimations({subtree:true})[0].pause(); })()"
  )
  expect_equal(
    pz_js(
      page,
      "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-exiting span') === null"
    ),
    TRUE
  )
  pz_js(
    page,
    "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations').pz.finishClear()"
  )
})

test_that("default reveal is fade for boxes and draw for other marks", {
  skip_if_not_installed("av")
  page <- annotation_page()
  path <- withr::local_tempfile(fileext = ".mp4")
  pz_js(
    page,
    "window.__markAnimations = []; const originalAnimate = Element.prototype.animate; Element.prototype.animate = function(frames, options) { window.__markAnimations.push(frames); return originalAnimate.call(this, frames, options); };"
  )
  page |> pz_record_start(path, fps = 10, hold = c(0, 0))
  defer_record_stop(page)
  for (type in c("box", "circle", "underline", "highlight")) {
    page |> pz_annotate("#box", type = type, id = "default")
    page |> pz_annotate_clear("default")
  }
  first <- pz_js(
    page,
    "window.__markAnimations.filter((_, i) => i % 2 === 0).map(frames => Object.keys(frames[0]))"
  )
  expect_true("opacity" %in% first[[1]])
  expect_true("strokeDashoffset" %in% first[[2]])
  expect_true("transform" %in% first[[3]])
  expect_true("transform" %in% first[[4]])
  page |> pz_record_stop()
})

test_that("clear returns the longest active exit duration", {
  page <- annotation_page()
  page |>
    pz_annotate("#box", id = "boot", reveal = "none") |>
    pz_annotate_clear()
  durations <- pz_js(
    page,
    "(() => { const l=document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations'); const el=document.querySelector('#box'); const o={type:'box',pad:[0,0,0,0],label:null,color:'red',fontFamily:'sans-serif',fontSize:14,animate:true}; const short=l.pz.draw([el], {...o,id:'short',reveal:'fade'}); const long=l.pz.draw([el], {...o,id:'long',reveal:'wipe'}); const clear=l.pz.clear({id:null,animate:true}); l.pz.finishClear(); return [short,long,clear,l.pz.clear({id:null,animate:true})]; })()"
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
    "(() => { const l=document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations'); l.pz.draw([document.querySelector('#box')], {id:'labeled',type:'box',pad:[0,0,0,0],label:'A',color:'#ff0000',fontFamily:'sans-serif',fontSize:14,reveal:'wipe',animate:true}); const a=l.querySelector('.pz-annotation').getAnimations({subtree:true})[0]; a.pause(); a.currentTime=200; })()"
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
    "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations').pz.clear({id:'labeled',animate:true})"
  )
  expect_true(pz_js(
    page,
    "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-exiting span') === null"
  ))
  pz_js(
    page,
    "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations').pz.finishClear()"
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
