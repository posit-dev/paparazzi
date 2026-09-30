test_that("camera shot includes a callout only with explicit annotated target box", {
  skip_if_no_av()
  page <- local_record_page()
  pz_js(
    page,
    "document.body.insertAdjacentHTML('beforeend', '<div id=shot style=\"position:absolute;left:220px;top:180px;width:80px;height:40px\"></div>')"
  )
  pz_stage(page, camera_follow = FALSE)
  pz_stage_frame(page, "#shot", target_box = "annotated")
  out <- withr::local_tempfile(fileext = ".mp4")
  pz_record_start(page, out, hold = c(0, 0))
  defer_record_stop(page)
  pz_annotate_callout(
    page,
    "Attached",
    target = "#shot",
    side = "right",
    reveal = "none"
  )
  expect_error(pz_camera(page, "#shot", target_box = "all"), "annotated")
  pz_camera(page, "#shot", pad = 0, duration = 0)
  rec <- page_recorder(page)
  expect_equal(rec$camera[[1]]$box, c(220, 180, 300, 220))
  pz_camera(page, "#shot", pad = 0, duration = 0, target_box = "annotated")
  expect_gt(rec$camera[[2]]$box[3], 300)
  pz_camera(page, "#shot", pad = 0, duration = 0, target_box = "element")
  expect_equal(rec$camera[[3]]$box, c(220, 180, 300, 220))
  pz_record_stop(page)
})

test_that("live screencast scroll metadata matches captured content", {
  skip_if_no_av()
  testthat::skip_if_not_installed("png")
  html <- withr::local_tempfile(
    lines = '<!doctype html><style>body{margin:0;height:1600px}#marker{position:absolute;top:520px;left:20px;width:100px;height:100px;background:rgb(255,0,0)}</style><div id="marker"></div>',
    fileext = ".html"
  )
  page <- local_page(html, width = 640, height = 480, scale = 2)
  out <- withr::local_tempfile(fileext = ".mp4")
  pz_record_start(
    page,
    out,
    method = "screencast",
    hold = c(0, 0),
    keep_frames = TRUE
  )
  rec <- page_recorder(page)
  withr::defer(unlink(rec$frames_dir, recursive = TRUE))
  defer_record_stop(page)
  pz_js(page, "window.scrollTo(0,500)")
  pz_poll(
    function() {
      any(vapply(
        rec$scroll,
        function(x) length(x) == 2 && abs(x[2] - 500) < 2,
        logical(1)
      ))
    },
    timeout = 3,
    loop = page$page$child_loop,
    what = "scrolled screencast metadata"
  )
  index <- which(vapply(
    rec$scroll,
    function(x) length(x) == 2 && abs(x[2] - 500) < 2,
    logical(1)
  ))[[1]]
  expect_equal(rec$scroll[[index]], c(0, 500), tolerance = 2)
  expect_equal(rec$camera_viewport_width, 640)
  expect_equal(png_dimensions(rec$files[[index]]), c(640L, 480L))
  expect_equal(
    unname(png::readPNG(rec$files[[index]])[50, 30, 1:3]),
    c(1, 0, 0)
  )
  pz_record_stop(page)
})

test_that("camera calls are no-ops outside recording and reset with the recorder", {
  skip_if_no_av()
  page <- local_record_page()
  expect_identical(
    withVisible(pz_camera(page, "#missing", zoom = 2))$value,
    page
  )
  expect_error(pz_camera(page, "#missing", zoom = -1), "zoom")
  expect_error(pz_camera(page, "#missing", zoom = Inf), "zoom")
  expect_error(pz_camera(page, "#missing", duration = Inf), "duration")
  pz_js(
    page,
    "document.body.appendChild(document.createElement('p')).id = 'gone'"
  )
  gone <- pz_find(page, "#gone")
  pz_js(page, "document.getElementById('gone').remove()")
  expect_identical(pz_camera(gone), gone)
  expect_error(pz_camera(page), "target")
  expect_identical(withVisible(pz_camera_reset(page))$value, page)
  out <- withr::local_tempfile(fileext = ".mp4")
  pz_record_start(page, out, hold = c(0, 0))
  defer_record_stop(page)
  expect_error(pz_camera(page), "target")
  expect_error(pz_camera(page, "#box", zoom = 0), "zoom")
  pz_camera(page, "#box", zoom = 2, duration = 0)
  expect_length(page_recorder(page)$camera, 1)
  expect_equal(page_recorder(page)$camera[[1]]$box, c(16, 6, 164, 114))
  suppressWarnings(pz_record_stop(page))
  pz_record_start(page, out, hold = c(0, 0))
  expect_length(page_recorder(page)$camera, 0)
  pz_record_stop(page)
})

test_that("camera zoom and reset change MP4 and GIF content, not dimensions", {
  skip_if_no_av()
  testthat::skip_if_not_installed("gifski")
  testthat::skip_if_not_installed("png")
  html <- withr::local_tempfile(
    lines = '<!doctype html><style>body{margin:0;background:white}#red,#blue{position:absolute;width:100px;height:100px}#red{left:100px;top:80px;background:red}#blue{left:500px;top:280px;background:blue}</style><div id="red"></div><div id="blue"></div>',
    fileext = ".html"
  )
  page <- local_page(html, width = 640, height = 480, scale = 1)
  for (ext in c("mp4", "gif")) {
    out <- withr::local_tempfile(fileext = paste0(".", ext))
    pz_record_start(page, out, fps = 10, hold = c(0.2, 0.2))
    defer_record_stop(page)
    pz_camera(page, "#red", zoom = 2, duration = 0.2)
    pz_wait(page, 0.25)
    pz_camera_reset(page)
    pz_wait(page, 0.2)
    suppressWarnings(pz_record_stop(page))
    info <- recorded_video_info(out)
    expect_equal(c(info$width, info$height), c(640, 480))
    expect_gte(info$duration, 0.9)
    decoded <- tempfile("camera-decoded-")
    withr::defer(unlink(decoded, recursive = TRUE))
    frames <- av_video_images_quiet(out, destdir = decoded, format = "png")
    expect_gte(length(frames), 8)
    red_at_blue <- function(file) png::readPNG(file)[330, 550, 1]
    expect_lt(red_at_blue(frames[[1]]), 0.2)
    expect_gt(red_at_blue(frames[[length(frames) %/% 2]]), 0.7)
    expect_lt(red_at_blue(tail(frames, 1)), 0.2)
  }
})

test_that("camera shot tracks page target after a scrolled poll capture", {
  skip_if_no_av()
  testthat::skip_if_not_installed("png")
  html <- withr::local_tempfile(
    lines = '<!doctype html><style>body{margin:0;height:1500px;background:white}#red{position:absolute;left:100px;top:520px;width:100px;height:100px;background:red}</style><div id="red"></div>',
    fileext = ".html"
  )
  page <- local_page(html, width = 640, height = 480, scale = 1)
  out <- withr::local_tempfile(fileext = ".mp4")
  pz_record_start(page, out, fps = 10, hold = c(0, 0))
  defer_record_stop(page)
  pz_js(page, "window.scrollTo(0,500)")
  pz_camera(page, "#red", zoom = 2, duration = 0.1)
  pz_wait(page, 0.15)
  suppressWarnings(pz_record_stop(page))
  decoded <- tempfile("camera-scrolled-")
  withr::defer(unlink(decoded, recursive = TRUE))
  frames <- av_video_images_quiet(out, destdir = decoded, format = "png")
  color <- png::readPNG(tail(frames, 1))[140, 300, 1:3]
  expect_gt(color[1], 0.8)
  expect_lt(color[2], 0.2)
})

test_that("framed camera uses final home, scale and each method's capture density", {
  skip_if_no_av()
  testthat::skip_if_not_installed("png")
  html <- withr::local_tempfile(
    lines = '<!doctype html><style>body{margin:0;background:#ddd}#home{position:absolute;left:20px;top:20px;width:400px;height:300px;background:white}#red,#blue{position:absolute;width:50px;height:50px}#red{left:30px;top:30px;background:red}#blue{left:330px;top:230px;background:blue}</style><div id="home"><div id="red"></div><div id="blue"></div></div>',
    fileext = ".html"
  )
  page <- local_page(html, width = 640, height = 480, scale = 2)
  for (method in c("poll", "screencast")) {
    out <- withr::local_tempfile(fileext = ".mp4")
    pz_js(page, "document.getElementById('home').style.width = '400px'")
    pz_record_start(
      page,
      out,
      method = method,
      frame = pz_frame("#home", when = "stop"),
      fps = 10,
      scale = 0.5,
      hold = c(0.2, 0.2)
    )
    defer_record_stop(page)
    pz_camera(page, "#red", zoom = 2, duration = 0.15)
    pz_wait(page, 0.25)
    pz_js(page, "document.getElementById('home').style.width = '480px'")
    pz_camera_reset(page)
    pz_wait(page, 0.15)
    suppressWarnings(pz_record_stop(page))
    size <- if (method == "poll") c(480, 300) else c(240, 148)
    info <- recorded_video_info(out)
    expect_equal(c(info$width, info$height), size)
    decoded <- tempfile("camera-framed-")
    withr::defer(unlink(decoded, recursive = TRUE))
    frames <- av_video_images_quiet(out, destdir = decoded, format = "png")
    red_at_blue <- function(file) {
      png::readPNG(file)[round(size[2] * 0.88), round(size[1] * 0.74), 1]
    }
    expect_lt(red_at_blue(frames[[1]]), 0.2)
    expect_gt(red_at_blue(frames[[length(frames) %/% 2]]), 0.7)
    expect_lt(red_at_blue(tail(frames, 1)), 0.2)
  }
})

test_that("50 camera moves fit the available perspective expression parser", {
  skip_if_no_av()
  testthat::skip_if_not_installed("png")
  png <- withr::local_tempfile(fileext = ".png")
  out_file <- withr::local_tempfile(fileext = ".mp4")
  png::writePNG(array(0.7, c(48, 64, 3)), png)
  rec <- new_recorder(out_file, "mp4", 10, NULL, c(0, 0), FALSE, NULL)
  rec$camera_viewport_width <- 64
  rec$files <- png
  rec$scroll <- list(c(0, 0))
  rec$camera <- lapply(seq_len(50), function(i) {
    list(
      start = (i - 1) * 0.6,
      end = i * 0.6,
      box = c(10 + i %% 8, 10, 20 + i %% 8, 20),
      zoom = 1.25,
      reset = FALSE,
      scroll = c(0, 0)
    )
  })
  sampled <- list(
    files = rep(png, 302),
    index = rep(1L, 302),
    vts = (0:301) / 10,
    n_ticks = 302L
  )
  size <- png_read_size(png)
  spec <- record_output_spec(rec, size)
  filter <- suppressWarnings(camera_filter(rec, sampled, spec, size))
  expect_lt(nchar(filter), 150000)
  av::av_encode_video(
    sampled$files,
    out_file,
    framerate = 10,
    vfilter = filter,
    codec = "libx264",
    verbose = FALSE
  )
  expect_equal(
    c(
      recorded_video_info(out_file)$width,
      recorded_video_info(out_file)$height
    ),
    c(64, 48)
  )
})

test_that("resampled camera ticks keep source video times and frame scroll indices", {
  rec <- new_recorder("unused.mp4", "mp4", 10, NULL, c(0.2, 0.2), FALSE, NULL)
  rec$times <- c(2, 2.3, 2.8)
  rec$vt_end <- 2.8
  rec$files <- c("a.png", "b.png", "c.png")
  rec$scroll <- list(c(0, 0), c(0, 150), c(0, 300))
  sampled <- record_resample(rec)
  expect_equal(sampled$vts[[1]], 2)
  expect_equal(sampled$index[[1]], 1L)
  expect_equal(rec$scroll[[sampled$index[[1]]]], c(0, 0))
  expect_equal(rec$scroll[[sampled$index[[6]]]], c(0, 150))
  expect_equal(tail(sampled$index, 1), 3L)
  rec$holds <- list(list(vt = 2.3, seconds = 0.3))
  held <- record_resample(rec)
  held_ticks <- which(abs(held$vts - 2.3) < 1e-8)
  expect_gte(length(held_ticks), 3)
  move <- list(
    start = 2,
    end = 2.8,
    box = c(100, 50, 300, 200),
    zoom = 2,
    reset = FALSE,
    scroll = c(0, 0)
  )
  positions <- lapply(held_ticks, function(i) {
    camera_at(list(move), held$vts[[i]], c(0, 0, 640, 480), 2)
  })
  expect_true(all(vapply(positions[-1], identical, logical(1), positions[[1]])))
})

test_that("explicit zoom beyond capture density warns", {
  testthat::skip_if_not_installed("png")
  path <- withr::local_tempfile(fileext = ".png")
  png::writePNG(array(0.5, c(48, 64, 3)), path)
  rec <- new_recorder("unused.mp4", "mp4", 10, NULL, c(0, 0), FALSE, NULL)
  rec$camera_viewport_width <- 64
  rec$files <- path
  rec$scroll <- list(c(0, 0))
  rec$camera <- list(list(
    start = 0,
    end = 0,
    box = c(20, 10, 40, 30),
    zoom = 4,
    reset = FALSE
  ))
  sampled <- list(files = path, index = 1L, vts = 0, n_ticks = 1L)
  out <- record_output_spec(rec, png_read_size(path))
  expect_warning(camera_filter(rec, sampled, out, png_read_size(path)), "soft")
})

test_that("an interrupted camera move starts at its previous eased position", {
  home <- c(0, 0, 800, 600)
  moves <- list(
    list(
      start = 0,
      end = 2,
      box = c(200, 150, 600, 450),
      zoom = 2,
      reset = FALSE,
      scroll = c(0, 0)
    ),
    list(
      start = 1,
      end = 2,
      box = c(500, 400, 600, 500),
      zoom = 2,
      reset = FALSE,
      scroll = c(0, 0)
    )
  )
  from <- camera_interpolate(home, camera_shot(moves[[1]]$box, home, 2), 0.5)
  expect_equal(as.numeric(camera_at(moves, 1, home, 1)), from)
  expect_equal(
    as.numeric(camera_at(moves, 1.5, home, 1)),
    camera_interpolate(from, camera_shot(moves[[2]]$box, home, 2), 0.5)
  )
})

test_that("camera expression coalesces held and stationary ticks", {
  expect_equal(camera_expression(rep(17, 50)), "17.00000")
  expect_equal(
    camera_expression(c(10, 10, 20, 20)),
    "if(lt(in\\,3)\\,10.00000\\,20.00000)"
  )
})

test_that("camera duration and eased interpolation use the video clock", {
  home <- c(0, 0, 800, 600)
  from <- c(0, 0, 800, 600)
  to <- c(200, 150, 600, 450)
  expect_equal(camera_duration(from, from, home), 0.66)
  expect_equal(camera_duration(from, to, home), 1.66, tolerance = 0.01)
  expect_equal(camera_duration(from, c(0, 0, 8, 6), home), 2)
  expect_equal(camera_interpolate(from, to, 0), from)
  expect_equal(camera_interpolate(from, to, 1), to)
  expect_equal(
    camera_interpolate(from, to, 0.5),
    c(
      400 - 400 / sqrt(2),
      300 - 300 / sqrt(2),
      400 + 400 / sqrt(2),
      300 + 300 / sqrt(2)
    )
  )
  quarter <- camera_interpolate(from, to, 0.25)
  expect_equal(quarter[3] - quarter[1], 800 * 2^(-0.0625), tolerance = 0.001)
})

test_that("camera fit caps at source density while explicit zoom does not", {
  home <- c(0, 0, 800, 600)
  target <- c(395, 290, 405, 310)
  expect_equal(
    camera_shot(target, home, zoom = NULL, density = 2),
    c(200, 150, 600, 450)
  )
  expect_equal(camera_shot(target, home, zoom = NULL, density = 1), home)
  expect_equal(
    camera_shot(target, home, zoom = 4, density = 1),
    c(300, 225, 500, 375)
  )
  expect_equal(camera_shot(target, home, zoom = 0.5, density = 2), home)
  expect_equal(
    camera_viewport(
      camera_shot(c(795, 595, 810, 610), home, zoom = 2, density = 2),
      c(0, 0),
      home
    ),
    c(400, 300, 800, 600)
  )
})

test_that("camera tick translation uses repeated frame scroll and home bounds", {
  home <- c(0, 0, 800, 600)
  shot <- c(200, 150, 600, 450)
  expect_equal(camera_viewport(shot, c(0, 0), home), shot)
  expect_equal(camera_viewport(shot, c(150, 100), home), c(50, 50, 450, 350))
  expect_equal(camera_viewport(shot, c(900, 0), home), c(0, 150, 400, 450))
  expect_equal(camera_viewport(home, c(900, 0), home, reset = TRUE), home)
})

test_that("camera follow pans minimally and zooms out only to fit", {
  home <- c(0, 0, 800, 600)
  current <- c(100, 100, 500, 400)
  expect_null(camera_follow_shot(current, c(200, 150, 250, 180), home, c(0, 0)))
  expect_equal(
    camera_follow_shot(current, c(480, 150, 510, 180), home, c(0, 0)),
    c(134, 100, 534, 400)
  )
  expect_equal(
    camera_follow_shot(current, c(200, 380, 250, 420), home, c(0, 0)),
    c(100, 144, 500, 444)
  )
  expect_equal(
    camera_follow_shot(current, c(450, 150, 950, 180), home, c(0, 0)),
    c(252, 100, 800, 511)
  )
  expect_equal(
    camera_follow_shot(current, c(100, 150, 950, 180), home, c(0, 0)),
    home
  )
  expect_equal(
    camera_follow_shot(
      c(200, 600, 600, 900),
      c(590, 850, 620, 880),
      home,
      c(100, 500)
    ),
    c(244, 604, 644, 904)
  )
  expect_null(camera_follow_shot(home, c(700, 500, 790, 590), home, c(0, 0)))
})

test_that("follow zoom is not treated as an explicit softness request", {
  testthat::skip_if_not_installed("png")
  path <- withr::local_tempfile(fileext = ".png")
  png::writePNG(array(0.5, c(48, 64, 3)), path)
  rec <- new_recorder("unused.mp4", "mp4", 10, NULL, c(0, 0), FALSE, NULL)
  rec$camera_viewport_width <- 64
  rec$files <- path
  rec$scroll <- list(c(0, 0))
  rec$camera <- list(list(
    start = 0,
    end = 0,
    box = c(20, 10, 40, 30),
    zoom = 1 + 1e-8,
    reset = FALSE,
    follow = TRUE,
    scroll = c(0, 0)
  ))
  sampled <- list(files = path, index = 1L, vts = 0, n_ticks = 1L)
  out <- record_output_spec(rec, png_read_size(path))
  expect_no_warning(camera_filter(rec, sampled, out, png_read_size(path)))
})

test_that("follow keyframes share the pointer glide and skip in-shot actions", {
  skip_if_no_av()
  html <- withr::local_tempfile(
    lines = '<!doctype html><style>body{margin:0}button,input{position:absolute;width:80px;height:50px}#a{left:90px;top:90px}#b{left:490px;top:290px}#field{left:480px;top:380px}</style><button id="a">A</button><button id="b">B</button><input id="field">',
    fileext = ".html"
  )
  page <- local_page(html, width = 640, height = 480, scale = 2)
  pz_record_start(page, withr::local_tempfile(fileext = ".mp4"), hold = c(0, 0))
  defer_record_stop(page)
  rec <- page_recorder(page)
  pz_camera(page, "#a", zoom = 2, duration = 0)
  pz_act_hover(page, "#a")
  expect_length(rec$camera, 1)
  start <- rec_vt(rec)
  pz_act_hover(page, "#b")
  expect_length(rec$camera, 2)
  move <- rec$camera[[2]]
  expect_true(move$follow)
  expect_gte(move$start, start)
  expect_lte(move$end, rec_vt(rec))
  expect_equal(
    move$end - move$start,
    stage_glide_duration(c(x = 130, y = 115), c(x = 530, y = 315), 500),
    tolerance = 0.02
  )
  pz_act_hover(page, "#b")
  expect_length(rec$camera, 2)
  pz_stage(page, camera_follow = FALSE)
  pz_act_click(page, "#a")
  expect_length(rec$camera, 2)
  pz_stage(page, camera_follow = NULL, cursor = FALSE)
  pz_camera(page, "#a", zoom = 2, duration = 0)
  before <- rec_vt(rec)
  pz_act_type(page, "hi", target = "#field")
  expect_length(rec$camera, 4)
  expect_true(rec$camera[[4]]$follow)
  expect_equal(rec$camera[[4]]$end - rec$camera[[4]]$start, 0.5)
  expect_gte(rec$camera[[4]]$start, before)
  expect_lte(rec$camera[[4]]$end, rec_vt(rec))
  suppressWarnings(pz_record_stop(page))
})

test_that("auto-scroll follow uses the resolved post-scroll target", {
  skip_if_no_av()
  html <- withr::local_tempfile(
    lines = '<!doctype html><style>body{margin:0;height:1500px}button{position:absolute;width:80px;height:50px}#near{left:90px;top:90px}#far{left:490px;top:900px}</style><button id="near">near</button><button id="far">far</button>',
    fileext = ".html"
  )
  page <- local_page(html, width = 640, height = 480, scale = 2)
  pz_record_start(page, withr::local_tempfile(fileext = ".mp4"), hold = c(0, 0))
  defer_record_stop(page)
  rec <- page_recorder(page)
  pz_camera(page, "#near", zoom = 2, duration = 0)
  pz_act_hover(page, "#far")
  expect_gt(pz_js(page, "window.scrollY"), 400)
  move <- tail(rec$camera, 1)[[1]]
  expect_true(move$follow)
  expect_gte(move$end - move$start, 0.5)
  expect_lte(move$end - move$start, 2)
  expect_equal(move$box[2], 900 - 24, tolerance = 2)
  suppressWarnings(pz_record_stop(page))
})

test_that("first appearance follows during fade; home and reads do not", {
  skip_if_no_av()
  html <- withr::local_tempfile(
    lines = '<!doctype html><style>body{margin:0}#a,#b{position:absolute;width:80px;height:50px}#a{left:90px;top:90px}#b{left:490px;top:290px}</style><button id="a">A</button><button id="b">B</button>',
    fileext = ".html"
  )
  page <- local_page(html, width = 640, height = 480, scale = 2)
  pz_record_start(page, withr::local_tempfile(fileext = ".mp4"), hold = c(0, 0))
  defer_record_stop(page)
  rec <- page_recorder(page)
  pz_act_hover(page, "#a")
  expect_length(rec$camera, 0)
  pz_camera(page, "#a", zoom = 2, duration = 0)
  pz_get_text(page, "#b")
  pz_expect_text(page, "B", target = "#b")
  pz_wait(page, 0.01)
  expect_length(rec$camera, 1)
  pz_act_hover(page, "#b")
  expect_length(rec$camera, 2)
  pz_camera_reset(page)
  n <- length(rec$camera)
  pz_act_hover(page, "#a")
  expect_length(rec$camera, n)
  suppressWarnings(pz_record_stop(page))

  page2 <- local_page(html, width = 640, height = 480, scale = 2)
  pz_record_start(
    page2,
    withr::local_tempfile(fileext = ".mp4"),
    hold = c(0, 0)
  )
  defer_record_stop(page2)
  rec2 <- page_recorder(page2)
  pz_camera(page2, "#a", zoom = 2, duration = 0)
  pz_act_hover(page2, "#b")
  expect_length(rec2$camera, 2)
  expect_equal(rec2$camera[[2]]$end - rec2$camera[[2]]$start, 0.3)
  suppressWarnings(pz_record_stop(page2))
})

test_that("selection and focused typing follow without a pointer glide", {
  skip_if_no_av()
  html <- withr::local_tempfile(
    lines = '<!doctype html><style>body{margin:0}[contenteditable]{position:absolute;width:120px;height:60px}#near{left:80px;top:80px}#far{left:480px;top:300px}</style><div id="near" contenteditable>near</div><div id="far" contenteditable>far text</div>',
    fileext = ".html"
  )
  page <- local_page(html, width = 640, height = 480, scale = 2)
  pz_record_start(page, withr::local_tempfile(fileext = ".mp4"), hold = c(0, 0))
  defer_record_stop(page)
  rec <- page_recorder(page)
  pz_camera(page, "#near", zoom = 2, duration = 0)
  pz_act_select_text(page, "far", target = "#far")
  expect_length(rec$camera, 2)
  expect_true(rec$camera[[2]]$follow)
  expect_equal(rec$camera[[2]]$end - rec$camera[[2]]$start, 0.5)
  pz_camera(page, "#near", zoom = 2, duration = 0)
  scoped <- pz_find(page, "#far")
  pz_act_type(scoped, "new")
  expect_length(rec$camera, 4)
  expect_true(rec$camera[[4]]$follow)
  pz_camera(page, "#near", zoom = 2, duration = 0)
  pz_act_type(page, "!")
  expect_length(rec$camera, 6)
  expect_true(rec$camera[[6]]$follow)
  suppressWarnings(pz_record_stop(page))
})

test_that("paused follow, manual camera, and reset moves are instant without pumping", {
  skip_if_no_av()
  html <- withr::local_tempfile(
    lines = '<!doctype html><style>body{margin:0}button{position:absolute;width:70px;height:50px}#near{left:90px;top:90px}#far{left:490px;top:290px}</style><button id="near">near</button><button id="far">far</button>',
    fileext = ".html"
  )
  page <- local_page(html, width = 640, height = 480, scale = 2)
  pz_stage(page, cursor = FALSE)
  pz_record_start(page, withr::local_tempfile(fileext = ".mp4"), hold = c(0, 0))
  defer_record_stop(page)
  rec <- page_recorder(page)
  pz_camera(page, "#near", zoom = 2, duration = 0)
  pz_record_pause(page)
  frozen <- rec_vt(rec)
  pumped <- numeric()
  testthat::with_mocked_bindings(
    {
      pz_act_hover(page, "#far")
      pz_camera(page, "#near", duration = 0.8)
      pz_camera_reset(page)
    },
    pump_loop = function(loop, seconds) {
      pumped <<- c(pumped, seconds)
    }
  )
  expect_length(rec$camera, 4)
  expect_true(rec$camera[[2]]$follow)
  for (move in rec$camera[2:4]) {
    expect_equal(move$start, frozen)
    expect_equal(move$end, frozen)
  }
  expect_length(pumped, 0)
  pz_record_resume(page)
  expect_equal(rec$camera[[4]]$end, frozen)
  suppressWarnings(pz_record_stop(page))
})

test_that("a move after scroll starts from the clamped crop", {
  home <- c(0, 0, 800, 600)
  scroll <- c(0, 500)
  a <- list(
    start = 0,
    end = 0,
    box = c(50, 40, 250, 190),
    zoom = 2,
    reset = FALSE,
    scroll = c(0, 0)
  )
  actual <- camera_viewport(
    as.numeric(camera_at(list(a), 1, home, 2)),
    scroll,
    home
  ) +
    rep(scroll, 2)
  b <- list(
    start = 2,
    end = 4,
    box = c(600, 1000, 650, 1050),
    zoom = 2,
    reset = FALSE,
    scroll = scroll
  )
  at_start <- camera_at(list(a, b), 2, home, 2)
  expect_equal(as.numeric(at_start), actual)
  expect_equal(camera_viewport(at_start, scroll, home), actual - rep(scroll, 2))
  unclamped <- as.numeric(camera_at(list(a), 2, home, 2))
  expect_false(isTRUE(all.equal(unclamped, actual)))
  at_first_motion <- camera_viewport(
    camera_at(list(a, b), 2.5, home, 2),
    scroll,
    home
  )
  old_first_motion <- camera_viewport(
    camera_interpolate(unclamped, camera_shot(b$box, home, b$zoom, 2), 0.25),
    scroll,
    home
  )
  expect_gt(at_first_motion[2], 0)
  expect_equal(old_first_motion[2], 0)
})

test_that("stop-time home resolves adjacent moves without a call-time crop", {
  call_home <- c(0, 0, 800, 600)
  final_home <- c(0, 0, 1000, 750)
  scroll <- c(0, 500)
  a <- list(
    start = 0,
    end = 0,
    box = c(50, 40, 250, 190),
    zoom = 2,
    reset = FALSE,
    scroll = c(0, 0)
  )
  b <- list(
    start = 2,
    end = 4,
    box = c(600, 1000, 650, 1050),
    zoom = 2,
    reset = FALSE,
    scroll = scroll
  )
  call_crop <- camera_viewport(
    camera_at(list(a), 2, call_home, 2),
    scroll,
    call_home
  )
  final_crop <- camera_viewport(
    camera_at(list(a), 2, final_home, 2),
    scroll,
    final_home
  )
  expect_false(isTRUE(all.equal(call_crop, final_crop)))
  start <- camera_at(list(a, b), 2, final_home, 2)
  expect_equal(as.numeric(start), final_crop + rep(scroll, 2))
  expect_equal(camera_viewport(start, scroll, final_home), final_crop)

  fit <- a
  fit$zoom <- NULL
  fit$box <- c(50, 40, 90, 70)
  call_density_crop <- camera_viewport(
    camera_at(list(fit), 2, final_home, 1),
    scroll,
    final_home
  )
  final_density_crop <- camera_viewport(
    camera_at(list(fit), 2, final_home, 2),
    scroll,
    final_home
  )
  expect_false(isTRUE(all.equal(call_density_crop, final_density_crop)))
  at_final_density <- camera_at(list(fit, b), 2, final_home, 2)
  expect_equal(
    as.numeric(at_final_density),
    final_density_crop + rep(scroll, 2)
  )
})

test_that("camera moves wait only when asked; holds and stops let them land", {
  skip_if_no_av()
  html <- withr::local_tempfile(
    lines = '<!doctype html><style>body{margin:0}button{position:absolute;width:70px;height:50px}#near{left:90px;top:90px}</style><button id="near">near</button>',
    fileext = ".html"
  )
  page <- local_page(html, width = 640, height = 480, scale = 2)
  pz_stage(page, cursor = FALSE)
  expect_error(pz_camera(page, "#near", wait = "yes"), "wait")
  pz_record_start(page, withr::local_tempfile(fileext = ".mp4"), hold = c(0, 0))
  defer_record_stop(page)
  rec <- page_recorder(page)
  pumped <- numeric()
  testthat::with_mocked_bindings(
    pz_camera(page, "#near", zoom = 2, duration = 0.8),
    pump_loop = function(loop, seconds) {
      pumped <<- c(pumped, seconds)
    }
  )
  expect_length(pumped, 0)
  zoom <- rec$camera[[1]]

  # A waiting reset settles the zoom, then waits for itself.
  pz_camera_reset(page, wait = TRUE)
  reset <- rec$camera[[2]]
  expect_gte(reset$start, zoom$end - 0.05)
  expect_gte(rec_vt(rec), reset$end - 0.05)

  pz_camera(page, "#near", zoom = 2, duration = 0.5)
  move <- rec$camera[[3]]
  pz_record_hold(page, 1)
  expect_gte(rec$holds[[1]]$vt, move$end - 0.05)

  pz_camera_reset(page)
  move <- rec$camera[[4]]
  pz_record_pause(page)
  expect_gte(rec_vt(rec), move$end - 0.05)
  pz_record_resume(page)
  suppressWarnings(pz_record_stop(page))
})

test_that("camera calls settle earlier moves and keyframe non-moves", {
  skip_if_no_av()
  html <- withr::local_tempfile(
    lines = '<!doctype html><style>body{margin:0}button{position:absolute;width:70px;height:50px}#near{left:90px;top:90px}#far{left:490px;top:290px}</style><button id="near">near</button><button id="far">far</button>',
    fileext = ".html"
  )
  page <- local_page(html, width = 640, height = 480, scale = 2)
  pz_stage(page, cursor = FALSE)
  pz_record_start(page, withr::local_tempfile(fileext = ".mp4"), hold = c(0, 0))
  defer_record_stop(page)
  rec <- page_recorder(page)

  pz_camera(page, "#near", zoom = 2, duration = 0.6)
  pz_camera(page, "#far", zoom = 2, duration = 0.6)
  expect_length(rec$camera, 2)
  expect_gte(rec$camera[[2]]$start, rec$camera[[1]]$end - 0.05)

  # Already there: an instantaneous keyframe records the anchor without pumping.
  pz_camera(page, "#far", zoom = 2)
  expect_length(rec$camera, 3)
  expect_equal(rec$camera[[3]]$end, rec$camera[[3]]$start)

  # With a duration, staying put is a still keyframe that can be waited on.
  pumped <- numeric()
  testthat::with_mocked_bindings(
    pz_camera(page, "#far", zoom = 2, duration = 0.7, wait = TRUE),
    pump_loop = function(loop, seconds) {
      pumped <<- c(pumped, seconds)
    }
  )
  expect_length(rec$camera, 4)
  expect_equal(pumped, 0.7)

  pz_camera_reset(page, wait = TRUE)
  pz_camera_reset(page)
  expect_length(rec$camera, 6)
  expect_equal(rec$camera[[6]]$end, rec$camera[[6]]$start)
  suppressWarnings(pz_record_stop(page))
})

test_that("follow tests the shot when the action lands", {
  skip_if_no_av()
  html <- withr::local_tempfile(
    lines = '<!doctype html><style>body{margin:0}button{position:absolute;width:70px;height:50px}#near{left:90px;top:90px}#far{left:490px;top:290px}</style><button id="near">near</button><button id="far">far</button>',
    fileext = ".html"
  )
  page <- local_page(html, width = 640, height = 480, scale = 2)
  pz_stage(page, cursor = FALSE, camera_follow = TRUE)
  pz_record_start(page, withr::local_tempfile(fileext = ".mp4"), hold = c(0, 0))
  defer_record_stop(page)
  rec <- page_recorder(page)
  pz_camera(page, "#near", zoom = 2, duration = 0)
  # Landing after the move ends: the move already frames the target.
  pz_camera(page, "#far", zoom = 2, duration = 0.3)
  pz_act_hover(page, "#far")
  expect_length(rec$camera, 2)
  # In the shot now, but the move pans away before the action lands.
  pz_camera(page, "#far", zoom = 2, duration = 0)
  pz_camera(page, "#near", zoom = 2, duration = 0.4)
  pz_act_hover(page, "#far")
  expect_length(rec$camera, 5)
  expect_true(rec$camera[[5]]$follow)
  # Landing early in a long move toward the target: leave it alone.
  pz_camera(page, "#near", zoom = 2, duration = 0)
  pz_camera(page, "#far", zoom = 2, duration = 3)
  pz_act_hover(page, "#far")
  expect_length(rec$camera, 7)
  suppressWarnings(pz_record_stop(page))
})

test_that("a clamped same-viewport keyframe changes the later scroll anchor", {
  skip_if_no_av()
  html <- withr::local_tempfile(
    lines = '<!doctype html><style>body{margin:0;height:1500px}.target{position:absolute;width:40px;height:40px}#first{left:700px;top:500px}#beyond{left:760px;top:560px}#next{left:250px;top:350px}</style><div class="target" id="first"></div><div class="target" id="beyond"></div><div class="target" id="next"></div>',
    fileext = ".html"
  )
  page <- local_page(html, width = 800, height = 600, scale = 2)
  pz_stage(page, cursor = FALSE, camera_follow = FALSE)
  pz_record_start(page, withr::local_tempfile(fileext = ".mp4"), hold = c(0, 0))
  defer_record_stop(page)
  rec <- page_recorder(page)
  pz_camera(page, "#first", zoom = 2, pad = 0, duration = 0)
  home <- c(0, 0, 800, 600)
  before <- camera_viewport(
    as.numeric(camera_at(rec$camera, rec_vt(rec), home, 2)),
    c(0, 0),
    home
  )
  pz_camera(page, "#beyond", zoom = 2, pad = 0)
  expect_length(rec$camera, 2)
  expect_equal(rec$camera[[2]]$end, rec$camera[[2]]$start)
  expect_equal(rec$camera[[2]]$box, c(760, 560, 800, 600))
  after <- camera_viewport(
    as.numeric(camera_at(rec$camera, rec_vt(rec), home, 2)),
    c(0, 0),
    home
  )
  expect_equal(after, before, tolerance = 0.5)
  pz_js(page, "window.scrollTo(0, 200)")
  scroll <- c(0, 200)
  anchor <- camera_at(rec$camera, rec_vt(rec), home, 2)
  expected <- camera_viewport(
    camera_shot(rec$camera[[2]]$box, home, 2, 2),
    scroll,
    home
  ) +
    rep(scroll, 2)
  expect_equal(as.numeric(anchor), camera_shot(rec$camera[[2]]$box, home, 2, 2))
  pz_camera(page, "#next", zoom = 2, pad = 0, duration = 0.5)
  expect_equal(rec$camera[[3]]$scroll, scroll)
  expect_equal(
    as.numeric(camera_at(rec$camera, rec$camera[[3]]$start, home, 2)),
    expected,
    tolerance = 0.5
  )
  suppressWarnings(pz_record_stop(page))
})

test_that("repeated target and reset add no camera time or settle pump", {
  skip_if_no_av()
  page <- local_record_page()
  pz_stage(page, camera_follow = FALSE, cursor = FALSE)
  pz_record_start(page, withr::local_tempfile(fileext = ".mp4"), hold = c(0, 0))
  defer_record_stop(page)
  rec <- page_recorder(page)
  pz_camera(page, "#box", zoom = 2, duration = 0)
  pumped <- numeric()
  before <- rec_vt(rec)
  testthat::with_mocked_bindings(
    {
      pz_camera(page, "#box", zoom = 2, wait = TRUE)
      camera_settle(page$page, rec)
    },
    pump_loop = function(loop, seconds) pumped <<- c(pumped, seconds)
  )
  expect_length(pumped, 0)
  expect_equal(rec$camera[[2]]$end, rec$camera[[2]]$start)
  expect_lt(rec_vt(rec) - before, 0.5)
  pz_camera_reset(page, wait = TRUE)
  before <- rec_vt(rec)
  testthat::with_mocked_bindings(
    {
      pz_camera_reset(page, wait = TRUE)
      camera_settle(page$page, rec)
    },
    pump_loop = function(loop, seconds) pumped <<- c(pumped, seconds)
  )
  expect_length(pumped, 0)
  expect_equal(rec$camera[[4]]$end, rec$camera[[4]]$start)
  expect_lt(rec_vt(rec) - before, 0.5)
  suppressWarnings(pz_record_stop(page))
})

test_that("a repeated reset after a page scroll records its new anchor", {
  skip_if_no_av()
  html <- withr::local_tempfile(
    lines = '<!doctype html><style>body{margin:0;height:2000px}#a{position:absolute;left:90px;top:90px;width:70px;height:50px}</style><button id="a">A</button>',
    fileext = ".html"
  )
  page <- local_page(html, width = 640, height = 480, scale = 2)
  pz_stage(page, cursor = FALSE, camera_follow = FALSE)
  pz_record_start(page, withr::local_tempfile(fileext = ".mp4"), hold = c(0, 0))
  defer_record_stop(page)
  rec <- page_recorder(page)
  pz_camera(page, "#a", zoom = 2, duration = 0)
  pz_camera_reset(page)
  n <- length(rec$camera)
  pz_js(page, "window.scrollTo(0, 400)")
  pz_camera_reset(page)
  expect_length(rec$camera, n + 1L)
  expect_equal(tail(rec$camera, 1)[[1]]$scroll, c(0, 400))
  expect_equal(tail(rec$camera, 1)[[1]]$end, tail(rec$camera, 1)[[1]]$start)
  suppressWarnings(pz_record_stop(page))
})

test_that("camera padding rejects NULL even without a recording", {
  page <- local_page()
  expect_error(pz_camera(page, "body", pad = NULL), "pad.*NULL")
  expect_invisible(pz_camera(page, "body"))
  expect_invisible(pz_camera(page, "body", pad = 24))
  expect_equal(formals(pz_camera)$pad, 24)
})
