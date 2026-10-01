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
  pump_loop(page$child_loop, 0.07)
  expect_true(annotation_state(page)[[2]]$visible)
  before <- annotation_state(page)
  pz_js(
    page,
    "window.scrollTo(0, 80); document.getElementById('outer').scrollTop = 130; document.getElementById('box').style.top = '350px'"
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
  pz_js(page, "document.getElementById('outer').scrollTop = 0")
  pump_loop(page$child_loop, 0.07)
  expect_false(annotation_state(page)[[2]]$visible)
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

test_that("recorded clear removes all nodes after mixed exit animations", {
  skip_if_not_installed("av")
  page <- annotation_page()
  pz_record_start(page, withr::local_tempfile(fileext = ".mp4"), hold = c(0, 0))
  defer_record_stop(page)
  pz_annotate(page, "#box", id = "shared", reveal = "fade")
  pz_annotate(page, "#box", id = "shared", reveal = "wipe")
  pz_annotate_callout(page, "Tip", target = "#box", id = "callout")
  pz_annotate_spotlight(page, "#box")
  pz_annotate_redact(page, "#box", id = "redaction")
  pz_annotate_clear(page)
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
  skip_if_not_installed("av")
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
  pump_loop(page$child_loop, 0.05)
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
  pump_loop(page$child_loop, 0.05)
  expect_equal(pixel(380, 110), rep(23 / 255, 3), tolerance = 0.03)
  expect_equal(pixel(380, 190), rep(1, 3), tolerance = 0.03)
  pz_js(page, "document.getElementById('clip').scrollTop = 250")
  pump_loop(page$child_loop, 0.05)
  expect_identical(
    pz_js(
      page,
      "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-redaction').style.display"
    ),
    "none"
  )
  expect_equal(pixel(380, 110), rep(1, 3), tolerance = 0.03)
  pz_js(page, "document.getElementById('clip').scrollTop = 0")
  pump_loop(page$child_loop, 0.05)
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
  page <- local_page(pz_example("tasks"))
  page |>
    pz_act_type("Prepare release notes", target = "#task-title") |>
    pz_act_click("#add-task")
  target <- pz_loc(".task", has_text = "Prepare release notes")
  rect <- unlist(pz_js(
    page,
    "(() => { const r = document.querySelector('.task').getBoundingClientRect(); return [r.left, r.top, r.right, r.bottom]; })()"
  ))
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
    expect_png_pixel(page, path, mean(rect[c(1, 3)]), rect[2] - 2, red)
    expect_png_pixel(page, path, rect[3] + 2, mean(rect[c(2, 4)]), red)
    expect_png_pixel(page, path, mean(rect[c(1, 3)]), rect[4] + 2, red)
    expect_png_pixel(page, path, rect[1] - 2, mean(rect[c(2, 4)]), red)
  }
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
  pump_loop(page$child_loop, 0.05)
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
  pump_loop(page$child_loop, 0.05)
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
  pump_loop(page$child_loop, 0.05)
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
  pump_loop(page$child_loop, 0.05)
  expect_identical(
    pz_js(
      page,
      "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-redaction').style.display"
    ),
    "none"
  )
  pz_js(page, "document.getElementById('secret').style.visibility = 'visible'")
  pump_loop(page$child_loop, 0.05)
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
  skip_if_not_installed("av")
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
