spotlight_page <- function(.env = parent.frame()) {
  page <- local_page(.env = .env)
  pz_js(
    page,
    paste0(
      "document.body.style.cssText = 'margin:0;background:white';",
      "document.body.innerHTML = '<div id=one style=\"position:absolute;left:100px;top:100px;width:100px;height:80px;background:rgb(0, 200, 80)\"></div>' +",
      "'<div id=two style=\"position:absolute;left:300px;top:100px;width:100px;height:80px;background:rgb(0, 100, 255)\"></div>' +",
      "'<div style=\"height:1800px\"></div>';"
    )
  )
  page
}

spotlight_layer <- function(page, expr) {
  pz_js(
    page,
    paste0(
      "(() => { const layer = document.getElementById('paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotations'); return ",
      expr,
      "; })()"
    )
  )
}

spotlight_image <- function(page, path) {
  page |> pz_screenshot(path)
  png::readPNG(path)
}

spotlight_viewport_image <- function(page, path) {
  shot <- page$session$Page$captureScreenshot(
    format = "png",
    fromSurface = TRUE
  )
  writeBin(jsonlite::base64_dec(shot$data), path)
  png::readPNG(path)
}

spotlight_rgb <- function(img, page, x, y) {
  dpr <- page_dpr(page)
  as.numeric(img[round(y * dpr) + 1, round(x * dpr) + 1, 1:3])
}

test_that("spotlight leaves its cutout unchanged and dims the outside in stills", {
  skip_if_not_installed("png")
  page <- spotlight_page()
  path <- withr::local_tempfile(fileext = ".png")
  baseline <- spotlight_image(page, path)
  expect_identical(pz_annotate_spotlight(page, "#one", dim = 0.6), page)
  lit <- spotlight_image(page, path)
  expect_equal(
    spotlight_rgb(lit, page, 150, 140),
    spotlight_rgb(baseline, page, 150, 140),
    tolerance = 0.03
  )
  expect_equal(spotlight_rgb(lit, page, 30, 30), rep(0.4, 3), tolerance = 0.04)
  expect_equal(
    spotlight_rgb(lit, page, 350, 140),
    spotlight_rgb(baseline, page, 350, 140) * 0.4,
    tolerance = 0.04
  )
})

test_that("spotlight dims the visible bottom of a tall document", {
  skip_if_not_installed("png")
  page <- local_page(
    pz_example("tasks"),
    width = 720,
    height = 800,
    color_scheme = "light"
  )
  path <- withr::local_tempfile(fileext = ".png")
  pz_js(page, "document.body.style.minHeight = '840px'")
  doc_height <- pz_js(page, "document.documentElement.scrollHeight")
  expect_gt(doc_height, 800)
  expect_gt(780, doc_height * 0.9)
  baseline <- spotlight_viewport_image(page, path)
  page |>
    pz_annotate_spotlight(
      list("#task-title", "#add-task"),
      dim = 0.75,
      reveal = "none"
    )
  dimmed <- spotlight_viewport_image(page, path)
  baseline_rgb <- spotlight_rgb(baseline, page, 20, 780)
  expect_gt(mean(baseline_rgb), 0.7)
  expect_equal(
    spotlight_rgb(dimmed, page, 20, 780),
    baseline_rgb * 0.25,
    tolerance = 0.04
  )
})

test_that("spotlight cuts out every match, including overlaps and padded corners", {
  skip_if_not_installed("png")
  page <- spotlight_page()
  path <- withr::local_tempfile(fileext = ".png")
  page |>
    pz_annotate_spotlight(
      list("#one", "#two"),
      pad = c(8, 5, 8, 8),
      reveal = "none"
    )
  img <- spotlight_image(page, path)
  expect_equal(
    spotlight_rgb(img, page, 150, 140),
    c(0, 200 / 255, 80 / 255),
    tolerance = 0.03
  )
  expect_equal(
    spotlight_rgb(img, page, 350, 140),
    c(0, 100 / 255, 1),
    tolerance = 0.03
  )
  expect_equal(spotlight_rgb(img, page, 94, 140), rep(1, 3), tolerance = 0.03)
  expect_equal(spotlight_rgb(img, page, 92, 92), rep(0.4, 3), tolerance = 0.04)
  pz_js(page, "document.getElementById('two').style.left = '160px'")
  img <- spotlight_image(page, path)
  expect_equal(
    spotlight_rgb(img, page, 180, 120),
    c(0, 100 / 255, 1),
    tolerance = 0.03
  )
  expect_equal(
    spotlight_rgb(img, page, 270, 140),
    rep(0.4, 3),
    tolerance = 0.04
  )
})

test_that("spotlight replaces its single slot and clears by reserved id or all", {
  skip_if_not_installed("png")
  page <- spotlight_page()
  path <- withr::local_tempfile(fileext = ".png")
  page |> pz_annotate_spotlight("#one", reveal = "none")
  page |> pz_annotate_spotlight("#two", reveal = "none")
  expect_equal(
    spotlight_layer(page, "layer.querySelectorAll('.pz-spotlight').length"),
    1
  )
  img <- spotlight_image(page, path)
  expect_equal(
    spotlight_rgb(img, page, 150, 140),
    c(0, 200 / 255, 80 / 255) * 0.4,
    tolerance = 0.04
  )
  expect_equal(
    spotlight_rgb(img, page, 350, 140),
    c(0, 100 / 255, 1),
    tolerance = 0.03
  )
  page |> pz_annotate_clear("spotlight")
  expect_equal(
    spotlight_layer(page, "layer.querySelectorAll('.pz-spotlight').length"),
    0
  )
  page |> pz_annotate_spotlight("#one") |> pz_annotate_clear()
  expect_equal(
    spotlight_layer(page, "layer.querySelectorAll('.pz-spotlight').length"),
    0
  )
})

test_that("spotlight follows page and inner scroll, then hides disconnected holes", {
  skip_if_not_installed("png")
  page <- spotlight_page()
  pz_js(
    page,
    "document.body.insertAdjacentHTML('beforeend', '<div id=outer style=\"position:fixed;top:300px;left:30px;width:140px;height:100px;overflow:auto\"><div style=\"height:140px\"></div><div id=inner style=\"width:80px;height:40px;background:red\"></div></div>')"
  )
  page |> pz_annotate_spotlight(list("#one", "#inner"), reveal = "none")
  holes <- function() {
    spotlight_layer(
      page,
      "[...layer.querySelectorAll('.pz-spotlight mask rect')].slice(1).map(n => ({x:+n.getAttribute('x'),y:+n.getAttribute('y'),visible:n.style.display !== 'none'}))"
    )
  }
  # #inner starts scrolled out of #outer's box, so it gets no hole;
  # scroll it into view before measuring movement.
  expect_false(holes()[[2]]$visible)
  pz_js(page, "document.getElementById('outer').scrollTop = 100")
  pump_loop(page$child_loop, 0.07)
  before <- holes()
  pz_js(
    page,
    "window.scrollTo(0, 50); document.getElementById('outer').scrollTop = 60; document.getElementById('one').style.left = '120px'"
  )
  pump_loop(page$child_loop, 0.07)
  after <- holes()
  expect_equal(after[[1]]$x, before[[1]]$x + 20, tolerance = 0.5)
  expect_equal(after[[1]]$y, before[[1]]$y, tolerance = 0.5)
  expect_equal(after[[2]]$y, before[[2]]$y - 60 + 50, tolerance = 0.5)
  path <- withr::local_tempfile(fileext = ".png")
  img <- spotlight_image(page, path)
  expect_equal(
    spotlight_rgb(img, page, 150, 90),
    c(0, 200 / 255, 80 / 255),
    tolerance = 0.04
  )
  expect_equal(spotlight_rgb(img, page, 50, 390), c(1, 0, 0), tolerance = 0.04)
  pz_js(page, "document.getElementById('inner').style.display = 'none'")
  img <- spotlight_image(page, path)
  expect_false(holes()[[2]]$visible)
  expect_equal(spotlight_rgb(img, page, 50, 385), rep(0.4, 3), tolerance = 0.04)
  pz_js(
    page,
    "document.getElementById('inner').style.display = ''; document.getElementById('one').remove()"
  )
  pump_loop(page$child_loop, 0.07)
  expect_false(holes()[[1]]$visible)
  expect_true(holes()[[2]]$visible)
})

test_that("spotlight opens no cutout for a target clipped away by an overflow ancestor", {
  skip_if_not_installed("png")
  page <- spotlight_page()
  pz_js(
    page,
    paste0(
      "document.body.insertAdjacentHTML('beforeend', ",
      "'<div style=\"position:absolute;left:100px;top:300px;width:200px;height:100px;overflow:auto\">' +",
      "'<div style=\"height:220px\"></div><div id=buried style=\"margin-left:20px;width:120px;height:60px\"></div>' +",
      "'<div style=\"height:220px\"></div></div>')"
    )
  )
  path <- withr::local_tempfile(fileext = ".png")
  baseline <- spotlight_image(page, path)
  page |>
    pz_annotate_spotlight(list("#one", "#buried"), dim = 0.6, reveal = "none")
  lit <- spotlight_image(page, path)
  # #one still gets its cutout.
  expect_equal(
    spotlight_rgb(lit, page, 150, 140),
    spotlight_rgb(baseline, page, 150, 140),
    tolerance = 0.03
  )
  # #buried's box projects to x 120..240, y 520..580, below its container;
  # no hole may open there over unrelated content.
  expect_equal(
    spotlight_rgb(lit, page, 180, 550),
    spotlight_rgb(baseline, page, 180, 550) * 0.4,
    tolerance = 0.04
  )
  expect_identical(
    unlist(spotlight_layer(
      page,
      "[...layer.querySelector('.pz-spotlight mask').children].slice(1).map(h => h.style.display)"
    )),
    c("", "none")
  )
})

test_that("spotlight stays under marks and opaque redactions in either draw order", {
  skip_if_not_installed("png")
  page <- spotlight_page()
  pz_js(
    page,
    "document.body.insertAdjacentHTML('beforeend', '<div id=secret style=\"position:fixed;left:450px;top:100px;width:70px;height:70px;background:white\"></div>')"
  )
  path <- withr::local_tempfile(fileext = ".png")
  page |> pz_annotate("#two", id = "mark", color = "#ff0000", reveal = "none")
  page |> pz_annotate_redact("#secret", id = "redaction")
  page |> pz_annotate_spotlight("#one", reveal = "none")
  img <- spotlight_image(page, path)
  expect_equal(spotlight_rgb(img, page, 301, 130), c(1, 0, 0), tolerance = 0.04)
  expect_equal(
    spotlight_rgb(img, page, 480, 130),
    rep(23 / 255, 3),
    tolerance = 0.04
  )
  page |> pz_annotate_clear("mark") |> pz_annotate_clear("redaction")
  page |> pz_annotate_redact("#secret", id = "redaction")
  page |> pz_annotate("#two", id = "mark", color = "#ff0000", reveal = "none")
  img <- spotlight_image(page, path)
  expect_equal(spotlight_rgb(img, page, 301, 130), c(1, 0, 0), tolerance = 0.04)
  expect_equal(
    spotlight_rgb(img, page, 480, 130),
    rep(23 / 255, 3),
    tolerance = 0.04
  )
})

test_that("spotlight validates its options and dim endpoints", {
  skip_if_not_installed("png")
  page <- spotlight_page()
  for (bad in list(-0.1, 1.1, Inf, NA_real_, "0.6", c(0.1, 0.2))) {
    expect_error(pz_annotate_spotlight(page, "#one", dim = bad))
  }
  for (bad in c("draw", "pop", "slide", "wipe", "invalid")) {
    expect_error(
      pz_annotate_spotlight(page, "#one", reveal = bad),
      "fade.*none"
    )
  }
  expect_error(
    pz_annotate_spotlight(page, "#one", reveal = c("fade", "invalid")),
    "reveal"
  )
  expect_error(pz_annotate_spotlight(page, "#one", pad = c(1, 2)))
  expect_error(pz_annotate_spotlight(page, "#one", extra = TRUE))
  path <- withr::local_tempfile(fileext = ".png")
  page |> pz_annotate_spotlight("#one", dim = 0)
  expect_equal(
    spotlight_rgb(spotlight_image(page, path), page, 30, 30),
    rep(1, 3),
    tolerance = 0.03
  )
  page |> pz_annotate_spotlight("#one", dim = 1)
  expect_equal(
    spotlight_rgb(spotlight_image(page, path), page, 30, 30),
    rep(0, 3),
    tolerance = 0.03
  )
  expect_equal(
    spotlight_rgb(spotlight_image(page, path), page, 150, 140),
    c(0, 200 / 255, 80 / 255),
    tolerance = 0.03
  )
})

test_that("spotlight fade pumps during recording and reverses on clear", {
  skip_if_not_installed("png")
  skip_if_not_installed("av")
  page <- spotlight_page()
  path <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(path, fps = 20, hold = c(0, 0), keep_frames = TRUE)
  defer_record_stop(page)
  page |> pz_annotate_spotlight("#one")
  expect_equal(
    spotlight_layer(
      page,
      "layer.querySelector('.pz-spotlight').getAnimations().length"
    ),
    0
  )
  pump_loop(page$child_loop, 0.3)
  files <- page_recorder(page)$files
  dpr <- page_dpr(page)
  outside <- function(file) {
    png::readPNG(file)[round(30 * dpr) + 1, round(30 * dpr) + 1, 1]
  }
  entering <- vapply(files, outside, 0.0)
  expect_true(any(entering > 0.5 & entering < 0.9))
  expect_lt(tail(entering, 1), 0.47)
  page |> pz_annotate_clear("spotlight")
  expect_equal(
    spotlight_layer(page, "layer.querySelectorAll('.pz-spotlight').length"),
    0
  )
  leaving <- vapply(page_recorder(page)$files[-seq_along(files)], outside, 0.0)
  expect_true(any(leaving > 0.5 & leaving < 0.9))
  page |> pz_record_stop()
})

test_that("paused spotlight and its clear are instant", {
  skip_if_not_installed("av")
  page <- spotlight_page()
  path <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(path, fps = 10, hold = c(0, 0)) |> pz_record_pause()
  defer_record_stop(page)
  page |> pz_annotate_spotlight("#one")
  expect_equal(
    spotlight_layer(
      page,
      "layer.querySelector('.pz-spotlight').getAnimations().length"
    ),
    0
  )
  page |> pz_annotate_clear("spotlight")
  expect_equal(
    spotlight_layer(page, "layer.querySelectorAll('.pz-spotlight').length"),
    0
  )
  page |> pz_record_resume() |> pz_record_stop()
})

test_that("spotlight accepts root and scoped NULL targets", {
  skip_if_not_installed("png")
  page <- spotlight_page()
  path <- withr::local_tempfile(fileext = ".png")
  page |> pz_annotate_spotlight(reveal = "none")
  expect_equal(
    spotlight_rgb(spotlight_image(page, path), page, 30, 30),
    rep(1, 3),
    tolerance = 0.03
  )
  scoped <- pz_find(page, "#one")
  scoped |> pz_annotate_spotlight(reveal = "none")
  expect_equal(
    as.numeric(unlist(spotlight_layer(
      page,
      "(() => { const svg = layer.querySelector('.pz-spotlight'); const h = svg.querySelector('mask rect:nth-child(2)'); return [+h.getAttribute('x') + parseFloat(svg.style.left), +h.getAttribute('y') + parseFloat(svg.style.top), +h.getAttribute('width'), +h.getAttribute('height')]; })()"
    ))),
    as.numeric(unlist(pz_js(
      page,
      "(() => { const r = document.querySelector('#one').getBoundingClientRect(); return [r.left, r.top, r.width, r.height]; })()"
    ))),
    tolerance = 1
  )
  img <- spotlight_image(page, path)
  expect_equal(spotlight_rgb(img, page, 30, 30), rep(0.4, 3), tolerance = 0.04)
  expect_equal(
    spotlight_rgb(img, page, 150, 140),
    c(0, 200 / 255, 80 / 255),
    tolerance = 0.03
  )
})

test_that("spotlight belongs to the current document", {
  page <- local_nav_page()
  page |> pz_annotate_spotlight("body", reveal = "none")
  expect_equal(
    spotlight_layer(page, "layer.querySelectorAll('.pz-spotlight').length"),
    1
  )
  page |> pz_nav_goto(nav_fixture_url("b"))
  expect_equal(
    spotlight_layer(page, "layer.querySelectorAll('.pz-spotlight').length"),
    0
  )
  page |>
    pz_annotate_spotlight("body", reveal = "none") |>
    pz_annotate_clear("spotlight")
  expect_equal(
    spotlight_layer(page, "layer.querySelectorAll('.pz-spotlight').length"),
    0
  )
})

test_that("spotlight dims a below-fold target-framed still without scrolling", {
  skip_if_not_installed("png")
  page <- spotlight_page()
  pz_js(
    page,
    "document.body.insertAdjacentHTML('beforeend', '<div id=far style=\"position:absolute;left:120px;top:1500px;width:180px;height:90px;background:white\"></div>')"
  )
  expect_equal(pz_js(page, "window.scrollY"), 0)
  page |> pz_annotate_spotlight("#one", reveal = "none")
  path <- withr::local_tempfile(fileext = ".png")
  page |> pz_screenshot(path, frame = "#far")
  expect_equal(pz_js(page, "window.scrollY"), 0)
  img <- png::readPNG(path)
  expect_equal(mean(img[,, 1:3]), 0.4, tolerance = 0.04)
})

test_that("hidden and zero-size targets cannot leave spotlight holes", {
  skip_if_not_installed("png")
  page <- spotlight_page()
  path <- withr::local_tempfile(fileext = ".png")
  pz_js(page, "document.getElementById('two').style.visibility = 'hidden'")
  page |> pz_annotate_spotlight("#two", reveal = "none")
  img <- spotlight_image(page, path)
  expect_equal(
    spotlight_rgb(img, page, 350, 140),
    rep(0.4, 3),
    tolerance = 0.04
  )
  pz_js(page, "document.getElementById('two').style.visibility = 'visible'")
  img <- spotlight_image(page, path)
  expect_equal(
    spotlight_rgb(img, page, 350, 140),
    c(0, 100 / 255, 1),
    tolerance = 0.04
  )
  # Like redactions, a hidden target keeps its cutout while a descendant
  # stays visible.
  pz_js(
    page,
    paste0(
      "(() => { const two = document.getElementById('two');",
      "two.style.visibility = 'hidden';",
      "two.insertAdjacentHTML('beforeend', '<span style=\"visibility:visible\">shown</span>'); })()"
    )
  )
  pump_loop(page$child_loop, 0.07)
  hole_display <- function() {
    unlist(spotlight_layer(
      page,
      "[...layer.querySelector('.pz-spotlight mask').children].slice(1).map(h => h.style.display)"
    ))
  }
  expect_identical(hole_display(), "")
  pz_js(page, "document.querySelector('#two span').remove()")
  pump_loop(page$child_loop, 0.07)
  expect_identical(hole_display(), "none")
  pz_js(
    page,
    "document.body.insertAdjacentHTML('beforeend', '<div id=zero style=\"position:absolute;left:500px;top:200px;width:0;height:40px\"></div>')"
  )
  page |> pz_annotate_spotlight("#zero", pad = 20, reveal = "none")
  img <- spotlight_image(page, path)
  expect_equal(
    spotlight_rgb(img, page, 500, 220),
    rep(0.4, 3),
    tolerance = 0.04
  )
})

test_that("RTL negative scroll dims the whole viewport but preserves the far-side hole", {
  skip_if_not_installed("png")
  page <- local_rtl_frame_page()
  pz_js(
    page,
    "document.body.style.background = 'white'; window.scrollTo(-1300, 0)"
  )
  skip_if(
    pz_js(page, "window.scrollX") >= 0,
    "browser won't scroll negative in RTL"
  )
  target_x <- pz_js(
    page,
    "document.getElementById('mark').getBoundingClientRect().left + 50"
  )
  expect_gt(target_x, 0)
  expect_lt(target_x, pz_js(page, "window.innerWidth"))
  page |> pz_annotate_spotlight("#mark", reveal = "none")
  path <- withr::local_tempfile(fileext = ".png")
  # Root stills clamp a negative clip x to zero; capture the painted viewport.
  shot <- page$session$Page$captureScreenshot(
    format = "png",
    fromSurface = TRUE
  )
  writeBin(jsonlite::base64_dec(shot$data), path)
  img <- png::readPNG(path)
  expect_equal(spotlight_rgb(img, page, 20, 200), rep(0.4, 3), tolerance = 0.04)
  expect_equal(
    spotlight_rgb(img, page, 950, 200),
    rep(0.4, 3),
    tolerance = 0.04
  )
  expect_equal(
    spotlight_rgb(img, page, target_x, 80),
    c(10, 20, 30) / 255,
    tolerance = 0.04
  )
})

test_that("callouts paint above the spotlight scrim", {
  skip_if_not_installed("png")
  page <- spotlight_page()
  path <- withr::local_tempfile(fileext = ".png")
  page |>
    pz_annotate_spotlight("#one", dim = 0.8, reveal = "none") |>
    pz_annotate_callout(
      "Look here",
      target = "#two",
      side = "bottom",
      color = "rgb(255, 0, 255)",
      reveal = "none"
    )
  img <- spotlight_image(page, path)
  magenta <- img[,, 1] > 0.9 & img[,, 2] < 0.2 & img[,, 3] > 0.9
  expect_true(any(magenta))
})

test_that("spotlight literal defaults preserve the effect and reject NULL", {
  page <- spotlight_page()
  expect_error(pz_annotate_spotlight(page, "#one", pad = NULL), "pad.*NULL")
  expect_error(pz_annotate_spotlight(page, "#one", dim = NULL), "dim")
  expect_error(pz_annotate_spotlight(page, "#one", reveal = NULL), "reveal")
  captured <- NULL
  local_mocked_bindings(annotate_call = function(ctx, els, fn, options, what) {
    captured <<- options
  })
  pz_annotate_spotlight(page, "#one")
  omitted <- captured
  pz_annotate_spotlight(page, "#one", pad = 0, dim = 0.6, reveal = "fade")
  expect_identical(captured, omitted)
  expect_equal(captured$pad, rep(0, 4))
  expect_equal(captured$dim, 0.6)
  expect_identical(captured$reveal, "fade")
})
