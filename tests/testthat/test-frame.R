# Fixture geometry (tests/testthat/fixtures/frame.html), all CSS px,
# viewport-relative; the body is 2000px tall and nothing overlaps:
#   #card       (100, 80)   120x90    rgb(200, 30, 30)
#   #small      (400, 60)    60x45    rgb(30, 120, 200)
#   #wide       (700, 200)  120x60    rgb(30, 200, 120)
#   #corner     (10, 10)    100x50    rgb(120, 30, 200)
#   #bound      (200, 200)  400x400   rgb(240, 240, 240)
#   #inner-tr   (520, 220)   40x40    rgb(200, 200, 30)
#   #low        (50, 1500)  100x60    rgb(200, 120, 30)
#   #deep       (100, 1940)  40x40    rgb(30, 200, 200)
#   #fractional (620.4, 262.6) 200.2x88.8 rgb(60, 60, 60)
# PNG pixel dimensions are round(css_size * dpr); dpr is read live.

test_that("annotated framing includes only attached painted nodes", {
  page <- local_frame_page()
  pz_js(
    page,
    "document.body.insertAdjacentHTML('beforeend', '<div id=outer style=\"position:absolute;left:220px;top:180px;width:80px;height:40px\"><div id=child style=\"width:30px;height:20px\"></div></div><div id=other style=\"position:absolute;left:600px;top:180px;width:40px;height:40px\"></div>')"
  )
  pz_annotate_callout(
    page,
    "Attached",
    target = "#child",
    side = "right",
    reveal = "none"
  )
  pz_annotate_callout(
    page,
    "Unrelated",
    target = "#other",
    side = "right",
    reveal = "none"
  )
  plain <- frame_content_box(page, pz_frame("#outer"))
  decorated <- frame_content_box(
    page,
    pz_frame("#outer", target_box = "annotated")
  )
  expect_equal(plain, c(220, 180, 300, 220))
  expect_gt(decorated[3], plain[3])
  expect_lt(decorated[3], 600)
  plain_png <- withr::local_tempfile(fileext = ".png")
  painted_png <- withr::local_tempfile(fileext = ".png")
  pz_screenshot(page, plain_png, frame = pz_frame("#outer"))
  pz_screenshot(
    page,
    painted_png,
    frame = pz_frame("#outer", target_box = "annotated")
  )
  expect_gt(png_dimensions(painted_png)[1], png_dimensions(plain_png)[1])
  pz_stage_frame(page, "#outer", target_box = "annotated")
  pz_screenshot(page, painted_png)
  expect_gt(png_dimensions(painted_png)[1], png_dimensions(plain_png)[1])
  expect_identical(page_frame(page)$target_box, "annotated")
  pz_js(page, "document.querySelector('#outer').style.left='250px'")
  moved <- frame_content_box(page, pz_frame("#outer", target_box = "annotated"))
  expect_gt(moved[3], decorated[3])

  pz_annotate_clear(page)
  pz_annotate_spotlight(page, "#child", pad = 15, reveal = "none")
  hole <- frame_content_box(page, pz_frame("#outer", target_box = "annotated"))
  expect_equal(hole, c(235, 165, 330, 220), tolerance = 1)
  pz_annotate_clear(page)
  pz_annotate_redact(page, "#child", pad = 30)
  expect_equal(
    frame_content_box(page, pz_frame("#outer", target_box = "annotated")),
    c(250, 180, 330, 220)
  )
  expect_equal(frame_clip(page, frame_effective(page, NULL))$width, 80)
})

test_that("marks add their badge but only for selected targets", {
  page <- local_frame_page()
  spec <- pz_frame("#card", target_box = "annotated")
  expect_equal(frame_content_box(page, spec), c(100, 80, 220, 170))
  pz_annotate(page, "#card", label = "A", reveal = "none")
  pz_annotate(page, "#small", label = "B", reveal = "none")
  box <- frame_content_box(page, spec)
  expect_lt(box[2], 80)
  expect_equal(box[3], 220)
  both <- frame_content_box(
    page,
    pz_frame(list("#card", "#small"), target_box = "annotated")
  )
  expect_gt(both[3], 400)
  scoped <- pz_find(page, "#card")
  expect_equal(
    frame_content_box(scoped, pz_frame(target_box = "annotated")),
    box
  )
  pz_annotate_clear(page)
  expect_equal(frame_content_box(page, spec), c(100, 80, 220, 170))
})

test_that("an inset circle does not enlarge its target frame", {
  page <- local_frame_page()
  pz_annotate(page, "#card", type = "circle", pad = 0, reveal = "none")
  box <- frame_content_box(
    page,
    pz_frame("#card", pad = 0, target_box = "annotated")
  )
  expect_lte(max(abs(box - c(100, 80, 220, 170))), 1)
})

test_that("multi-match marks contribute only the framed match", {
  page <- local_frame_page()
  pz_annotate(page, "#card, #small", label = TRUE, reveal = "none")
  card <- frame_content_box(
    page,
    pz_frame("#card", pad = 0, target_box = "annotated")
  )
  expect_lte(max(abs(card[c(1, 3, 4)] - c(100, 220, 170))), 1)
  expect_gt(card[2], 50)
  expect_lt(card[2], 75)
  expect_lt(card[3], 400)
  small <- frame_content_box(
    page,
    pz_frame("#small", pad = 0, target_box = "annotated")
  )
  expect_gte(small[3], 460)
  expect_lt(small[2], 60)
})

test_that("pz_frame returns a normalized spec", {
  spec <- pz_frame()
  expect_s3_class(spec, "paparazzi_frame")
  # Unset fields stay NULL: they inherit at capture time
  for (field in names(spec)) {
    expect_null(spec[[field]])
  }
  expect_identical(pz_frame(target_box = "annotated")$target_box, "annotated")

  expect_identical(pz_frame(pad = 32)$pad, rep(32, 4))
  expect_identical(pz_frame(pad = c(1, 2, 3, 4))$pad, c(1, 2, 3, 4))
  expect_identical(pz_frame(offset = 5)$offset, c(5, 5))
  expect_identical(pz_frame(when = "start")$when, "start")

  # anchor normalizes to its sorted token set
  expect_identical(pz_frame(anchor = "top-right")$anchor, c("right", "top"))
  expect_identical(pz_frame(anchor = "Top Right")$anchor, c("right", "top"))

  # target and bounds are promoted to loc lists, eagerly
  expect_identical(pz_frame("#card")$target[[1]]$css, "#card")
  expect_length(pz_frame(list("#card", pz_loc("#small")))$target, 2)
  expect_identical(pz_frame(bounds = "#bound")$bounds[[1]]$css, "#bound")
})

test_that("pz_frame validates its inputs", {
  expect_error(pz_frame(bogus = 1), "empty")

  expect_error(pz_frame(ratio = 0), class = "paparazzi_error_input")
  expect_error(pz_frame(ratio = -1), class = "paparazzi_error_input")
  expect_error(pz_frame(ratio = "wide"), class = "rlang_error")

  expect_error(pz_frame(pad = c(1, 2)), class = "paparazzi_error_input")
  expect_error(pz_frame(pad = NA), class = "paparazzi_error_input")
  expect_error(pz_frame(pad = "32"), class = "paparazzi_error_input")

  expect_error(pz_frame(offset = c(1, 2, 3)), class = "paparazzi_error_input")
  expect_error(pz_frame(offset = NA_real_), class = "paparazzi_error_input")

  expect_error(pz_frame(when = "middle"), "start")
  expect_error(pz_frame(target_box = "page"), "annotated")

  expect_error(pz_frame(42), class = "rlang_error")
  expect_error(pz_frame(list()), class = "paparazzi_error_target")
  expect_error(pz_frame(bounds = list()), class = "paparazzi_error_target")
})

test_that("print.paparazzi_frame shows the spec", {
  expect_output(
    print(pz_frame("#card", ratio = 16 / 9, pad = 32)),
    "paparazzi_frame"
  )
  expect_output(
    print(pz_frame(target_box = "annotated")),
    "target_box: annotated"
  )
})

test_that("parse_direction normalizes spaces, hyphens and case", {
  expect_identical(parse_direction("top"), "top")
  expect_identical(parse_direction("Top Right"), c("right", "top"))
  expect_identical(parse_direction("right-top"), c("right", "top"))
  expect_identical(parse_direction(" top  right "), c("right", "top"))
  expect_identical(parse_direction("center"), "center")
  expect_error(parse_direction(42), class = "rlang_error")
  expect_error(parse_direction(""), class = "paparazzi_error_input")
})

test_that("parse_direction rejects invalid tokens and combinations", {
  # Invalid combinations error with the valid values listed.
  expect_error(
    pz_frame(anchor = "top bottom"),
    "left top",
    class = "paparazzi_error_input"
  )
  expect_error(
    pz_frame(anchor = "top center"),
    class = "paparazzi_error_input"
  )
  expect_error(
    pz_frame(anchor = "sideways"),
    "bottom right",
    class = "paparazzi_error_input"
  )
})

test_that("parse_direction takes a restricted valid set", {
  # Cursor and staging restrict the shared parser to a subset of directions.
  sides <- list(c("left"), c("right"))
  expect_identical(parse_direction("right", valid = sides), "right")
  expect_error(parse_direction("top", valid = sides), '"left"')
})

test_that("frame_apply pads, offsets, grows and clamps", {
  box <- c(100, 80, 220, 170)
  expect_identical(
    frame_apply(filled_frame(), box),
    box
  )
  expect_identical(
    frame_apply(filled_frame(pad = c(10, 20, 30, 40)), box),
    c(60, 70, 240, 200)
  )
  expect_identical(
    frame_apply(filled_frame(pad = 10, offset = c(5, -8)), box),
    c(95, 62, 235, 172)
  )
  expect_identical(
    frame_apply(filled_frame(), box, list(a = c(150, 150, 300, 300))),
    c(150, 150, 220, 170)
  )
})

test_that("frame_apply grows the shorter side to reach the ratio by anchor", {
  box <- c(400, 60, 460, 105) # 60x45 (4:3)
  expect_identical(
    frame_apply(filled_frame(ratio = 16 / 9, anchor = "left"), box),
    c(400, 60, 480, 105)
  )
  expect_identical(
    frame_apply(filled_frame(ratio = 16 / 9, anchor = "right"), box),
    c(380, 60, 460, 105)
  )
  expect_identical(
    frame_apply(filled_frame(ratio = 16 / 9), box),
    c(390, 60, 470, 105)
  )

  tall <- c(700, 200, 820, 260) # 120x60 (2:1)
  expect_identical(
    frame_apply(filled_frame(ratio = 1, anchor = "top"), tall),
    c(700, 200, 820, 320)
  )
  expect_identical(
    frame_apply(filled_frame(ratio = 1, anchor = "bottom"), tall),
    c(700, 140, 820, 260)
  )
  expect_identical(
    frame_apply(filled_frame(ratio = 1), tall),
    c(700, 170, 820, 290)
  )
  # A corner anchors both axes: growing width pins to the left edge.
  expect_identical(
    frame_apply(filled_frame(ratio = 16 / 9, anchor = "top left"), box),
    c(400, 60, 480, 105)
  )

  # Never shrinks: a box already at the ratio is unchanged.
  expect_identical(
    frame_apply(filled_frame(ratio = 4 / 3), box),
    box
  )
})

test_that("frame_apply errors on empty or out-of-clamp regions", {
  expect_error(
    frame_apply(filled_frame(pad = -50), c(0, 0, 30, 30)),
    "empty",
    class = "paparazzi_error_frame"
  )
  expect_error(
    frame_apply(
      filled_frame(),
      c(0, 0, 10, 10),
      list(bounds = c(50, 50, 100, 100))
    ),
    "outside",
    class = "paparazzi_error_frame"
  )
})

test_that("frame_region rejects an empty rounded box", {
  expect_identical(
    frame_region(c(1, 2, 9, 12)),
    list(x = 1, y = 2, width = 8, height = 10)
  )
  expect_error(
    frame_region(c(2, 3, 2, 10)),
    "The framed region is empty.",
    class = "paparazzi_error_frame",
    fixed = TRUE
  )
  expect_error(
    frame_region(c(2, 3, 10, 3)),
    class = "paparazzi_error_frame"
  )
})

test_that("frame_round rounds to whole or even pixels", {
  expect_identical(
    frame_round(c(0.4, 0.6, 10.6, 12.4)),
    c(0, 1, 11, 12)
  )
  expect_identical(
    frame_round(c(1.2, 3.7, 10.8, 12.1), even = TRUE),
    c(2, 4, 10, 12)
  )
})

test_that("frame_round rounds constrained edges inward", {
  # Edges a clamp fixed in place must not escape the CSS bounds: a
  # bound beginning at 200.4 must not become a clip at 200.
  expect_identical(
    frame_round(
      c(200.4, 100.6, 300.5, 400.2),
      pinned = c(TRUE, TRUE, TRUE, TRUE)
    ),
    c(201, 101, 300, 400)
  )
  # Mixed: pinned left/top round inward, free right/bottom stay
  # nearest.
  expect_identical(
    frame_round(
      c(200.4, 100.6, 310.6, 412.4),
      pinned = c(TRUE, TRUE, FALSE, FALSE)
    ),
    c(201, 101, 311, 412)
  )
  # Even mode keeps the same intent: inward for pinned, nearest even
  # otherwise.
  expect_identical(
    frame_round(
      c(200.4, 101.4, 300.6, 402.2),
      pinned = c(TRUE, TRUE, TRUE, TRUE),
      even = TRUE
    ),
    c(202, 102, 300, 402)
  )
})

test_that("a pad-only frame pads the capture on all sides", {
  page <- local_frame_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)

  # #card (100, 80, 120x90) + 32 on each side: (68, 48) 184x154.
  pz_screenshot(page, path, frame = pz_frame("#card", pad = 32))
  expect_identical(png_dimensions(path), as.integer(round(c(184, 154) * dpr)))
  # The card sits 32px inside the capture: red at (40, 40); the point
  # left of it (page 78, 148) is padding background -- clear of
  # #corner, which overlaps the padded region.
  expect_png_pixel(page, path, 40, 40, c(200, 30, 30), dpr = dpr)
  expect_png_pixel(page, path, 10, 100, c(255, 255, 255), dpr = dpr)
})

test_that("pad accepts c(top, right, bottom, left)", {
  page <- local_frame_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)

  # #card + 10/20/30/40: (60, 70) 180x130.
  pz_screenshot(
    page,
    path,
    frame = pz_frame("#card", pad = c(10, 20, 30, 40))
  )
  expect_identical(png_dimensions(path), as.integer(round(c(180, 130) * dpr)))
})

test_that("offset nudges the capture after padding", {
  page <- local_frame_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)

  # #card + pad 10 = (90, 70) 140x110; offset (5, -8) moves it to
  # (95, 62), so the card starts at (5, 18) inside the capture.
  pz_screenshot(
    page,
    path,
    frame = pz_frame("#card", pad = 10, offset = c(5, -8))
  )
  expect_identical(png_dimensions(path), as.integer(round(c(140, 110) * dpr)))
  expect_png_pixel(page, path, 20, 30, c(200, 30, 30), dpr = dpr)
  expect_png_pixel(page, path, 2, 5, c(255, 255, 255), dpr = dpr)
})

test_that("ratio grows the shorter side, placing content by anchor", {
  page <- local_frame_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)

  # #small is 60x45 (4:3); 16/9 grows the width to 80. With
  # anchor = "left" the content pins to the left edge of the frame.
  pz_screenshot(
    page,
    path,
    frame = pz_frame("#small", ratio = 16 / 9, anchor = "left")
  )
  expect_identical(png_dimensions(path), as.integer(round(c(80, 45) * dpr)))
  expect_png_pixel(page, path, 30, 22, c(30, 120, 200), dpr = dpr)
  expect_png_pixel(page, path, 70, 22, c(255, 255, 255), dpr = dpr)

  # anchor = "top right": the vertical token is unused while growing
  # width; "right" pins the content to the right edge.
  pz_screenshot(
    page,
    path,
    frame = pz_frame("#small", ratio = 16 / 9, anchor = "top right")
  )
  expect_identical(png_dimensions(path), as.integer(round(c(80, 45) * dpr)))
  expect_png_pixel(page, path, 50, 22, c(30, 120, 200), dpr = dpr)
  expect_png_pixel(page, path, 10, 22, c(255, 255, 255), dpr = dpr)

  # Growing the height instead: #wide is 120x60 (2:1); ratio 1 grows
  # the height to 120, content at the bottom.
  pz_screenshot(
    page,
    path,
    frame = pz_frame("#wide", ratio = 1, anchor = "bottom")
  )
  expect_identical(png_dimensions(path), as.integer(round(c(120, 120) * dpr)))
  expect_png_pixel(page, path, 60, 100, c(30, 200, 120), dpr = dpr)
  expect_png_pixel(page, path, 60, 20, c(255, 255, 255), dpr = dpr)
})

test_that("ratio + pad compose in order, and anchor spellings are equivalent", {
  page <- local_frame_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)

  # #small + pad 24 = (376, 36) 108x93; ratio 16/9 grows the width to
  # 165.33, centered horizontally: (347.33, 36) -- whole-pixel rounding
  # gives a 166x93 capture. anchor = "top" only matters vertically,
  # so the horizontal placement is centered.
  spec_a <- pz_frame("#small", ratio = 16 / 9, pad = 24, anchor = "top")
  pz_screenshot(page, path, frame = spec_a)
  expect_identical(png_dimensions(path), as.integer(round(c(166, 93) * dpr)))
  expect_png_pixel(page, path, 80, 46, c(30, 120, 200), dpr = dpr)
  expect_png_pixel(page, path, 10, 46, c(255, 255, 255), dpr = dpr)

  # Spellings of the same anchor build identical specs.
  expect_identical(
    pz_frame(ratio = 16 / 9, anchor = "right-top"),
    pz_frame(ratio = 16 / 9, anchor = "top-right")
  )
})

test_that("bounds clamp the frame to their box", {
  page <- local_frame_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)

  # #inner-tr + 32 = (488, 188) 104x92; #bound starts at y = 200, so
  # the top pad is cut: (488, 200) 104x92.
  pz_screenshot(
    page,
    path,
    frame = pz_frame("#inner-tr", pad = 32, bounds = "#bound")
  )
  expect_identical(png_dimensions(path), as.integer(round(c(104, 92) * dpr)))
  # #inner-tr starts at (32, 20) inside the clamped capture.
  expect_png_pixel(page, path, 40, 40, c(200, 200, 30), dpr = dpr)
  # Below the cut pad: #bound's background, not the page background.
  expect_png_pixel(page, path, 100, 5, c(240, 240, 240), dpr = dpr)
})

test_that("a fractional bound rounds the clip inward on every edge", {
  page <- local_frame_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)

  # #fractional begins at (620.4, 262.6); with pad 120 around #wide,
  # the bound clamps all four edges of the frame, and inward rounding
  # keeps every pixel inside it: left 620.4 becomes 621, not 620.
  pz_screenshot(
    page,
    path,
    frame = pz_frame("#wide", pad = 120, bounds = "#fractional")
  )
  expect_identical(png_dimensions(path), as.integer(round(c(199, 88) * dpr)))
  expect_png_pixel(page, path, 0, 0, c(60, 60, 60), dpr = dpr)
  expect_png_pixel(page, path, 198, 87, c(60, 60, 60), dpr = dpr)
})

test_that("the frame clamps to the page at the top-left corner", {
  page <- local_frame_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)

  # #corner + 32 = (-22, -22) 142x92; the page starts at (0, 0), so
  # the frame clamps to (0, 0) 142x92.
  pz_screenshot(page, path, frame = pz_frame("#corner", pad = 32))
  expect_identical(png_dimensions(path), as.integer(round(c(142, 92) * dpr)))
  expect_png_pixel(page, path, 30, 30, c(120, 30, 200), dpr = dpr)
  expect_png_pixel(page, path, 5, 5, c(255, 255, 255), dpr = dpr)
})

test_that("the frame clamps to the page at the bottom edge", {
  page <- local_frame_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)

  # #deep (100, 1940, 40x40) + 32 reaches y = 2012, past the
  # 2000px-tall page: the frame clamps to (68, 1908) 104x92.
  pz_screenshot(page, path, frame = pz_frame("#deep", pad = 32))
  expect_identical(png_dimensions(path), as.integer(round(c(104, 92) * dpr)))
})

test_that("a below-fold frame captures without scrolling", {
  page <- local_frame_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)

  # #low sits at y = 1500, far below the viewport; the framed capture
  # still must not scroll the page as a side effect.
  pz_screenshot(page, path, frame = pz_frame("#low", pad = 20))
  expect_identical(png_dimensions(path), as.integer(round(c(140, 100) * dpr)))
  expect_png_pixel(page, path, 70, 50, c(200, 120, 30), dpr = dpr)
  expect_equal(pz_js(page, "window.scrollY"), 0)
})

test_that("the frame clamps against geometry read after resolution auto-waits", {
  page <- local_frame_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)

  # A late element expands the document while the target resolution
  # auto-waits for it; the clamp must see the expanded document, not
  # the pre-wait 2000px one.
  pz_js(
    page,
    "setTimeout(() => {
      const el = document.createElement('div');
      el.id = 'late';
      el.style.cssText =
        'position:absolute;left:100px;top:2600px;width:40px;height:40px;background:rgb(10,20,30)';
      document.body.appendChild(el);
      document.body.style.height = '2700px';
    }, 300)"
  )
  pz_screenshot(page, path, frame = pz_frame("#late", pad = 32))
  # #late (100, 2600) 40x40 + 32 = (68, 2568) 104x104, entirely below
  # the pre-expansion document: only fresh geometry keeps it capturable.
  expect_identical(png_dimensions(path), as.integer(round(c(104, 104) * dpr)))
  expect_equal(
    pz_js(page, "document.documentElement.scrollHeight"),
    2700
  )
})

test_that("a frame's own target wins over the scope", {
  page <- local_frame_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)

  # Scoped to the body, the frame's own #card target wins over the
  # scope's box: (68, 48) 184x154, not the page-sized body box.
  pz_screenshot(
    pz_find(page, "body"),
    path,
    frame = pz_frame("#card", pad = 32)
  )
  expect_identical(png_dimensions(path), as.integer(round(c(184, 154) * dpr)))
  expect_png_pixel(page, path, 40, 40, c(200, 30, 30), dpr = dpr)
})

test_that("a frame unions a multi-element target", {
  page <- local_frame_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)

  # #card (100, 80, 120x90) + #small (400, 60, 60x45): the union is
  # (100, 60) 360x110, and the frame pads it.
  pz_screenshot(
    page,
    path,
    frame = pz_frame(list("#card", "#small"), pad = 10)
  )
  expect_identical(png_dimensions(path), as.integer(round(c(380, 130) * dpr)))
})

test_that("an identity frame at the root captures the viewport", {
  page <- local_frame_page()
  plain <- withr::local_tempfile(fileext = ".png")
  framed <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)

  pz_screenshot(page, plain)
  pz_screenshot(page, framed, frame = pz_frame())
  expect_identical(png_dimensions(framed), png_dimensions(plain))
})

test_that("an identity frame keeps the viewport on negative RTL scroll", {
  page <- local_rtl_frame_page()
  plain <- withr::local_tempfile(fileext = ".png")
  framed <- withr::local_tempfile(fileext = ".png")

  # The RTL fixture overflows left, so scrolling into it makes
  # scrollX negative and the viewport's left portion sits at negative
  # document x. The document clamp must anchor to the real document
  # span, or an identity frame narrows by |scrollX|.
  pz_js(page, "window.scrollTo(-100, 0)")
  skip_if(
    pz_js(page, "window.scrollX") >= 0,
    "browser won't scroll negative in RTL"
  )

  pz_screenshot(page, plain)
  pz_screenshot(page, framed, frame = pz_frame())
  expect_identical(png_dimensions(framed), png_dimensions(plain))
})

test_that("a frame on RTL left-overflow content captures it", {
  page <- local_rtl_frame_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)

  # #mark sits in the left overflow, at negative document x
  # (around [-1208, -1108] for a 992px viewport): clamping to
  # [0, scrollWidth] would reject it as outside the page instead of
  # capturing it.
  skip_if(
    pz_js(page, "document.body.getBoundingClientRect().left") >= 0,
    "browser doesn't overflow RTL documents to the left"
  )

  pz_screenshot(page, path, frame = pz_frame("#mark", pad = 10))
  # #mark 100x60 + 10 on each side; the negative document origin
  # shifts to 0 with the size preserved.
  expect_identical(png_dimensions(path), as.integer(round(c(120, 80) * dpr)))
})

test_that("a frame on a scoped context uses the scope's box", {
  page <- local_frame_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)

  # The scope pins #card; with no frame target, the frame pads the
  # scope's box: (90, 70) 140x110.
  ctx <- pz_find(page, "#card")
  pz_screenshot(ctx, path, frame = pz_frame(pad = 10))
  expect_identical(png_dimensions(path), as.integer(round(c(140, 110) * dpr)))
})

test_that("pz_stage_frame sets the page's default framing", {
  page <- local_frame_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)

  # A target-less default frames the locator the call promotes.
  page |> pz_stage_frame(pad = 32) |> pz_screenshot(path, frame = "#card")
  expect_identical(png_dimensions(path), as.integer(round(c(184, 154) * dpr)))

  # A default ratio frames target-less calls via the frame's target.
  page |> pz_stage_frame("#card", pad = 32) |> pz_screenshot(path)
  expect_identical(png_dimensions(path), as.integer(round(c(184, 154) * dpr)))

  # Ratio-only defaults grow their target.
  page |>
    pz_stage_frame(ratio = 16 / 9) |>
    pz_screenshot(path, frame = "#small")
  expect_identical(png_dimensions(path), as.integer(round(c(80, 45) * dpr)))
})

test_that("an explicit frame's fields win and leave the default untouched", {
  page <- local_frame_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)

  pz_stage_frame(page, pad = 32)
  # An explicit field wins: pad = 8 over pad = 32, giving 136x106.
  pz_screenshot(page, path, frame = pz_frame("#card", pad = 8))
  expect_identical(png_dimensions(path), as.integer(round(c(136, 106) * dpr)))
  # The staged default itself is untouched by the explicit frame.
  pz_screenshot(page, path, frame = "#card")
  expect_identical(png_dimensions(path), as.integer(round(c(184, 154) * dpr)))
})

test_that("frame = FALSE opts out of the default for one call", {
  page <- local_frame_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)

  pz_stage_frame(page, pad = 32)
  pz_find(page, "#card") |> pz_screenshot(path, frame = FALSE)
  expect_identical(png_dimensions(path), as.integer(round(c(120, 90) * dpr)))
})

test_that("an explicit frame without a target frames the viewport under a targetless default", {
  page <- local_frame_page()
  path <- withr::local_tempfile(fileext = ".png")
  viewport <- withr::local_tempfile(fileext = ".png")

  dpr <- page_dpr(page)

  pz_stage_frame(page, pad = 32)
  pz_screenshot(page, viewport, frame = FALSE)
  pz_screenshot(page, path, frame = pz_frame(pad = 8))
  # The padded viewport clamps to the document: the left, top and right
  # pads fall off the page, and the bottom pad reaches below the fold.
  expect_identical(
    png_dimensions(path),
    png_dimensions(viewport) + c(0L, as.integer(round(8 * dpr)))
  )
})

test_that("pz_stage_frame(NULL) clears the default", {
  page <- local_frame_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)

  pz_stage_frame(page, pad = 32)
  pz_stage_frame(page, NULL)
  pz_screenshot(page, path, frame = "#card")
  expect_identical(png_dimensions(path), as.integer(round(c(120, 90) * dpr)))
})

test_that("a staged frame does not leak to other pages", {
  page <- local_frame_page()
  other <- local_frame_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(other)

  pz_stage_frame(page, pad = 32)
  pz_screenshot(other, path, frame = "#card")
  expect_identical(png_dimensions(path), as.integer(round(c(120, 90) * dpr)))
})

test_that("pz_stage_frame validates its inputs", {
  page <- local_frame_page()

  expect_invisible(pz_stage_frame(page, pad = 32))

  expect_error(
    pz_stage_frame(page, "#card", bogus = 1),
    "unnamed",
    class = "paparazzi_error_input"
  )
  expect_error(
    pz_stage_frame(page, NULL, pad = 32),
    "clears",
    class = "paparazzi_error_input"
  )
  expect_error(pz_stage_frame(page, 42), class = "rlang_error")
  expect_error(
    pz_stage_frame(page, anchor = "sideways"),
    class = "paparazzi_error_input"
  )
})

test_that("pz_screenshot rejects non-frame frame values", {
  page <- local_frame_page()
  path <- withr::local_tempfile(fileext = ".png")

  expect_error(
    pz_screenshot(page, path, frame = TRUE),
    class = "paparazzi_error_unsupported"
  )
  expect_error(
    pz_screenshot(page, path, frame = 42),
    class = "paparazzi_error_unsupported"
  )
  # A bare locator promotes; an empty one matches nothing and errors
  expect_error(
    pz_screenshot(page, path, frame = list()),
    class = "paparazzi_error_target"
  )
  # Nothing was written before the errors.
  expect_false(file.exists(path))
})

test_that("framing errors when the region leaves the bounds", {
  page <- local_frame_page()
  path <- withr::local_tempfile(fileext = ".png")

  # #card (y 80..170) and #deep (y 1940..1980) never overlap.
  expect_error(
    pz_screenshot(
      page,
      path,
      frame = pz_frame("#card", bounds = "#deep")
    ),
    "outside",
    class = "paparazzi_error_frame"
  )
})

test_that("framing errors when the region collapses", {
  page <- local_frame_page()
  path <- withr::local_tempfile(fileext = ".png")

  # A pad more negative than the content is wide collapses the box.
  expect_error(
    pz_screenshot(
      page,
      path,
      frame = pz_frame("#small", pad = -100)
    ),
    "empty",
    class = "paparazzi_error_frame"
  )
  expect_false(file.exists(path))
})

test_that("a framed screenshot returns its context invisibly", {
  page <- local_frame_page()
  path <- withr::local_tempfile(fileext = ".png")

  ctx <- pz_find(page, "#card")
  expect_invisible(pz_screenshot(ctx, path, frame = pz_frame(pad = 10)))
  expect_identical(
    withVisible(pz_screenshot(ctx, path, frame = pz_frame(pad = 10)))$value,
    ctx
  )
})

test_that("pz_frame fields default to NULL, filled only at capture time", {
  spec <- pz_frame("#card")
  expect_s3_class(spec, "paparazzi_frame")
  fields <- c(
    "ratio",
    "pad",
    "offset",
    "anchor",
    "bounds",
    "when",
    "target_box",
    "zoom"
  )
  for (field in fields) {
    expect_null(spec[[field]])
  }
  expect_identical(pz_frame(zoom = 2)$zoom, 2)
})

test_that("pz_frame validates zoom", {
  expect_error(pz_frame(zoom = 0), "greater than zero")
  expect_error(pz_frame(zoom = -1), class = "rlang_error")
  expect_error(pz_frame(zoom = Inf), class = "rlang_error")
  expect_error(pz_frame(zoom = "2x"), class = "rlang_error")
})

test_that("frame_effective promotes bare locators and fills per-field", {
  page <- local_frame_page()

  promoted <- frame_effective(page, "#card")
  expect_s3_class(promoted, "paparazzi_frame")
  expect_identical(promoted$target[[1]]$css, "#card")
  expect_identical(promoted$pad, rep(0, 4))
  expect_identical(promoted$offset, c(0, 0))
  expect_identical(promoted$anchor, "center")
  expect_identical(promoted$when, "stop")
  expect_identical(promoted$target_box, "element")
  expect_null(promoted$zoom)

  listed <- frame_effective(page, list("#card", pz_loc("#small")))
  expect_length(listed$target, 2)

  pz_stage_frame(page, "#small", pad = 24, ratio = 2)
  # Explicit beats staged; staged beats the built-in default. At the
  # root, the staged target applies too.
  filled <- frame_effective(page, pz_frame(pad = 8))
  expect_identical(filled$pad, rep(8, 4))
  expect_identical(filled$ratio, 2)
  expect_identical(filled$target[[1]]$css, "#small")
  expect_identical(filled$anchor, "center")
  # frame = NULL resolves the staged recipe itself
  expect_identical(frame_effective(page, NULL)$pad, rep(24, 4))
  # FALSE opts out entirely
  expect_false(frame_effective(page, FALSE))
  expect_error(
    frame_effective(page, TRUE),
    class = "paparazzi_error_unsupported"
  )
})

test_that("the scope beats the staged target, which beats the viewport", {
  page <- local_frame_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)

  pz_stage_frame(page, "#small", pad = 24)
  # Root: the staged target frames #small (400, 60) 60x45 + 24
  pz_screenshot(page, path)
  expect_identical(png_dimensions(path), as.integer(round(c(108, 93) * dpr)))
  # Scoped: the scope's box wins over the staged target
  pz_find(page, "#card") |> pz_screenshot(path)
  expect_identical(png_dimensions(path), as.integer(round(c(168, 138) * dpr)))
  # An explicit spec target wins over the scope
  pz_find(page, "body") |> pz_screenshot(path, frame = "#small")
  expect_identical(png_dimensions(path), as.integer(round(c(108, 93) * dpr)))
  # A scoped spec keeps its target unset: the scope applies at measure time
  spec <- frame_effective(pz_find(page, "#card"), pz_frame(pad = 8))
  expect_null(spec$target)
})

test_that("resolved frame specs keep every field, so `$target` stays exact", {
  page <- local_frame_page()
  fields <- names(pz_frame())
  expect_named(frame_fill(pz_frame()), fields, ignore.order = TRUE)
  expect_named(
    frame_fill(pz_frame(), defaults = frame_camera_defaults),
    fields,
    ignore.order = TRUE
  )

  pz_stage_frame(page, "#small", pad = 24)
  scoped <- pz_find(page, "#card")
  for (spec in list(
    frame_effective(page, NULL),
    frame_effective(page, pz_frame(pad = 8)),
    frame_effective(scoped, NULL),
    frame_effective(scoped, pz_frame(pad = 8))
  )) {
    expect_named(spec, fields, ignore.order = TRUE)
  }
  expect_null(frame_effective(scoped, NULL)$target)
})

test_that("a staged frame keeps its unset fields NULL", {
  page <- local_frame_page()

  pz_stage_frame(page, pad = 24)
  spec <- page_frame(page)
  expect_identical(spec$pad, rep(24, 4))
  expect_null(spec$ratio)
  expect_null(spec$target)

  pz_stage_frame(page, "#card", zoom = 2)
  expect_identical(page_frame(page)$zoom, 2)
  expect_identical(page_frame(page)$target[[1]]$css, "#card")
})

test_that("an explicit frame inherits unset fields from the staged frame", {
  page <- local_frame_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)

  pz_stage_frame(page, "#card", pad = 32)
  # Only ratio is explicit; pad and target inherit: (68, 48) 184x154
  # grown to 2:1 is 308x154.
  pz_screenshot(page, path, frame = pz_frame(ratio = 2))
  expect_identical(png_dimensions(path), as.integer(round(c(308, 154) * dpr)))
  # An explicit field wins over the staged one.
  pz_screenshot(page, path, frame = pz_frame(pad = 8))
  expect_identical(png_dimensions(path), as.integer(round(c(136, 106) * dpr)))
})

test_that("numeric zoom fixes the still region at view / zoom", {
  page <- local_zoom_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)

  # #mid is centered in the 800x600 viewport: zoom 2 crops 400x300
  # centered on it -- a smaller PNG, cropped only, never resampled up.
  pz_screenshot(page, path, frame = pz_frame("#mid", zoom = 2))
  expect_identical(png_dimensions(path), as.integer(round(c(400, 300) * dpr)))
  expect_png_pixel(page, path, 200, 150, c(200, 30, 30), dpr = dpr)

  # zoom 1 on the centered target is the full view
  pz_screenshot(page, path, frame = pz_frame("#mid", zoom = 1))
  expect_identical(png_dimensions(path), as.integer(round(c(800, 600) * dpr)))
})

test_that("zoom places the padded target by anchor and honors ratio", {
  page <- local_zoom_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)

  # anchor "top left": the region's top-left is the padded target's
  pz_screenshot(
    page,
    path,
    frame = pz_frame("#mid", pad = 10, zoom = 2, anchor = "top left")
  )
  expect_identical(png_dimensions(path), as.integer(round(c(400, 300) * dpr)))
  # (20, 20) in the capture is (310, 210) on the page: inside #mid
  expect_png_pixel(page, path, 20, 20, c(200, 30, 30), dpr = dpr)
  # (5, 5) is (295, 195): the pad ring, i.e. the page background
  expect_png_pixel(page, path, 5, 5, c(255, 255, 255), dpr = dpr)

  # ratio sets the aspect inside view / zoom: the largest 1:1 box
  pz_screenshot(page, path, frame = pz_frame("#mid", zoom = 2, ratio = 1))
  expect_identical(png_dimensions(path), as.integer(round(c(300, 300) * dpr)))
})
