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
    frames <- av::av_video_images(out, destdir = decoded, format = "png")
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
  frames <- av::av_video_images(out, destdir = decoded, format = "png")
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
    frames <- av::av_video_images(out, destdir = decoded, format = "png")
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

test_that("explicit zoom beyond capture density warns once per recording", {
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
  expect_no_warning(camera_filter(rec, sampled, out, png_read_size(path)))
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
