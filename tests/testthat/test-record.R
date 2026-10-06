test_that("recorder accessors share the page recorder binding", {
  page <- PaparazziPage$new(structure(list(), class = "ChromoteSession"))
  rec <- new.env(parent = emptyenv())
  rec$active <- TRUE

  expect_invisible(page_set_recorder(page, rec))
  expect_identical(page$recorder, rec)

  page$recorder$active <- FALSE
  expect_identical(page_recorder(page), rec)
  expect_false(page_recorder(page)$active)

  page_set_recorder(page, NULL)
  expect_null(page$recorder)
})

test_that("recording rejects explicit annotated home but uses staged element home", {
  skip_if_no_av()
  page <- local_record_page()
  pz_js(
    page,
    "document.body.insertAdjacentHTML('beforeend', '<div id=home style=\"position:absolute;left:200px;top:120px;width:100px;height:60px\"></div>')"
  )
  pz_annotate_callout(
    page,
    "Outside",
    target = "#home",
    side = "right",
    reveal = "none"
  )
  out <- withr::local_tempfile(fileext = ".mp4")
  for (when in c("start", "stop")) {
    expect_error(
      pz_record_start(
        page,
        out,
        frame = pz_frame("#home", when = when, target_box = "annotated")
      ),
      "home|recording"
    )
    expect_null(page_recorder(page))
  }
  pz_stage_frame(page, "#home", target_box = "annotated")
  expect_error(
    pz_record_start(page, out, frame = page_frame(page)),
    "home|recording"
  )
  expect_null(page_recorder(page))
  pz_record_start(page, out, hold = c(0, 0))
  defer_record_stop(page)
  rec <- page_recorder(page)
  expect_identical(rec$frame$target_box, "element")
  expect_identical(page_frame(page)$target_box, "annotated")
  expect_equal(
    unlist(record_crop_box(page, rec$frame)[c("x", "y")]),
    c(x = 200, y = 120)
  )
  pz_record_stop(page)
  expect_equal(
    unlist(rec$crop[c("x", "y", "width", "height")]),
    c(x = 200, y = 120, width = 100, height = 60)
  )
})

test_that("pz_record_start/stop record an mp4 with first/last holds", {
  page <- local_record_page()
  skip_if_no_av()

  out <- withr::local_tempfile(fileext = ".mp4")
  start <- withVisible(pz_record_start(page, out, fps = 10, hold = c(0.5, 1)))
  expect_false(start$visible)
  expect_identical(start$value$page, page)

  pz_wait(page, 0.8)
  stop <- withVisible(pz_record_stop(page))
  expect_false(stop$visible)
  expect_identical(stop$value, page)

  expect_true(file.exists(out))
  info <- recorded_video_info(out)
  expect_equal(info$codec, "h264")
  expect_equal(info$framerate, 10)
  # ~0.8s recorded + 0.5s + 1s holds
  expect_gte(info$duration, 2.0)
  expect_lte(info$duration, 3.2)
  # mp4 dimensions are multiples of 4
  expect_equal(info$width %% 4, 0)
  expect_equal(info$height %% 4, 0)
})

test_that("webm encodes", {
  page <- local_record_page()
  skip_if_no_av()

  out <- withr::local_tempfile(fileext = ".webm")
  page |> pz_record_start(out, fps = 10, hold = c(0, 0))
  pz_wait(page, 0.4)
  page |> pz_record_stop()

  expect_true(file.exists(out))
  info <- recorded_video_info(out)
  expect_match(info$codec, "vp")
  expect_gte(info$duration, 0.2)
  expect_lte(info$duration, 1.0)
})

test_that("pause/resume cuts the paused stretch out of the video", {
  page <- local_record_page()
  skip_if_no_av()

  out <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(out, fps = 10, hold = c(0, 0))
  pz_wait(page, 0.5)
  page |> pz_record_pause()
  pz_wait(page, 0.7)
  page |> pz_record_resume()
  pz_wait(page, 0.5)
  page |> pz_record_stop()

  info <- recorded_video_info(out)
  # ~1s of active recording; the 0.7s pause leaves no trace
  expect_gte(info$duration, 0.7)
  expect_lte(info$duration, 1.5)
})

test_that("knit recording results distinguish GIF images and video output", {
  skip_if_not_installed("knitr")
  withr::local_options(knitr.graphics.error = FALSE)
  gif <- record_knit_media("figure/demo.gif")
  expect_s3_class(gif, "knit_image_paths")
  expect_equal(as.character(gif), "figure/demo.gif")

  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  dir.create("figure")
  writeBin(charToRaw("fixture"), "figure/a & b.webm")
  prior_format <- knitr::opts_knit$get("rmarkdown.pandoc.to")
  withr::defer(knitr::opts_knit$set(rmarkdown.pandoc.to = prior_format))
  for (format in c("html", "latex")) {
    input <- file.path(dir, paste0(format, ".Rmd"))
    output <- file.path(dir, paste0(format, ".md"))
    knitr::opts_knit$set(rmarkdown.pandoc.to = format)
    writeLines(
      c(
        "```{r, echo=FALSE, error=FALSE}",
        'record_knit_media("figure/a & b.webm")',
        "```"
      ),
      input
    )
    knitr::knit(input, output = output, envir = environment(), quiet = TRUE)
    text <- paste(readLines(output), collapse = "\n")
    if (format == "html") {
      expect_match(text, "<video controls")
      expect_match(text, "a%20%26%20b.webm", fixed = TRUE)
      expect_false(grepl("knit_asis|knit_image_paths", text))
    } else {
      expect_match(text, "[Download recording](<", fixed = TRUE)
      expect_match(text, "a%20%26%20b.webm", fixed = TRUE)
      expect_false(grepl("<video", text, fixed = TRUE))
    }
  }
})

video_sources <- function(html) {
  tags <- regmatches(html, gregexpr('<video[^>]+src="[^"]+"', html))[[1]]
  sub('.*src="([^"]+)"', "\\1", tags)
}

video_source_exists <- function(output, src) {
  file.exists(file.path(dirname(output), utils::URLdecode(src)))
}

test_that("absolute figure paths yield output-relative video sources", {
  skip_if_not_installed("knitr")
  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  dir.create("published")
  writeBin(charToRaw("fixture"), "a & b.mp4")
  figure_path <- file.path(dir, "published", "article_files", "figure-html", "")
  prior_output <- knitr::opts_knit$get("output.dir")
  withr::defer(knitr::opts_knit$set(output.dir = prior_output))
  prior_format <- knitr::opts_knit$get("rmarkdown.pandoc.to")
  withr::defer(knitr::opts_knit$set(rmarkdown.pandoc.to = prior_format))
  knitr::opts_knit$set(
    output.dir = file.path(dir, "published"),
    rmarkdown.pandoc.to = "html"
  )
  withr::local_options(knitr.graphics.rel_path = FALSE)
  input <- file.path(dir, "video.Rmd")
  output <- file.path(dir, "published", "index.md")
  writeLines(
    c(
      sprintf("```{r, echo=FALSE, fig.path=%s}", deparse(figure_path)),
      sprintf(
        'knitr::opts_knit$set(output.dir=%s)',
        deparse(file.path(dir, "published"))
      ),
      'record_knit_media("a & b.mp4")',
      "```"
    ),
    input
  )
  knitr::knit(input, output = output, envir = environment(), quiet = TRUE)
  src <- video_sources(paste(readLines(output), collapse = "\n"))
  expect_length(src, 1L)
  expect_false(startsWith(src, "/"))
  expect_match(src, "a%20%26%20b.mp4", fixed = TRUE)
  expect_true(video_source_exists(
    file.path(dir, "published", "index.html"),
    src
  ))
})

test_that("rmarkdown renders recordings with absolute fig.path", {
  skip_if_not_installed("rmarkdown")
  skip_if_no_av()
  page <- local_record_page()
  dir <- withr::local_tempdir()
  published <- file.path(dir, "published")
  dir.create(published)
  figure_path <- file.path(published, "article_files", "figure-html", "")
  input <- file.path(dir, "absolute-fig-video.Rmd")
  writeLines(
    c(
      "---",
      "output:",
      "  html_document:",
      "    self_contained: false",
      "---",
      "",
      sprintf('```{r, echo=FALSE, fig.path=%s}', deparse(figure_path)),
      'pz_record(page, "clip.mp4", { pz_wait(page, 0.2) }, fps=5, hold=c(0, 0))',
      "```"
    ),
    input
  )
  output <- rmarkdown::render(
    input,
    output_dir = published,
    envir = environment(),
    quiet = TRUE
  )
  src <- video_sources(paste(readLines(output, warn = FALSE), collapse = "\n"))
  expect_length(src, 1L)
  expect_false(startsWith(src, "/"))
  expect_true(video_source_exists(output, src))
})

test_that("named videos resolve from final rendered HTML", {
  skip_if_not_installed("rmarkdown")
  skip_if_no_av()
  page <- local_record_page()
  dir <- withr::local_tempdir()
  dir.create(file.path(dir, "clips"))
  dir.create(file.path(dir, "published"))
  absolute <- file.path(dir, "absolute.mp4")
  input <- file.path(dir, "record-video.Rmd")
  writeLines(
    c(
      "---",
      "output:",
      "  html_document:",
      "    self_contained: false",
      "---",
      "",
      '```{r, echo=FALSE, error=FALSE}',
      sprintf(
        'pz_record(page, %s, { pz_wait(page, 0.2) }, fps=5, hold=c(0, 0))',
        deparse(absolute)
      ),
      'pz_record(page, "clips/relative.webm", { pz_wait(page, 0.2) }, fps=5, hold=c(0, 0))',
      '```'
    ),
    input
  )
  output <- getExportedValue("rmarkdown", "render")(
    input,
    output_dir = file.path(dir, "published"),
    envir = environment(),
    quiet = TRUE
  )
  html <- paste(readLines(output, warn = FALSE), collapse = "\n")
  src <- video_sources(html)
  expect_length(src, 2L)
  expect_true(file.exists(absolute))
  expect_true(file.exists(file.path(dir, "clips", "relative.webm")))
  expect_true(all(vapply(
    src,
    video_source_exists,
    logical(1),
    output = output
  )))

  broken <- sub(src[[1]], "missing-video.mp4", html, fixed = TRUE)
  expect_identical(video_sources(broken)[[1]], "missing-video.mp4")
  expect_false(video_source_exists(output, video_sources(broken)[[1]]))

  links_input <- file.path(dir, "record-links.Rmd")
  writeLines(
    c(
      "---",
      "output: md_document",
      "---",
      "",
      '```{r, echo=FALSE, error=FALSE}',
      sprintf("record_knit_media(%s)", deparse(absolute)),
      'record_knit_media("clips/relative.webm")',
      '```'
    ),
    links_input
  )
  links_output <- getExportedValue("rmarkdown", "render")(
    links_input,
    output_dir = file.path(dir, "published"),
    envir = environment(),
    quiet = TRUE
  )
  markdown <- gsub(
    "[[:space:]]+",
    " ",
    paste(readLines(links_output, warn = FALSE), collapse = "\n")
  )
  matches <- regmatches(
    markdown,
    gregexpr("\\[Download recording\\]\\(<?[^)>]+>?\\)", markdown)
  )[[1]]
  links <- sub("^\\[Download recording\\]\\(<?([^)>]+)>?\\)$", "\\1", matches)
  expect_length(links, 2L)
  expect_true(all(vapply(
    links,
    video_source_exists,
    logical(1),
    output = links_output
  )))
})

test_that("named video resolves from final Quarto HTML", {
  skip_if(Sys.which("quarto") == "", "Quarto not available")
  skip_if_not_installed("pkgload")
  skip_if_no_av()
  skip_if_no_chrome()
  dir <- withr::local_tempdir()
  absolute <- file.path(dir, "outside.mp4")
  input <- file.path(dir, "record-video.qmd")
  package_root <- normalizePath(test_path("..", ".."))
  fixture <- normalizePath(record_fixture_file())
  writeLines(
    c(
      "---",
      "format: html",
      "---",
      "",
      "```{r}",
      "#| echo: false",
      quarto_load_package(package_root),
      sprintf("page <- pz_open(%s)", deparse(fixture)),
      sprintf(
        'pz_record(page, %s, { pz_wait(page, 0.2) }, fps=5, hold=c(0, 0))',
        deparse(absolute)
      ),
      "pz_close(page)",
      "```"
    ),
    input
  )
  result <- processx::run(
    Sys.which("quarto"),
    c("render", input, "--to", "html"),
    wd = dir,
    error_on_status = FALSE,
    timeout = 120000
  )
  expect_identical(
    result$status,
    0L,
    info = paste(result$stdout, result$stderr)
  )
  output <- file.path(dir, "record-video.html")
  src <- video_sources(paste(readLines(output, warn = FALSE), collapse = "\n"))
  expect_length(src, 1L)
  expect_true(file.exists(absolute))
  expect_true(video_source_exists(output, src[[1]]))
})

test_that("knitted recordings return media only at completion", {
  skip_if_not_installed("knitr")
  skip_if_no_gifski()
  skip_if_no_av()
  prior_format <- knitr::opts_knit$get("rmarkdown.pandoc.to")
  withr::defer(knitr::opts_knit$set(rmarkdown.pandoc.to = prior_format))
  knitr::opts_knit$set(rmarkdown.pandoc.to = "html")
  page <- local_record_page()
  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  text <- paste(
    '```{r demo, echo=FALSE, error=FALSE}',
    'start <- withVisible(pz_record_start(page, fps=5, hold=c(0, 0), format="gif"))',
    'stopifnot(!start$visible, identical(start$value$page, page))',
    'pz_wait(page, 0.2)',
    'pz_record_stop(page)',
    'pz_record(page, code = { pz_wait(page, 0.2) }, fps=5, hold=c(0, 0), format="gif")',
    'start <- pz_record_start(page, path=NULL, fps=5, hold=c(0, 0), format="gif")',
    'pz_wait(page, 0.2)',
    'pz_record_stop(start)',
    'pz_record(page, path=NULL, code = { pz_wait(page, 0.2) }, fps=5, hold=c(0, 0), format="gif")',
    'pz_record(page, "named.gif", { pz_wait(page, 0.2) }, fps=5, hold=c(0, 0))',
    'pz_record(page, "named.mp4", { pz_wait(page, 0.2) }, fps=5, hold=c(0, 0))',
    'page |> pz_record_start("split.webm", fps=5, hold=c(0, 0))',
    'pz_wait(page, 0.2)',
    'pz_record_stop(page)',
    '```',
    sep = "\n"
  )
  markdown <- knitr::knit(text = text, envir = environment(), quiet = TRUE)
  expect_false(grepl("Error", markdown, fixed = TRUE))
  gifs <- list.files(
    "figure",
    pattern = "[.]gif$",
    recursive = TRUE,
    full.names = TRUE
  )
  expect_length(gifs, 4L)
  expect_true(all(file.exists(gifs)))
  expect_match(markdown, "demo-1.gif", fixed = TRUE)
  expect_match(markdown, "demo-2.gif", fixed = TRUE)
  expect_match(markdown, "demo-3.gif", fixed = TRUE)
  expect_match(markdown, "demo-4.gif", fixed = TRUE)
  expect_true(file.exists("named.gif"))
  expect_match(markdown, "named.gif", fixed = TRUE)
  expect_true(file.exists("named.mp4"))
  expect_match(markdown, "named.mp4", fixed = TRUE)
  expect_match(
    markdown,
    "<video controls preload=\"metadata\" src=\"",
    fixed = TRUE
  )
  expect_true(file.exists("split.webm"))
  expect_match(markdown, "split.webm", fixed = TRUE)
})

test_that("knitted recording chains stop at the end of their expression", {
  skip_if_not_installed("knitr")
  skip_if_no_gifski()
  skip_if_no_av()
  prior_format <- knitr::opts_knit$get("rmarkdown.pandoc.to")
  withr::defer(knitr::opts_knit$set(rmarkdown.pandoc.to = prior_format))
  page <- local_record_page()
  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  knitr::opts_knit$set(rmarkdown.pandoc.to = "html")
  text <- paste(
    '```{r chain, echo=FALSE, error=FALSE}',
    'page |> pz_record_start(fps=5, hold=c(0, 0)) |> pz_wait(0.2)',
    'rec <- page |> pz_record_start("split.gif", fps=5, hold=c(0, 0))',
    'page |> pz_wait(0.1)',
    'rec |> pz_find("body") |> pz_wait(0.1)',
    'stopifnot(is.null(page_recorder(page)))',
    '```',
    sep = "\n"
  )
  markdown <- knitr::knit(text = text, envir = environment(), quiet = TRUE)
  expect_false(grepl("Error", markdown, fixed = TRUE))
  expect_match(markdown, "chain-1.mp4", fixed = TRUE)
  expect_length(list.files("figure", pattern = "[.]mp4$"), 1L)
  expect_match(markdown, "<video controls", fixed = TRUE)
  expect_match(markdown, "split.gif", fixed = TRUE)
  expect_true(file.exists("split.gif"))
  expect_false(grepl("paparazzi page", markdown, fixed = TRUE))

  knitr::opts_knit$set(rmarkdown.pandoc.to = "latex")
  text <- paste(
    '```{r latex, echo=FALSE, error=FALSE}',
    'page |> pz_record_start(fps=5, hold=c(0, 0)) |> pz_wait(0.2)',
    '```',
    sep = "\n"
  )
  markdown <- knitr::knit(text = text, envir = environment(), quiet = TRUE)
  expect_match(markdown, "latex-1.gif", fixed = TRUE)
})

test_that("recording chains return visibly until their recording stops", {
  page <- local_record_page()
  skip_if_no_av()
  out <- withr::local_tempfile(fileext = ".mp4")
  start <- withVisible(pz_record_start(page, out, fps = 5, hold = c(0, 0)))
  defer_record_stop(page)
  rec <- start$value
  expect_false(start$visible)
  expect_false(identical(rec, page))
  expect_true(withVisible(pz_wait(rec, 0.1))$visible)
  expect_false(withVisible(pz_wait(page, 0.1))$visible)
  scoped <- pz_find(rec, "body")
  expect_true(withVisible(pz_wait(scoped, 0.1))$visible)
  expect_true(withVisible(pz_find_reset(scoped) |> pz_wait(0.1))$visible)
  expect_false(withVisible(pz_find(page, "body") |> pz_wait(0.1))$visible)
  expect_error(pz_record_start(rec, out), class = "paparazzi_error_record")

  expect_silent(print(scoped))
  expect_null(page_recorder(page))
  expect_true(file.exists(out))
  expect_gt(recorded_video_info(out)$duration, 0)
  expect_false(withVisible(pz_wait(rec, 0))$visible)
  expect_output(print(rec), "paparazzi page")

  nav <- withr::local_tempfile(fileext = ".mp4")
  chain <- pz_record_start(page, nav, fps = 5, hold = c(0, 0)) |>
    pz_nav_reload()
  expect_true(withVisible(pz_nav_reload(chain, wait = "none"))$visible)
  expect_true(
    withVisible(pz_wait_for_navigation(chain, wait = "none"))$visible
  )
  print(chain)
  expect_true(file.exists(nav))
  expect_null(page_recorder(page))

  # A stale chain doesn't adopt a later recording.
  pz_record_start(page, withr::local_tempfile(fileext = ".mp4"))
  expect_false(withVisible(pz_wait(rec, 0))$visible)
  pz_record_stop(page)
})

test_that("interactive recordings without a path preview in the viewer", {
  page <- local_record_page()
  skip_if_no_av()
  viewed <- character()
  withr::local_options(
    rlang_interactive = TRUE,
    viewer = function(url) viewed <<- c(viewed, url)
  )
  pz_record_start(page, fps = 5, hold = c(0, 0))
  defer_record_stop(page)
  pz_wait(page, 0.1)
  preview <- withVisible(pz_record_stop(page))
  expect_true(preview$visible)
  expect_s3_class(preview$value, "paparazzi_preview")
  expect_equal(tools::file_ext(preview$value), "mp4")
  expect_true(file.exists(preview$value))
  expect_length(viewed, 0)
  print(preview$value)
  expect_length(viewed, 1)
  expect_equal(basename(viewed), "index.html")
  html <- paste(readLines(viewed), collapse = "\n")
  expect_match(html, "<video", fixed = TRUE)
  expect_true(file.exists(file.path(dirname(viewed), basename(preview$value))))

  out <- withr::local_tempfile(fileext = ".gif")
  skip_if_no_gifski()
  chain <- pz_record_start(page, out, fps = 5, hold = c(0, 0)) |>
    pz_wait(0.1)
  print(chain)
  expect_true(file.exists(out))
  expect_equal(viewed[[2]], out)

  webm <- pz_record(page, format = "webm", code = pz_wait(page, 0.1))
  expect_s3_class(webm, "paparazzi_preview")
  expect_equal(tools::file_ext(webm), "webm")
})

test_that("previews stage files the viewer can't serve", {
  inside <- withr::local_tempfile(fileext = ".gif")
  writeBin(charToRaw("gif"), inside)
  expect_identical(preview_stage(inside), inside)

  dir <- withr::local_tempdir(tmpdir = test_path())
  outside <- file.path(dir, "outside.gif")
  writeBin(charToRaw("gif"), outside)
  staged <- preview_stage(outside)
  expect_true(startsWith(normalizePath(staged), normalizePath(tempdir())))
  expect_equal(basename(staged), "outside.gif")

  sibling <- paste0(normalizePath(tempdir()), "-sibling.gif")
  writeBin(charToRaw("gif"), sibling)
  withr::defer(unlink(sibling))
  expect_false(identical(preview_stage(sibling), sibling))

  video <- file.path(dir, "clip.mp4")
  writeBin(charToRaw("mp4"), video)
  page <- preview_stage(video)
  expect_equal(basename(page), "index.html")
  expect_true(file.exists(file.path(dirname(page), "clip.mp4")))
})

test_that("pz_record encodes on error and returns ctx invisibly", {
  page <- local_record_page()
  skip_if_no_av()

  out <- withr::local_tempfile(fileext = ".mp4")
  expect_error(
    pz_record(page, out, {
      pz_wait(page, 0.4)
      stop("boom")
    }),
    "boom",
    class = "simpleError"
  )
  expect_true(file.exists(out))
  expect_gt(recorded_video_info(out)$duration, 0)

  out2 <- withr::local_tempfile(fileext = ".mp4")
  res <- withVisible(pz_record(page, out2, pz_wait(page, 0.2)))
  expect_false(res$visible)
  expect_identical(res$value, page)
  expect_true(file.exists(out2))
})

test_that("an interrupt stops the recorder and permits another recording", {
  page <- local_record_page()
  skip_if_no_av()
  interrupted <- withr::local_tempfile(fileext = ".mp4")
  condition <- structure(
    list(message = "record interrupted"),
    class = c("interrupt", "condition")
  )
  caught <- tryCatch(
    pz_record(
      page,
      interrupted,
      {
        pz_wait(page, 0.2)
        stop(condition)
      },
      fps = 5,
      hold = c(0, 0)
    ),
    interrupt = identity
  )
  expect_s3_class(caught, "interrupt")
  expect_match(conditionMessage(caught), "record interrupted")
  expect_null(page_recorder(page$page))
  expect_true(file.exists(interrupted))
  next_path <- withr::local_tempfile(fileext = ".mp4")
  pz_record(page, next_path, pz_wait(page, 0.2), fps = 5, hold = c(0, 0))
  expect_true(file.exists(next_path))
})

test_that("block error wins over stop failure and the page can record again", {
  page <- local_record_page()
  skip_if_no_av()
  failed <- withr::local_tempfile(fileext = ".mp4")
  with_mocked_bindings(
    expect_error(
      pz_record(
        page,
        failed,
        {
          pz_wait(page, 0.2)
          stop("block failed")
        },
        fps = 5,
        hold = c(0, 0)
      ),
      "block failed",
      class = "simpleError"
    ),
    record_encode = function(...) stop("stop failed")
  )
  expect_null(page_recorder(page$page))
  next_path <- withr::local_tempfile(fileext = ".mp4")
  pz_record(page, next_path, pz_wait(page, 0.2), fps = 5, hold = c(0, 0))
  expect_true(file.exists(next_path))
})

test_that("pz_record_hold extends the video and is a no-op otherwise", {
  page <- local_record_page()
  skip_if_no_av()

  out <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(out, fps = 10, hold = c(0, 0))
  pz_wait(page, 0.3)
  page |> pz_record_hold(1)
  pz_wait(page, 0.2)
  page |> pz_record_stop()

  info <- recorded_video_info(out)
  # ~0.5s recorded + 1s hold; real time was only ~0.5s
  expect_gte(info$duration, 1.2)
  expect_lte(info$duration, 2.0)

  start <- Sys.time()
  res <- withVisible(pz_record_hold(page, 2))
  elapsed <- as.numeric(difftime(Sys.time(), start, units = "secs"))
  expect_lt(elapsed, 0.5)
  expect_false(res$visible)
  expect_identical(res$value, page)
})

test_that("frames are resampled to the requested constant fps", {
  page <- local_record_page()
  skip_if_no_av()

  out5 <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record(out5, pz_wait(page, 0.6), fps = 5, hold = c(0, 0))
  info5 <- recorded_video_info(out5)

  out20 <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record(out20, pz_wait(page, 0.6), fps = 20, hold = c(0, 0))
  info20 <- recorded_video_info(out20)

  # same real time, different output rates: durations agree, frame
  # counts track fps
  expect_gte(info5$duration, 0.4)
  expect_lte(info5$duration, 1.2)
  expect_gte(info20$duration, 0.4)
  expect_lte(info20$duration, 1.2)
  expect_lte(info5$frames, 8)
  expect_gte(info20$frames, 8)
})

test_that("gif encodes via gifski", {
  page <- local_record_page()
  skip_if_no_gifski()

  out <- withr::local_tempfile(fileext = ".gif")
  page |> pz_record(out, pz_wait(page, 0.4), fps = 10, hold = c(0.2, 0.2))

  expect_true(file.exists(out))
  if (rlang::is_installed("av")) {
    info <- recorded_video_info(out)
    expect_equal(info$codec, "gif")
    expect_gte(info$duration, 0.6)
    expect_lte(info$duration, 1.2)
  }
})

test_that("framed GIFs give gifski losslessly cropped unique captures", {
  skip_if_no_gifski()
  testthat::skip_if_not_installed("png")
  page <- local_record_page()
  pz_js(
    page,
    "document.body.style.background = '#fdfdf5';
    document.getElementById('box').style.background = '#fdfdf5';
    document.getElementById('box').textContent = 'Flat text';"
  )
  dpr <- page_dpr(page)
  out <- withr::local_tempfile(fileext = ".gif")
  raw_dir <- paste0(tools::file_path_sans_ext(out), "_frames")
  withr::defer(unlink(raw_dir, recursive = TRUE))
  captured <- NULL
  local_mocked_bindings(
    gifski = function(png_files, gif_file, width, height, ...) {
      raw <- unique(rec$files)
      spec <- record_output_spec(rec, png_read_size(raw[[1]]))
      crop <- spec$crop
      expect_equal(crop$width, round(116 * dpr))
      expect_equal(crop$height, round(76 * dpr))
      expect_true(length(raw) >= 1L)
      expect_true(length(png_files) > length(unique(png_files)))
      expect_equal(
        length(list.files(dirname(png_files[[1]]), pattern = "[.]png$")),
        length(raw)
      )
      expect_equal(basename(png_files), basename(record_resample(rec)$files))
      expect_equal(c(width, height), c(spec$width, spec$height))
      expect_false(any(png_files %in% raw))
      expect_true(all(file.exists(png_files)))
      for (i in seq_along(raw)) {
        source <- png::readPNG(raw[[i]])
        cropped <- png::readPNG(file.path(
          dirname(png_files[[1]]),
          basename(raw[[i]])
        ))
        expect_equal(dim(cropped)[1:2], c(crop$height, crop$width))
        expect_equal(
          cropped,
          source[
            seq.int(crop$y + 1L, length.out = crop$height),
            seq.int(crop$x + 1L, length.out = crop$width),
            ,
            drop = FALSE
          ]
        )
      }
      captured <<- png_files
    },
    .package = "gifski"
  )
  page |>
    pz_record_start(
      out,
      fps = 10,
      scale = 0.5,
      hold = c(0.5, 0.5),
      frame = pz_frame("#box", pad = 8),
      keep_frames = TRUE
    )
  rec <- page_recorder(page)
  pz_wait(page, 0.3)
  page |> pz_record_stop()
  expect_gt(length(captured), 0L)
  expect_true(all(file.exists(rec$files)))
  expect_false(any(file.exists(unique(captured))))
})

test_that("GIF frame crops preserve alpha and crop unique PNGs", {
  skip_if_no_gifski()
  testthat::skip_if_not_installed("png")
  source <- withr::local_tempfile(fileext = ".png")
  image <- array(seq(0, 1, length.out = 5 * 5 * 4), c(5, 5, 4))
  png::writePNG(image, source)
  rec <- list(
    format = "gif",
    path = withr::local_tempfile(fileext = ".gif"),
    files = c(source, source),
    times = c(0, 0.1),
    vt_end = 0.1,
    holds = list(),
    hold_first = 0.5,
    hold_last = 0,
    fps = 10,
    scale = NULL,
    crop = list(x = 1, y = 2, width = 3, height = 2, viewport_width = 5)
  )
  input <- png::readPNG(source)
  cropped_path <- NULL
  local_mocked_bindings(
    gifski = function(png_files, width, height, ...) {
      expect_equal(c(width, height), c(3, 2))
      expect_length(unique(png_files), 1L)
      expect_equal(dim(png::readPNG(png_files[[1]])), c(2, 3, 4))
      expect_equal(
        png::readPNG(png_files[[1]]),
        input[3:4, 2:4, , drop = FALSE]
      )
      cropped_path <<- png_files[[1]]
    },
    .package = "gifski"
  )
  record_encode(rec)
  expect_false(file.exists(cropped_path))
  expect_true(file.exists(source))
})

test_that("unframed GIFs of odd size go to gifski uncropped", {
  skip_if_no_gifski()
  testthat::skip_if_not_installed("png")
  source <- withr::local_tempfile(fileext = ".png")
  png::writePNG(array(0.5, c(5, 7, 3)), source)
  rec <- list(
    format = "gif",
    path = withr::local_tempfile(fileext = ".gif"),
    files = source,
    times = 0,
    vt_end = 0,
    holds = list(),
    hold_first = 0.2,
    hold_last = 0,
    fps = 10,
    crop = NULL,
    scale = NULL
  )
  local_mocked_bindings(
    gifski = function(png_files, width, height, ...) {
      expect_equal(c(width, height), c(7, 5))
      expect_true(all(png_files == source))
    },
    .package = "gifski"
  )
  record_encode(rec)
})

test_that("GIF dependencies are checked before recording", {
  requested <- character()
  present <- character()
  local_mocked_bindings(
    check_installed = function(pkg, reason = NULL, ...) {
      requested <<- c(requested, pkg)
      if (!pkg %in% present) stop(paste("missing", pkg, reason))
    },
    .package = "rlang"
  )
  expect_error(record_check_packages("gif", FALSE), "missing gifski")
  present <- "gifski"
  expect_no_error(record_check_packages("gif", FALSE))
  expect_equal(tail(requested, 1), "gifski")
  expect_error(record_check_packages("gif", TRUE), "missing png")
  present <- c("gifski", "png", "av")
  requested <- character()
  expect_no_error(record_check_packages("gif", TRUE))
  expect_equal(requested, c("gifski", "png"))
  requested <- character()
  expect_no_error(record_check_packages("mp4", FALSE))
  expect_equal(requested, "av")
})

test_that("an immediate stop still writes a one-frame video", {
  page <- local_record_page()
  skip_if_no_av()

  out <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(out, fps = 10, hold = c(0, 0))
  page |> pz_record_stop()

  expect_true(file.exists(out))
  expect_gte(recorded_video_info(out)$frames, 1)
})

test_that("stop captures a final frame after a late page change", {
  page <- local_record_page()
  skip_if_no_av()
  testthat::skip_if_not_installed("png")

  out <- withr::local_tempfile(fileext = ".mp4")
  frames_dir <- paste0(tools::file_path_sans_ext(out), "_frames")
  withr::defer(unlink(frames_dir, recursive = TRUE))
  page |> pz_record_start(out, fps = 10, hold = c(0, 0), keep_frames = TRUE)
  defer_record_stop(page)
  pz_wait(page, 0.4)
  # A change right before stop must appear in the final frame; without
  # the stop-time capture the video would end on an older one.
  pz_js(
    page,
    "document.getElementById('box').style.backgroundColor = 'rgb(255, 0, 0)'"
  )
  page |> pz_record_stop()

  files <- sort(list.files(frames_dir, full.names = TRUE, pattern = "[.]png$"))
  expect_gte(length(files), 2L)
  dpr <- page_dpr(page)
  # a pixel inside #box (CSS left 40, top 30, 100x60), in device pixels
  pixel <- function(path) {
    img <- png::readPNG(path)
    unname(img[round(40 * dpr) + 1, round(50 * dpr) + 1, 1:3])
  }
  expect_false(isTRUE(all.equal(
    pixel(files[[1]]),
    c(1, 0, 0),
    tolerance = 0.05
  )))
  expect_equal(pixel(files[[length(files)]]), c(1, 0, 0), tolerance = 0.05)
})

test_that("late capture callbacks cannot consume the final capture slot", {
  for (late in c("success", "error")) {
    callbacks <- new.env(parent = emptyenv())
    callbacks$metrics <- list()
    callbacks$frames <- list()
    page <- list(
      default_timeout = 5,
      session = list(
        Page = list(
          getLayoutMetrics = function(..., callback_, error_) {
            callbacks$metrics[[length(callbacks$metrics) + 1L]] <- callback_
          },
          captureScreenshot = function(..., callback_, error_) {
            callbacks$frames[[length(callbacks$frames) + 1L]] <- list(
              success = callback_,
              error = error_
            )
          }
        )
      )
    )
    rec <- new_recorder(
      path = tempfile(fileext = ".mp4"),
      format = "mp4",
      fps = 10,
      scale = NULL,
      hold = c(0, 0),
      keep_frames = TRUE,
      frame = NULL
    )
    rec$frames_dir <- withr::local_tempdir()
    metrics <- list(
      cssVisualViewport = list(
        pageX = 0,
        pageY = 0,
        clientWidth = 640,
        clientHeight = 480
      )
    )

    record_capture(rec, page, if (late == "error") 2 else 1)
    callbacks$metrics[[1]](metrics)
    rec$pending <- NULL # The stop poll timed out and retired this capture.
    record_capture(rec, page, 2)
    callbacks$metrics[[2]](metrics)
    final_pending <- rec$pending
    expect_length(callbacks$frames, 2)

    if (late == "success") {
      callbacks$frames[[1]]$success(list(
        data = jsonlite::base64_enc(charToRaw("stale"))
      ))
    } else {
      callbacks$frames[[1]]$error(simpleError("late capture error"))
    }
    expect_identical(rec$pending, final_pending)
    expect_length(rec$files, 0)
    expect_length(rec$times, 0)
    expect_equal(rec$n_errors, 0L)
    expect_null(rec$first_error)
    expect_false(file.exists(final_pending$file))

    callbacks$frames[[2]]$success(list(
      data = jsonlite::base64_enc(charToRaw("final"))
    ))
    expect_null(rec$pending)
    expect_equal(rec$times, 2)
    expect_identical(rec$files, final_pending$file)
    expect_true(file.exists(final_pending$file))
    if (file.exists(final_pending$file)) {
      expect_identical(
        readBin(final_pending$file, "raw", n = 5),
        charToRaw("final")
      )
    }
    expect_equal(rec$n_errors, 0L)
  }
})

test_that("an immediate block error is not masked by the stop", {
  page <- local_record_page()
  skip_if_no_av()

  out <- withr::local_tempfile(fileext = ".mp4")
  expect_error(
    pz_record(page, out, stop("boom")),
    "boom",
    class = "simpleError"
  )
})

test_that("a quick restart does not double the capture chain", {
  page <- local_record_page()
  skip_if_no_av()

  out1 <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(out1, fps = 2, hold = c(0, 0))
  pz_wait(page, 0.3)
  # a tick from the first recording is still scheduled when stop runs
  page |> pz_record_stop()

  out2 <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(out2, fps = 2, hold = c(0, 0))
  rec <- page_recorder(page)
  start <- Sys.time()
  # Pump the 1.2s observation window, but require two ticks within it: a
  # stalled pump must not fail the lower bound.
  pz_poll(
    function() {
      rec$ticks >= 2L &&
        as.numeric(difftime(Sys.time(), start, units = "secs")) >= 1.2
    },
    timeout = 5,
    loop = page$page$child_loop,
    what = "two capture ticks within the observation window"
  )
  elapsed <- as.numeric(difftime(Sys.time(), start, units = "secs"))
  ticks <- rec$ticks
  page |> pz_record_stop()

  # one chain at 2 fps ticks every 0.5s; a second chain left over from the
  # first recording would double the rate
  expect_gte(ticks, 2L)
  expect_lte(ticks, ceiling(elapsed / 0.35))
})

test_that("closing the page tears down the recorder synchronously", {
  page <- local_record_page()

  out <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(out, fps = 10, hold = c(0, 0))
  rec <- page_recorder(page)
  expect_true(rec$active)
  frames_dir <- rec$frames_dir
  expect_true(dir.exists(frames_dir))

  pz_close(page)

  # no tick involved: the close path itself clears the recorder slot,
  # deactivates the recorder, and drops the temp frames dir -- the
  # closed session's loop may never pump again
  expect_null(page_recorder(page))
  expect_false(rec$active)
  expect_false(dir.exists(frames_dir))
})

test_that("a frame crops the recording at encode time", {
  page <- local_record_page()
  skip_if_no_av()
  dpr <- page_dpr(page)

  out <- withr::local_tempfile(fileext = ".mp4")
  page |>
    pz_record(
      out,
      pz_wait(page, 0.3),
      fps = 10,
      hold = c(0, 0),
      frame = pz_frame("#box", pad = 8)
    )

  info <- recorded_video_info(out)
  # #box is 100x60; pad 8 gives 116x76 CSS pixels, converted to device
  # pixels and floored to a multiple of 4
  expect_equal(info$width, floor(round(116 * dpr) / 4) * 4)
  expect_equal(info$height, floor(round(76 * dpr) / 4) * 4)
})

test_that("frame when = start and stop measure at different times", {
  page <- local_record_page()
  skip_if_no_av()
  dpr <- page_dpr(page)
  width_at <- function(css) floor(round(css * dpr) / 4) * 4

  out_stop <- withr::local_tempfile(fileext = ".mp4")
  page |>
    pz_record_start(
      out_stop,
      fps = 10,
      hold = c(0, 0),
      frame = pz_frame("#box", pad = 8)
    )
  pz_js(page, "growBox()")
  pz_wait(page, 0.3)
  page |> pz_record_stop()
  # measured against the final layout: the grown 200px-wide box
  expect_equal(recorded_video_info(out_stop)$width, width_at(216))

  out_start <- withr::local_tempfile(fileext = ".mp4")
  page$session$Page$reload()
  pz_wait(page, 0.3)
  page |>
    pz_record_start(
      out_start,
      fps = 10,
      hold = c(0, 0),
      frame = pz_frame("#box", pad = 8, when = "start")
    )
  pz_js(page, "growBox()")
  pz_wait(page, 0.3)
  page |> pz_record_stop()
  # measured at the start: the original 100px-wide box
  expect_equal(recorded_video_info(out_start)$width, width_at(116))
})

test_that("a targetless stop frame crops from the start-time scope", {
  page <- local_record_page()
  skip_if_no_av()
  dpr <- page_dpr(page)
  width_at <- function(css) floor(round(css * dpr) / 4) * 4

  out <- withr::local_tempfile(fileext = ".mp4")
  page |>
    pz_find("#box") |>
    pz_record_start(out, fps = 10, hold = c(0, 0), frame = pz_frame())
  pz_wait(page, 0.2)
  # stopping from the root context must not swap the crop to the
  # viewport; it still covers the scope the recording started in
  page |> pz_record_stop()

  info <- recorded_video_info(out)
  # #box is 100x60
  expect_equal(info$width, width_at(100))
  expect_equal(info$height, width_at(60))
})

test_that("a framed recording survives a navigation by framing the viewport", {
  page <- local_record_page()
  skip_if_no_av()
  dpr <- page_dpr(page)
  vw <- pz_js(page, "innerWidth")
  vh <- pz_js(page, "innerHeight")
  width_at <- function(css) floor(round(css * dpr) / 4) * 4
  height_at <- function(css) floor(round(css * dpr) / 4) * 4

  out <- withr::local_tempfile(fileext = ".mp4")
  page |>
    pz_find("#box") |>
    pz_record_start(out, fps = 10, hold = c(0, 0), frame = pz_frame())
  pz_wait(page, 0.2)
  root <- pz_nav_goto(page, nav_fixture_url("b"))
  # Frames keep being captured on the new document: require frames that
  # completed after the navigation settled, not a total count that frames
  # captured before it can satisfy.
  before <- length(page_recorder(root)$files)
  pz_poll(
    function() length(page_recorder(root)$files) >= before + 2L,
    timeout = root$page$default_timeout,
    loop = root$page$child_loop,
    what = "frames captured after the navigation"
  )
  expect_no_error(pz_record_stop(root))

  info <- recorded_video_info(out)
  expect_gte(info$frames, 3)
  # The navigation released the scope the recording started in, so the
  # not-yet-measured when = "stop" crop resolved as the full viewport
  # instead of raising the detach error.
  expect_equal(info$width, width_at(vw))
  expect_equal(info$height, height_at(vh))
})

test_that("a when = start crop is measured before the navigation and stays", {
  page <- local_record_page()
  skip_if_no_av()
  dpr <- page_dpr(page)
  width_at <- function(css) floor(round(css * dpr) / 4) * 4

  out <- withr::local_tempfile(fileext = ".mp4")
  page |>
    pz_find("#box") |>
    pz_record_start(
      out,
      fps = 10,
      hold = c(0, 0),
      frame = pz_frame(when = "start")
    )
  pz_wait(page, 0.2)
  pz_nav_goto(page, nav_fixture_url("b"))
  pz_wait(page, 0.3)
  expect_no_error(pz_record_stop(page))
  # Measured before the navigation: the 100px box as it was, a fixed
  # box in viewport coordinates.
  expect_equal(recorded_video_info(out)$width, width_at(100))
})

test_that("the even crop rounds clamped edges inward, staying inside bounds", {
  page <- local_record_page()

  # Fractional bounds that clamp all four edges of #box (40,30 to
  # 140,90): a left bound at 40.8 and a right bound at 101.2 would
  # round to 40 and 102 under nearest-even -- outside the bounds.
  pz_js(
    page,
    "const b = document.createElement('div');
     b.id = 'frac';
     b.style.cssText =
       'position:absolute; left:40.8px; top:20px; width:60.4px; height:120px';
     document.body.appendChild(b);"
  )
  crop <- record_crop_box(page, frame_fill(pz_frame("#box", bounds = "#frac")))

  # pinned edges round inward: left up to 42, right down to 100
  expect_equal(crop$x, 42)
  expect_equal(crop$width, 58)
  expect_gte(crop$x, 40.8)
  expect_lte(crop$x + crop$width, 101.2)
})

test_that("recorded clicks reach above- and below-fold buttons at DPR 2", {
  page <- local_record_page()
  skip_if_no_av()
  pz_device(page, width = 640, height = 560)
  pz_js(
    page,
    "(() => {
    document.body.insertAdjacentHTML('beforeend', '<button id=top style=\"position:absolute;left:280px;top:100px;width:120px;height:48px\">Top</button><button id=bottom style=\"position:absolute;left:280px;top:850px;width:120px;height:48px\">Bottom</button>');
    window.recordClicks = [];
    document.addEventListener('mousedown', e => recordClicks.push(e.target.id));
    return true;
  })()"
  )

  # Frames cover the visual viewport, which classic scrollbars (CI's
  # headless Chrome) shrink below the 640x560 device size; measure it
  # live instead of hardcoding 1280x1120.
  viewport_size <- record_viewport_png_size(page)

  out <- withr::local_tempfile(fileext = ".mp4")
  frames_dir <- paste0(tools::file_path_sans_ext(out), "_frames")
  withr::defer(unlink(frames_dir, recursive = TRUE))
  pz_record_start(page, out, fps = 30, hold = c(0, 0), keep_frames = TRUE)
  defer_record_stop(page)
  targets <- rep(c("bottom", "top"), 4)
  for (target in targets) {
    pz_act_click(page, paste0("#", target))
  }
  pz_record_stop(page)

  expect_equal(unlist(pz_js(page, "window.recordClicks")), targets)
  files <- sort(list.files(frames_dir, pattern = "[.]png$", full.names = TRUE))
  expect_gt(length(files), 0)
  expect_frame_files_size(files, viewport_size)
  # yuv420p aligns the width down to a multiple of 4.
  expect_equal(
    recorded_video_info(out)$width,
    floor(viewport_size[[1]] / 4) * 4
  )
})

test_that("framed DPR-2 recordings retain viewport frames and click targets", {
  page <- local_record_page()
  skip_if_no_av()
  pz_device(page, width = 640, height = 560)
  pz_js(
    page,
    "(() => {
    document.body.insertAdjacentHTML('beforeend', '<h1 style=\"display:inline-block\">Tasks</h1><main style=\"width:420px;padding:70px;box-sizing:border-box\"><button id=task-title style=\"width:180px;height:40px\">Title</button><button id=add-task style=\"width:180px;height:40px\">Add</button></main>');
    window.recordClicks = [];
    document.addEventListener('mousedown', e => recordClicks.push(e.target.id));
    return true;
  })()"
  )

  # Frames cover the visual viewport at the device density, measured
  # live so classic-scrollbar platforms (CI's headless Chrome) don't
  # need the overlay-scrollbar size 1280x1120.
  viewport_size <- record_viewport_png_size(page)

  out <- withr::local_tempfile(fileext = ".mp4")
  frames_dir <- paste0(tools::file_path_sans_ext(out), "_frames")
  withr::defer(unlink(frames_dir, recursive = TRUE))
  pz_record_start(
    page,
    out,
    fps = 30,
    hold = c(0, 0),
    keep_frames = TRUE,
    frame = pz_frame(list("h1", "main"), pad = 16)
  )
  defer_record_stop(page)
  for (target in rep(c("task-title", "add-task"), 4)) {
    pz_act_click(page, paste0("#", target))
  }
  pz_record_stop(page)

  expect_equal(
    unlist(pz_js(page, "window.recordClicks")),
    rep(c("task-title", "add-task"), 4)
  )
  files <- sort(list.files(frames_dir, pattern = "[.]png$", full.names = TRUE))
  expect_gt(length(files), 0)
  expect_frame_files_size(files, viewport_size)
  info <- recorded_video_info(out)
  # The frame crop is smaller than the full viewport it came from.
  expect_lt(info$width, viewport_size[[1]])
  expect_lt(info$height, viewport_size[[2]])
})

test_that("a device hold skips capture ticks and clears on exit", {
  page <- local_record_page()
  rec <- new_recorder("unused.mp4", "mp4", 10, NULL, c(0, 0), FALSE, NULL)
  page_set_recorder(page$page, rec)
  withr::defer(page_set_recorder(page$page, NULL))
  captures <- 0L
  local_mocked_bindings(
    record_capture = function(...) captures <<- captures + 1L
  )

  expect_identical(
    record_device_change(page$page, {
      expect_true(rec$held)
      record_tick(page$page, rec)
      "done"
    }),
    "done"
  )
  expect_identical(captures, 0L)
  expect_identical(rec$ticks, 1L)
  expect_identical(rec$vt_base, 0)
  expect_false(rec$paused)
  expect_false(rec$held)

  expect_error(record_device_change(page$page, stop("boom")), "boom")
  expect_false(rec$held)
  rec$active <- FALSE
  expect_identical(record_device_change(page$page, 42), 42)
  expect_false(rec$held)
})

test_that("a device hold fails on a stuck capture and restores an outer hold", {
  page <- local_record_page()
  rec <- new_recorder("unused.mp4", "mp4", 10, NULL, c(0, 0), FALSE, NULL)
  page_set_recorder(page$page, rec)
  withr::defer(page_set_recorder(page$page, NULL))

  ran <- FALSE
  rec$pending <- new.env()
  local_mocked_bindings(
    pz_poll = function(...) {
      cli::cli_abort("Timed out.", class = "paparazzi_error_timeout")
    }
  )
  expect_error(
    record_device_change(page$page, ran <- TRUE),
    class = "paparazzi_error_timeout"
  )
  expect_false(ran)
  expect_false(rec$held)
  expect_identical(rec$n_errors, 0L)

  rec$pending <- NULL
  record_device_change(page$page, {
    record_device_change(page$page, NULL)
    expect_true(rec$held)
  })
  expect_false(rec$held)
})

test_that("device metrics survive an in-flight recording capture", {
  skip_if_no_av()
  page <- local_record_page()
  pz_device(page, width = 640, height = 560)

  out <- withr::local_tempfile(fileext = ".mp4")
  pz_record_start(page, out, fps = 10, hold = c(0, 0))
  defer_record_stop(page)
  rec <- page_recorder(page$page)
  capture_sent <- FALSE
  session <- page$page$session
  domain <- session$Page
  wrapped <- domain
  wrapped$captureScreenshot <- function(...) {
    capture_sent <<- TRUE
    domain$captureScreenshot(...)
  }
  session$Page <- wrapped
  withr::defer(session$Page <- domain)
  if (is.null(rec$pending)) {
    record_capture(rec, page$page, rec_vt(rec))
  }
  pz_poll(
    function() capture_sent,
    timeout = page$page$default_timeout,
    loop = page$page$child_loop,
    what = "the screenshot request"
  )
  expect_false(is.null(rec$pending))

  pz_device(page, width = 800, height = 600)
  pz_poll(
    function() is.null(rec$pending),
    timeout = page$page$default_timeout,
    loop = page$page$child_loop,
    what = "the in-flight frame capture"
  )
  pz_wait(page, 0.2)
  expect_equal(pz_js(page, "innerWidth"), 800)
  expect_equal(pz_js(page, "innerHeight"), 600)
})

test_that("recorded viewport clips follow scroll, zoom and resize", {
  skip_if_no_av()
  skip_if_not_installed("png")
  page <- local_record_page()
  # Styled scrollbars exercise classic gutters on overlay-scrollbar platforms.
  pz_js(
    page,
    "(() => {
    const style = document.createElement('style');
    style.textContent = '::-webkit-scrollbar { width: 15px; height: 15px }';
    document.head.appendChild(style);
    return true;
  })()"
  )
  pz_js(
    page,
    "(() => {
    document.body.insertAdjacentHTML('beforeend', '<div style=\"position:absolute;left:0;top:0;width:3000px;height:3000px;background:rgb(255,0,0)\"></div><div style=\"position:absolute;left:250px;top:450px;width:2000px;height:2000px;background:rgb(0,128,0)\"></div>');
    return true;
  })()"
  )
  frames_in <- function() page_recorder(page)$files

  for (method in c("css", "viewport")) {
    pz_device(page, width = 640, height = 560, zoom = 2, zoom_method = method)
    pz_js(page, "window.scrollTo(0, 0)")
    out <- withr::local_tempfile(fileext = ".mp4")
    frames_dir <- paste0(tools::file_path_sans_ext(out), "_frames")
    withr::defer(unlink(frames_dir, recursive = TRUE))
    pz_record_start(page, out, fps = 10, hold = c(0, 0), keep_frames = TRUE)
    defer_record_stop(page)

    viewport_size <- record_viewport_png_size(page)
    pz_poll(
      function() {
        files <- frames_in()
        length(files) > 0 &&
          identical(png_dimensions(tail(files, 1)), viewport_size)
      },
      timeout = 5,
      loop = page$page$child_loop,
      what = "a frame at the scrolled-back-to-top viewport"
    )
    before <- frames_in()
    expect_gt(length(before), 0)
    expect_equal(png_dimensions(tail(before, 1)), viewport_size)
    expect_equal(
      as.numeric(png::readPNG(tail(before, 1))[10, 10, 1:3]),
      c(1, 0, 0)
    )

    pz_js(page, "window.scrollTo(650, 1100)")
    expect_gt(pz_js(page, "window.scrollX"), 0)
    expect_gt(pz_js(page, "window.scrollY"), 0)
    pz_poll(
      function() {
        new <- setdiff(frames_in(), before)
        if (!length(new)) {
          return(FALSE)
        }
        pixel <- as.numeric(png::readPNG(tail(new, 1))[10, 10, 1:3])
        isTRUE(all.equal(pixel, c(0, 128 / 255, 0), tolerance = 1 / 255))
      },
      timeout = 5,
      loop = page$page$child_loop,
      what = "a frame showing the scrolled viewport"
    )
    scrolled <- setdiff(frames_in(), before)
    expect_equal(png_dimensions(tail(scrolled, 1)), viewport_size)
    expect_equal(
      as.numeric(png::readPNG(tail(scrolled, 1))[10, 10, 1:3]),
      c(0, 128 / 255, 0),
      tolerance = 1 / 255
    )

    pz_device(page, width = 800, height = 600)
    resized_size <- record_viewport_png_size(page)
    pz_poll(
      function() {
        new <- setdiff(frames_in(), c(before, scrolled))
        length(new) > 0 &&
          identical(png_dimensions(tail(new, 1)), resized_size)
      },
      timeout = 5,
      loop = page$page$child_loop,
      what = "a frame at the resized viewport"
    )
    resized <- setdiff(frames_in(), c(before, scrolled))
    expect_gt(length(resized), 0)
    expect_equal(png_dimensions(tail(resized, 1)), resized_size)
    pz_record_stop(page)
  }
})

test_that("classic scrollbars shrink captured frames to the visual viewport", {
  skip_if_no_av()
  page <- local_record_page()
  # Styled scrollbars exercise classic gutters on overlay-scrollbar platforms.
  pz_js(
    page,
    "(() => {
    const style = document.createElement('style');
    style.textContent = '::-webkit-scrollbar { width: 15px; height: 15px }';
    document.head.appendChild(style);
    document.body.insertAdjacentHTML('beforeend', '<div style=\"position:absolute;left:0;top:0;width:3000px;height:3000px\"></div>');
    return true;
  })()"
  )
  pz_device(page, width = 640, height = 560)
  # The fixture reserved gutter space: the visual viewport is smaller
  # than the window on every scrollbar style.
  expect_lt(
    pz_js(page, "window.visualViewport.width"),
    pz_js(page, "window.innerWidth")
  )

  out <- withr::local_tempfile(fileext = ".mp4")
  frames_dir <- paste0(tools::file_path_sans_ext(out), "_frames")
  withr::defer(unlink(frames_dir, recursive = TRUE))
  pz_record_start(page, out, fps = 10, hold = c(0, 0), keep_frames = TRUE)
  defer_record_stop(page)
  viewport_size <- record_viewport_png_size(page)
  pz_poll(
    function() {
      files <- page_recorder(page)$files
      length(files) > 0 &&
        identical(png_dimensions(tail(files, 1)), viewport_size)
    },
    timeout = 5,
    loop = page$page$child_loop,
    what = "the first recording frames"
  )
  files <- page_recorder(page)$files
  expect_gt(length(files), 0)
  expect_frame_files_size(files, viewport_size)
  pz_record_stop(page)
})

test_that("framed recordings reject viewport resizes and can record again", {
  skip_if_no_av()
  for (method in c("poll", "screencast")) {
    page <- local_page(
      record_fixture_file(),
      width = 640,
      height = 480,
      scale = 2
    )
    out <- withr::local_tempfile(fileext = ".mp4")
    pz_record_start(
      page,
      out,
      method = method,
      frame = pz_frame("#box", when = "stop"),
      fps = 10,
      hold = c(0, 0)
    )
    defer_record_stop(page)
    rec <- page_recorder(page)
    pz_poll(
      function() length(rec$files) >= 3L,
      timeout = 5,
      loop = page$page$child_loop,
      what = "the initial recording frames"
    )
    density <- if (method == "poll") 2L else 1L
    expect_equal(png_dimensions(rec$files[[1]]), c(640L, 480L) * density)

    pz_device(page, width = 800, height = 600)
    pz_poll(
      function() {
        identical(png_dimensions(tail(rec$files, 1)), c(800L, 600L) * density)
      },
      timeout = 5,
      loop = page$page$child_loop,
      what = "a frame at the resized viewport"
    )
    expect_error(
      pz_record_stop(page),
      "Resizing the viewport.*not supported",
      class = "paparazzi_error_record"
    )
    expect_false(rec$active)
    expect_null(page_recorder(page))
    expect_null(rec$deregister_screencast)
    expect_false(dir.exists(rec$frames_dir))
    expect_false(file.exists(out))

    next_path <- withr::local_tempfile(fileext = ".mp4")
    pz_record_start(
      page,
      next_path,
      method = method,
      frame = pz_frame("#box", when = "stop"),
      fps = 10,
      hold = c(0, 0)
    )
    pz_wait(page, 0.3)
    pz_record_stop(page)
    expect_true(file.exists(next_path))
    pz_close(page)
  }
})

test_that("framed screencasts at a fractional DPR encode without a resize", {
  skip_if_no_av()
  page <- local_page(
    record_fixture_file(),
    width = 640,
    height = 480,
    scale = 1.5
  )
  out <- withr::local_tempfile(fileext = ".mp4")
  pz_record_start(
    page,
    out,
    method = "screencast",
    frame = pz_frame("#box", when = "stop"),
    fps = 10,
    hold = c(0, 0),
    keep_frames = TRUE
  )
  defer_record_stop(page)
  rec <- page_recorder(page)
  withr::defer(unlink(rec$frames_dir, recursive = TRUE))
  pz_wait(page, 0.3)
  pz_record_stop(page)

  expect_true(file.exists(out))
  sizes <- unique(lapply(rec$files, png_dimensions))
  expect_length(sizes, 1L)
})

test_that("staged frames reject resizes and keep requested frames", {
  skip_if_no_av()
  page <- local_page(
    record_fixture_file(),
    width = 640,
    height = 480,
    scale = 2
  )
  pz_stage_frame(page, "#box")
  out <- withr::local_tempfile(fileext = ".mp4")
  pz_record_start(page, out, fps = 10, hold = c(0, 0), keep_frames = TRUE)
  defer_record_stop(page)
  rec <- page_recorder(page)
  withr::defer(unlink(rec$frames_dir, recursive = TRUE))
  pz_poll(
    function() length(rec$files) >= 3L,
    timeout = 5,
    loop = page$page$child_loop,
    what = "the initial recording frames"
  )
  pz_device(page, width = 800, height = 600)
  expect_error(
    pz_record_stop(page),
    "Set the viewport size before",
    class = "paparazzi_error_record"
  )
  expect_null(page_recorder(page))
  expect_true(dir.exists(rec$frames_dir))
  expect_true(all(file.exists(rec$files)))
})

test_that("encode checks even unsampled frames for width and height changes", {
  skip_if_not_installed("png")
  source <- withr::local_tempfile(fileext = ".png")
  mixed <- withr::local_tempfile(fileext = ".png")
  png::writePNG(array(0.5, c(48, 64, 3)), source)
  for (dimensions in list(c(48, 80, 3), c(60, 64, 3))) {
    png::writePNG(array(0.5, dimensions), mixed)
    for (format in c("mp4", "webm", "gif")) {
      for (crop_type in c("frame", "camera")) {
        out <- withr::local_tempfile(fileext = paste0(".", format))
        rec <- new_recorder(out, format, 1, NULL, c(1, 0), FALSE, NULL)
        rec$files <- c(source, mixed, source)
        rec$times <- c(0, 0.01, 0.02)
        rec$vt_end <- 0.02
        if (crop_type == "frame") {
          rec$crop <- list(
            x = 0,
            y = 0,
            width = 32,
            height = 24,
            viewport_width = 64
          )
        } else {
          rec$camera <- list(list(start = 0, end = 0, box = c(0, 0, 32, 24)))
        }
        expect_identical(record_resample(rec)$files, source)
        expect_error(
          record_encode(rec),
          "Set the viewport size before",
          class = "paparazzi_error_record"
        )
        expect_false(file.exists(out))
      }
    }
  }
})

test_that("keep_frames keeps the captured PNGs", {
  page <- local_record_page()
  skip_if_no_av()

  out <- withr::local_tempfile(fileext = ".mp4")
  frames_dir <- paste0(tools::file_path_sans_ext(out), "_frames")
  page |> pz_record(out, pz_wait(page, 0.3), fps = 10, keep_frames = TRUE)
  expect_true(dir.exists(frames_dir))
  expect_gte(length(list.files(frames_dir, pattern = "[.]png$")), 1)
  unlink(frames_dir, recursive = TRUE)

  out2 <- withr::local_tempfile(fileext = ".mp4")
  frames_dir2 <- paste0(tools::file_path_sans_ext(out2), "_frames")
  page |> pz_record(out2, pz_wait(page, 0.2), fps = 10)
  expect_false(dir.exists(frames_dir2))
})

test_that("screencast records real Chrome PNG events and acknowledges later frames", {
  page <- local_record_page()
  skip_if_no_av()

  out <- withr::local_tempfile(fileext = ".mp4")
  frames_dir <- paste0(tools::file_path_sans_ext(out), "_frames")
  withr::defer(unlink(frames_dir, recursive = TRUE))
  expect_invisible(pz_record_start(
    page,
    out,
    method = "screencast",
    fps = 10,
    hold = c(0, 0),
    keep_frames = TRUE
  ))
  defer_record_stop(page)
  rec <- page_recorder(page)
  pz_wait(page, 0.3)
  before <- length(rec$files)
  expect_gte(before, 1L)
  # A fresh paint must arrive even after the initial event has been acked.
  pz_js(page, "document.getElementById('box').style.background = 'red'")
  pz_poll(
    function() length(rec$files) > before,
    timeout = page$page$default_timeout,
    loop = page$page$child_loop,
    what = "a screencast frame after the paint"
  )
  expect_gt(length(rec$files), before)
  expect_equal(rec$ticks, 0L) # events, not the poll capture chain
  expect_equal(rec$n_errors, 0L)
  page |> pz_record_stop()

  expect_true(file.exists(out))
  expect_gte(recorded_video_info(out)$frames, 1L)
  files <- list.files(frames_dir, pattern = "[.]png$", full.names = TRUE)
  expect_gte(length(files), 2L)
  for (file in files) {
    expect_identical(
      readBin(file, "raw", n = 8),
      as.raw(c(137, 80, 78, 71, 13, 10, 26, 10))
    )
  }
})

test_that("screencast holds the last frame on an idle page", {
  skip_if_no_av()
  html <- withr::local_tempfile(
    lines = '<!doctype html><div style="background:teal">Still</div>',
    fileext = ".html"
  )
  page <- local_page(html)
  out <- withr::local_tempfile(fileext = ".mp4")
  pz_record_start(page, out, method = "screencast", hold = c(0, 0))
  defer_record_stop(page)
  rec <- page_recorder(page)
  pz_poll(
    function() length(rec$files) >= 1L,
    timeout = page$page$default_timeout,
    loop = page$page$child_loop,
    what = "the first screencast frame"
  )
  before <- length(rec$files)
  first <- png::readPNG(tail(rec$files, 1))
  pz_wait(page, 0.4)
  # Chrome may re-send an unchanged frame (a late acknowledgement), so the
  # idle contract is content, not cadence: frames captured while the page
  # sits still repeat the same pixels, and only a handful arrive -- a
  # leaked capture chain would produce a steady stream.
  idle <- tail(rec$files, -before)
  expect_lte(length(idle), 2L)
  for (file in idle) {
    expect_identical(png::readPNG(file), first, label = basename(file))
  }
  pz_record_stop(page)
  expect_true(file.exists(out))
})

test_that("screencast immediate stop captures the final page state", {
  page <- local_page(
    record_fixture_file(),
    width = 640,
    height = 480,
    scale = 2
  )
  skip_if_no_av()
  testthat::skip_if_not_installed("png")

  out <- withr::local_tempfile(fileext = ".mp4")
  frames_dir <- paste0(tools::file_path_sans_ext(out), "_frames")
  withr::defer(unlink(frames_dir, recursive = TRUE))
  pz_record_start(
    page,
    out,
    method = "screencast",
    fps = 10,
    hold = c(0, 0),
    keep_frames = TRUE
  )
  defer_record_stop(page)
  pz_js(page, "document.getElementById('box').style.background = 'red'")
  pz_record_stop(page)

  files <- sort(list.files(frames_dir, pattern = "[.]png$", full.names = TRUE))
  if (!length(files)) {
    testthat::fail("the immediate stop captured no frames")
  } else {
    expect_equal(png_dimensions(tail(files, 1)), c(640L, 480L))
    img <- png::readPNG(tail(files, 1))
    expect_equal(
      unname(img[51, 91, 1:3]),
      c(1, 0, 0),
      tolerance = 0.05
    )
  }
  expect_true(file.exists(out))
})

test_that("screencast cuts paused paints and resumes event delivery", {
  page <- local_record_page()
  skip_if_no_av()

  out <- withr::local_tempfile(fileext = ".mp4")
  pz_record_start(
    page,
    out,
    method = "screencast",
    fps = 10,
    hold = c(0.2, 0.3)
  )
  defer_record_stop(page)
  rec <- page_recorder(page)
  pz_poll(
    function() length(rec$files) >= 2L,
    timeout = 5,
    loop = page$page$child_loop,
    what = "the ticker's screencast paint events"
  )
  expect_gte(length(rec$files), 2L)

  pz_record_pause(page)
  before <- length(rec$files)
  paused_vt <- rec_vt(rec)
  pz_wait(page, 0.4)
  expect_length(rec$files, before)
  expect_equal(rec_vt(rec), paused_vt, tolerance = 0)
  resume_started <- rec_now()
  pz_record_resume(page)
  expect_lte(rec_vt(rec) - paused_vt, rec_now() - resume_started + 0.002)
  pz_poll(
    function() length(rec$files) > before,
    timeout = 5,
    loop = page$page$child_loop,
    what = "a screencast frame after resuming"
  )
  expect_gt(length(rec$files), before)
  expect_equal(rec$n_errors, 0L)
  pz_record_hold(page, 0.2)
  pz_record_stop(page)
  expect_true(file.exists(out))
  expected <- record_resample(rec)$n_ticks / rec$fps
  expect_gte(recorded_video_info(out)$duration, expected - 1 / rec$fps - 0.002)
  expect_lte(recorded_video_info(out)$duration, expected + 1 / rec$fps + 0.002)
})

test_that("resume captures a paused change on an idle page", {
  skip_if_no_av()
  testthat::skip_if_not_installed("png")
  html <- withr::local_tempfile(
    lines = '<!doctype html><style>body{margin:0}#box{position:absolute;left:20px;top:20px;width:100px;height:60px;background:teal}</style><div id="box"></div>',
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
  pz_poll(
    function() length(rec$files) > 0,
    timeout = 3,
    loop = page$page$child_loop,
    what = "the first screencast frame"
  )

  pz_record_pause(page)
  before <- length(rec$files)
  pz_js(page, "document.getElementById('box').style.background = 'red'")
  pz_wait(page, 0.25)
  expect_length(rec$files, before)
  pz_record_resume(page)
  pz_poll(
    function() length(rec$files) > before && is.null(rec$pending),
    timeout = 1,
    loop = page$page$child_loop,
    what = "the resumed page state"
  )
  expect_equal(png_dimensions(tail(rec$files, 1)), c(640L, 480L))
  expect_equal(
    unname(png::readPNG(tail(rec$files, 1))[31, 31, 1:3]),
    c(1, 0, 0)
  )
  pz_record_stop(page)
})

test_that("a device change captures the new state after held paints", {
  skip_if_no_av()
  testthat::skip_if_not_installed("png")
  html <- withr::local_tempfile(
    lines = '<!doctype html><style>body{margin:0}#box{position:absolute;left:20px;top:20px;width:100px;height:60px;background:teal}</style><div id="box"></div>',
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
  pz_poll(
    function() length(rec$files) > 0,
    timeout = 3,
    loop = page$page$child_loop,
    what = "the first screencast frame"
  )

  before <- length(rec$files)
  record_device_change(page$page, {
    pz_device(page, width = 800, height = 600)
    pz_js(page, "document.getElementById('box').style.background = 'red'")
    pz_wait(page, 0.25)
    expect_length(rec$files, before)
  })
  pz_poll(
    function() length(rec$files) > before && is.null(rec$pending),
    timeout = 1,
    loop = page$page$child_loop,
    what = "the held page state"
  )
  expect_equal(png_dimensions(tail(rec$files, 1)), c(800L, 600L))
  expect_equal(
    unname(png::readPNG(tail(rec$files, 1))[31, 31, 1:3]),
    c(1, 0, 0)
  )
  expect_equal(pz_js(page, "window.innerWidth"), 800)
  before_error <- length(rec$files)
  expect_error(
    record_device_change(page$page, stop("failed override")),
    "failed override"
  )
  expect_false(rec$held)
  expect_length(rec$files, before_error)
  pz_record_stop(page)
})

test_that("screencast uses CSS-size frames and crops at their actual resolution", {
  page <- local_page(
    record_fixture_file(),
    width = 640,
    height = 480,
    scale = 2
  )
  skip_if_no_av()
  expect_equal(page_dpr(page), 2)

  capture <- function(method) {
    out <- withr::local_tempfile(fileext = ".mp4")
    frames_dir <- paste0(tools::file_path_sans_ext(out), "_frames")
    withr::defer(unlink(frames_dir, recursive = TRUE))
    pz_record_start(
      page,
      out,
      method = method,
      fps = 10,
      hold = c(0, 0),
      frame = pz_frame("#box"),
      keep_frames = TRUE
    )
    defer_record_stop(page)
    rec <- page_recorder(page)
    pz_poll(
      function() length(rec$files) >= 1L,
      timeout = page$page$default_timeout,
      loop = page$page$child_loop,
      what = "a frame to measure the crop scale"
    )
    # The PNG dimensions, not the page's DPR, determine the crop scale.
    event_files <- rec$files
    event_sizes <- lapply(event_files, png_dimensions)
    pz_record_stop(page)
    files <- sort(list.files(
      frames_dir,
      pattern = "[.]png$",
      full.names = TRUE
    ))
    list(
      event_sizes = event_sizes,
      final_size = png_dimensions(tail(files, 1)),
      video = recorded_video_info(out)
    )
  }

  poll <- capture("poll")
  screencast <- capture("screencast")
  expect_true(all(vapply(
    poll$event_sizes,
    identical,
    logical(1),
    c(1280L, 960L)
  )))
  expect_true(all(vapply(
    screencast$event_sizes,
    identical,
    logical(1),
    c(640L, 480L)
  )))
  expect_equal(poll$final_size, c(1280L, 960L))
  expect_equal(screencast$final_size, c(640L, 480L))
  expect_equal(c(poll$video$width, poll$video$height), c(200, 120))
  expect_equal(c(screencast$video$width, screencast$video$height), c(100, 60))
})

test_that("screencast encodes framed, scaled webm and gif outputs", {
  page <- local_record_page()
  skip_if_no_av()
  skip_if_no_gifski()
  testthat::skip_if_not_installed("png")

  for (ext in c("webm", "gif")) {
    out <- withr::local_tempfile(fileext = paste0(".", ext))
    pz_record_start(
      page,
      out,
      method = "screencast",
      fps = 10,
      hold = c(0, 0),
      frame = pz_frame("#box"),
      scale = 0.5
    )
    defer_record_stop(page)
    pz_wait(page, 0.3)
    pz_record_stop(page)
    info <- recorded_video_info(out)
    expect_true(file.exists(out))
    expect_equal(c(info$width, info$height), c(50, 30))
    if (ext == "webm") {
      expect_equal(info$framerate, 10)
    } else {
      expect_equal(info$codec, "gif")
      expect_gt(info$duration, 0)
    }
  }
})

test_that("screencast stops cleanly and can restart on the same page", {
  page <- local_record_page()
  skip_if_no_av()

  first <- withr::local_tempfile(fileext = ".mp4")
  pz_record_start(page, first, method = "screencast", hold = c(0, 0))
  defer_record_stop(page)
  old <- page_recorder(page)
  pz_wait(page, 0.2)
  pz_record_stop(page)
  expect_null(old$deregister_screencast)
  expect_false(dir.exists(old$frames_dir))
  expect_equal(pz_js(page, "document.readyState"), "complete")

  second <- withr::local_tempfile(fileext = ".mp4")
  pz_record_start(page, second, method = "screencast", hold = c(0, 0))
  defer_record_stop(page)
  current <- page_recorder(page)
  before <- length(current$files)
  record_screencast_frame(page$page, old, list(sessionId = 1L))
  expect_length(current$files, before)
  pz_poll(
    function() length(current$files) >= 1L,
    timeout = page$page$default_timeout,
    loop = page$page$child_loop,
    what = "a frame from the restarted screencast"
  )
  pz_record_stop(page)
  expect_true(file.exists(second))
  expect_equal(current$n_errors, 0L)
})

test_that("closing a screencast page releases its listener and frames", {
  page <- local_record_page()
  skip_if_no_av()
  out <- withr::local_tempfile(fileext = ".mp4")
  pz_record_start(page, out, method = "screencast")
  rec <- page_recorder(page)
  pz_close(page)

  expect_null(page_recorder(page))
  expect_false(rec$active)
  expect_null(rec$deregister_screencast)
  expect_false(dir.exists(rec$frames_dir))
})

test_that("screencast follows a viewport resize without losing recording", {
  page <- local_page(
    record_fixture_file(),
    width = 640,
    height = 480,
    scale = 2
  )
  skip_if_no_av()

  out <- withr::local_tempfile(fileext = ".mp4")
  pz_record_start(
    page,
    out,
    method = "screencast",
    fps = 10,
    hold = c(0, 0),
    keep_frames = TRUE
  )
  rec <- page_recorder(page)
  withr::defer(unlink(rec$frames_dir, recursive = TRUE))
  defer_record_stop(page)
  pz_poll(
    function() length(rec$files) > 0,
    timeout = 5,
    loop = page$page$child_loop,
    what = "the initial screencast frame"
  )
  expect_equal(png_dimensions(rec$files[[1]]), c(640L, 480L))

  pz_device(page, width = 800, height = 600)
  pz_poll(
    function() {
      length(rec$files) > 1 &&
        identical(png_dimensions(tail(rec$files, 1)), c(800L, 600L))
    },
    timeout = 5,
    loop = page$page$child_loop,
    what = "a screencast frame at the resized viewport"
  )
  pz_record_stop(page)
  expect_equal(png_dimensions(tail(rec$files, 1)), c(800L, 600L))
  expect_true(file.exists(out))
})

test_that("a failed screencast start leaves the page free to record", {
  page <- local_record_page()
  skip_if_no_av()
  session <- page$page$session
  domain <- session$Page
  started <- NULL
  wrapped <- domain
  wrapped$startScreencast <- function(...) {
    started <<- page_recorder(page)
    stop("start failed")
  }
  session$Page <- wrapped
  withr::defer(session$Page <- domain)

  out <- withr::local_tempfile(fileext = ".mp4")
  expect_error(
    pz_record_start(page, out, method = "screencast"),
    "start failed"
  )
  expect_null(page_recorder(page))
  expect_null(started$deregister_screencast)
  expect_false(dir.exists(started$frames_dir))
  session$Page <- domain
  pz_record_start(page, out, hold = c(0, 0))
  defer_record_stop(page)
  pz_record_stop(page)
  expect_true(file.exists(out))
})

test_that("recording input and lifecycle errors are classed", {
  page <- local_record_page()
  skip_if_no_av()

  expect_error(pz_record_start(page), "path")
  expect_error(pz_record_start(page, format = "gif"), "path")
  expect_error(
    pz_record_start(
      page,
      withr::local_tempfile(fileext = ".mp4"),
      format = "gif"
    ),
    class = "paparazzi_error_input"
  )
  expect_error(
    pz_record_start(page, withr::local_tempfile(fileext = ".mov")),
    class = "paparazzi_error_input"
  )
  expect_error(
    pz_record_start(page, withr::local_tempfile(fileext = ".mp4"), hold = 1),
    class = "paparazzi_error_input"
  )
  expect_error(pz_record_stop(page), class = "paparazzi_error_record")
  expect_error(pz_record_pause(page), class = "paparazzi_error_record")
  expect_error(pz_record_resume(page), class = "paparazzi_error_record")

  out <- withr::local_tempfile(fileext = ".mp4")
  page |> pz_record_start(out, fps = 10, hold = c(0, 0))
  expect_error(
    pz_record_start(page, withr::local_tempfile(fileext = ".mp4")),
    class = "paparazzi_error_record"
  )
  pz_wait(page, 0.2)
  page |> pz_record_stop()
  expect_error(pz_record_stop(page), class = "paparazzi_error_record")
})

test_that("NULL and omitted paths both preview start and block recordings", {
  page <- local_record_page()
  skip_if_no_av()
  rlang::local_interactive()
  chain <- pz_record_start(page, fps = 5, hold = c(0, 0))
  defer_record_stop(page)
  pz_wait(chain, 0.1)
  omitted <- pz_record_stop(chain)
  chain <- pz_record_start(page, path = NULL, fps = 5, hold = c(0, 0))
  pz_wait(chain, 0.1)
  explicit <- pz_record_stop(chain)
  block_omitted <- pz_record(
    page,
    code = pz_wait(page, 0.1),
    fps = 5,
    hold = c(0, 0)
  )
  block_explicit <- pz_record(
    page,
    path = NULL,
    code = pz_wait(page, 0.1),
    fps = 5,
    hold = c(0, 0)
  )
  previews <- list(omitted, explicit, block_omitted, block_explicit)
  withr::defer(unlink(vapply(previews, unclass, character(1))))
  for (preview in previews) {
    expect_s3_class(preview, "paparazzi_preview")
    expect_true(file.exists(preview))
    expect_equal(tools::file_ext(preview), "mp4")
  }
})

test_that("pz_record_start promotes a bare locator frame", {
  skip_if_no_av()
  page <- local_record_page()
  out <- withr::local_tempfile(fileext = ".mp4")

  pz_record_start(page, out, hold = c(0, 0), frame = "#box")
  defer_record_stop(page)
  frame <- page_recorder(page)$frame
  expect_s3_class(frame, "paparazzi_frame")
  expect_identical(frame$target[[1]]$css, "#box")
  expect_identical(frame$pad, rep(0, 4))
  pz_record_stop(page)
})

test_that("an inherited annotated target box downgrades for the home frame", {
  skip_if_no_av()
  page <- local_record_page()
  pz_stage_frame(page, "#box", target_box = "annotated")
  out <- withr::local_tempfile(fileext = ".mp4")

  # An explicit spec without target_box inherits the staged annotated
  # box, which silently measures element boxes for the home frame.
  expect_no_error(
    pz_record_start(page, out, hold = c(0, 0), frame = pz_frame(pad = 8))
  )
  defer_record_stop(page)
  frame <- page_recorder(page)$frame
  expect_identical(frame$target_box, "element")
  expect_identical(frame$pad, rep(8, 4))
  expect_identical(frame$target[[1]]$css, "#box")
  pz_record_stop(page)
})
