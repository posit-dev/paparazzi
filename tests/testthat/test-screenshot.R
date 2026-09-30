test_that("pz_screenshot captures the viewport from the root context", {
  page <- local_screenshot_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)
  # pz_js() turns JS arrays into R lists; flatten for the arithmetic.
  inner <- unlist(pz_js(page, "[window.innerWidth, window.innerHeight]"))

  pz_screenshot(page, path)
  expect_identical(png_dimensions(path), as.integer(round(inner * dpr)))
})

test_that("pz_screenshot captures a single element's bounding box", {
  page <- local_screenshot_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)

  # #shot-a: left 40, top 30, 100x60
  pz_screenshot(page, path, frame = "#shot-a")
  expect_identical(png_dimensions(path), as.integer(round(c(100, 60) * dpr)))
})

test_that("pz_screenshot captures the union of a list of targets", {
  page <- local_screenshot_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)

  # #shot-b sits right of AND below #shot-a, so the union is
  # x=40 y=30 w=300 h=170: the prior-art bug (mutating x before
  # computing width) would report the wrong width here.
  pz_screenshot(page, path, frame = list("#shot-a", "#shot-b"))
  expect_identical(png_dimensions(path), as.integer(round(c(300, 170) * dpr)))
})

test_that("pz_screenshot unions every element a multi-match selector finds", {
  page <- local_screenshot_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)

  # .multi matches #multi-1 (40, 260, 80x50) and #multi-2
  # (180, 300, 80x50); the union is x=40 y=260 w=220 h=90. No strict
  # argument: several matches are a union, not an error.
  pz_screenshot(page, path, frame = ".multi")
  expect_identical(png_dimensions(path), as.integer(round(c(220, 90) * dpr)))
})

test_that("pz_screenshot accepts a mixed list of pz_loc() specs and strings", {
  page <- local_screenshot_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)

  pz_screenshot(page, path, frame = list(pz_loc("#shot-a"), "#shot-b"))
  expect_identical(png_dimensions(path), as.integer(round(c(300, 170) * dpr)))
})

test_that("pz_screenshot captures a below-fold element without scrolling", {
  page <- local_screenshot_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)

  # #below-fold: left 60, top 2400, 200x100 -- far beyond the default
  # viewport, so this exercises the captureBeyondViewport path. The
  # capture must not scroll the page as a side effect.
  pz_screenshot(page, path, frame = "#below-fold")
  expect_identical(png_dimensions(path), as.integer(round(c(200, 100) * dpr)))
  expect_equal(pz_js(page, "window.scrollY"), 0)
})

test_that("frame = FALSE captures without framing, like frame = NULL", {
  page <- local_screenshot_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)
  inner <- unlist(pz_js(page, "[window.innerWidth, window.innerHeight]"))

  pz_screenshot(page, path, frame = FALSE)
  expect_identical(png_dimensions(path), as.integer(round(inner * dpr)))
})

test_that("frame = TRUE is not supported yet", {
  page <- local_screenshot_page()
  path <- withr::local_tempfile(fileext = ".png")

  expect_error(
    pz_screenshot(page, path, frame = TRUE),
    class = "paparazzi_error_unsupported"
  )
  # Nothing was written before the error.
  expect_false(file.exists(path))
})

test_that("pz_screenshot clamps the viewport clip origin on negative RTL scroll", {
  page <- local_screenshot_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)

  # Go RTL and widen the body so horizontal scroll exists; scrolling
  # left of the origin makes window.scrollX negative, which CDP would
  # reject as a clip origin.
  pz_js(page, "document.documentElement.dir = 'rtl'")
  pz_js(page, "document.body.style.width = '3000px'")
  pz_js(page, "window.scrollTo(-100, 0)")
  skip_if(
    pz_js(page, "window.scrollX") >= 0,
    "browser won't scroll negative in RTL"
  )

  expect_no_error(pz_screenshot(page, path))
  inner <- unlist(pz_js(page, "[window.innerWidth, window.innerHeight]"))
  expect_identical(png_dimensions(path), as.integer(round(inner * dpr)))
})

test_that("pz_screenshot captures the right pixels", {
  page <- local_screenshot_page()
  dpr <- page_dpr(page)

  # #shot-a: 100x60 red at (40, 30); center of the capture.
  path_a <- withr::local_tempfile(fileext = ".png")
  pz_screenshot(page, path_a, frame = "#shot-a")
  expect_png_pixel(page, path_a, 50, 30, c(255, 0, 0), dpr = dpr)

  # Union of #shot-a + #shot-b: origin (40, 30), so offsets are relative
  # to the union box.
  path_u <- withr::local_tempfile(fileext = ".png")
  pz_screenshot(page, path_u, frame = list("#shot-a", "#shot-b"))
  expect_png_pixel(page, path_u, 10, 15, c(255, 0, 0), dpr = dpr)
  # CSS "green" is #008000, not (0, 255, 0).
  expect_png_pixel(page, path_u, 230, 130, c(0, 128, 0), dpr = dpr)
  # Inside the union box but over neither element: the page background.
  expect_png_pixel(page, path_u, 110, 5, c(255, 255, 255), dpr = dpr)

  # #below-fold: 200x100 purple at (60, 2400); center of the capture.
  path_f <- withr::local_tempfile(fileext = ".png")
  pz_screenshot(page, path_f, frame = "#below-fold")
  expect_png_pixel(page, path_f, 100, 50, c(128, 0, 128), dpr = dpr)
})

test_that("pz_screenshot returns its context invisibly", {
  page <- local_screenshot_page()
  path <- withr::local_tempfile(fileext = ".png")

  expect_invisible(pz_screenshot(page, path))
  expect_identical(withVisible(pz_screenshot(page, path))$value, page)
})

test_that("pathless screenshots are numbered knitr figures", {
  skip_if_not_installed("knitr")
  page <- local_screenshot_page()
  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  text <- paste(
    '```{r fig-shot, echo=FALSE, fig.path="figures/", fig.cap="The page", fig.alt="Red box", out.width="50%"}',
    'page |> pz_screenshot(frame = "#shot-a")',
    'page |> pz_screenshot(path = NULL, frame = "#shot-b")',
    '```',
    sep = "\n"
  )

  markdown <- knitr::knit(text = text, envir = environment(), quiet = TRUE)
  expect_match(markdown, "figures/fig-shot-1.png", fixed = TRUE)
  expect_match(markdown, "figures/fig-shot-2.png", fixed = TRUE)
  expect_match(markdown, 'alt="Red box"', fixed = TRUE)
  expect_match(markdown, 'width="50%"', fixed = TRUE)
  expect_match(markdown, "The page", fixed = TRUE)
  expect_true(file.exists("figures/fig-shot-1.png"))
  expect_true(file.exists("figures/fig-shot-2.png"))
  expect_identical(
    png_dimensions("figures/fig-shot-1.png"),
    as.integer(round(c(100, 60) * page_dpr(page)))
  )

  for (retina in c(1, 2)) {
    text <- paste(
      sprintf(
        '```{r fig-css, echo=FALSE, fig.path="figures/", fig.retina=%d}',
        retina
      ),
      'page |> pz_screenshot(frame = "#shot-a")',
      '```',
      sep = "\n"
    )
    markdown <- knitr::knit(text = text, envir = environment(), quiet = TRUE)
    expect_match(markdown, 'width="100"', fixed = TRUE)
  }
})

test_that("a pathless screenshot resolves in rendered R Markdown", {
  skip_if_not_installed("rmarkdown")
  page <- local_screenshot_page()
  dir <- withr::local_tempdir()
  input <- file.path(dir, "live-shot.Rmd")
  writeLines(
    c(
      "---",
      "output:",
      "  html_document:",
      "    self_contained: false",
      "---",
      "",
      '```{r fig-live-shot, echo=FALSE, fig.cap="The red box", fig.alt="Red box"}',
      'page |> pz_screenshot(frame = "#shot-a")',
      '```'
    ),
    input
  )

  output <- getExportedValue("rmarkdown", "render")(
    input,
    envir = environment(),
    quiet = TRUE
  )
  html <- paste(readLines(output, warn = FALSE), collapse = "\n")
  image_src <- function(document) {
    match <- regmatches(
      document,
      regexec('src="([^"]+)"[^>]*alt="Red box"', document)
    )[[1]]
    if (length(match) != 2L) {
      return(NULL)
    }
    match[[2]]
  }
  src <- image_src(html)
  expect_false(is.null(src))
  expect_match(src, "fig-live-shot-1.png", fixed = TRUE)
  expect_true(file.exists(file.path(dirname(output), src)))
  expect_identical(
    png_dimensions(file.path(dirname(output), src)),
    as.integer(round(c(100, 60) * page_dpr(page)))
  )
  expect_match(html, "The red box", fixed = TRUE)
  expect_match(html, 'alt="Red box"', fixed = TRUE)

  # A dangling final HTML image link must fail the same resolution check.
  broken <- sub(src, "missing-image.png", html, fixed = TRUE)
  expect_identical(image_src(broken), "missing-image.png")
  expect_false(file.exists(file.path(dirname(output), image_src(broken))))
})

test_that("a Quarto screenshot figure resolves with its cross-reference", {
  skip_if(Sys.which("quarto") == "", "Quarto not available")
  skip_if_not_installed("pkgload")
  skip_if_no_chrome()
  dir <- withr::local_tempdir()
  input <- file.path(dir, "live-shot.qmd")
  package_root <- normalizePath(test_path("..", ".."))
  fixture <- normalizePath(screenshot_fixture_file())
  writeLines(
    c(
      "---",
      "format: html",
      "---",
      "",
      "See @fig-live-shot.",
      "",
      "```{r}",
      "#| echo: false",
      quarto_load_package(package_root),
      sprintf("page <- pz_open(%s)", deparse(fixture)),
      "```",
      "",
      "```{r}",
      "#| label: fig-live-shot",
      "#| echo: false",
      "#| fig-cap: The red box",
      "#| fig-alt: Red box",
      'page |> pz_screenshot(frame = "#shot-a")',
      "```",
      "",
      "```{r}",
      "#| echo: false",
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
  output <- file.path(dir, "live-shot.html")
  html <- paste(readLines(output, warn = FALSE), collapse = "\n")
  src <- regmatches(
    html,
    regexec('src="([^"]*fig-live-shot-1\\.png)"', html)
  )[[1]]
  expect_length(src, 2L)
  expect_true(file.exists(file.path(dir, src[[2]])))
  expect_match(html, 'id="fig-live-shot"', fixed = TRUE)
  expect_match(html, 'href="#fig-live-shot"', fixed = TRUE)
  expect_match(html, "The red box", fixed = TRUE)
  expect_match(html, 'alt="Red box"', fixed = TRUE)
})

test_that("explicit paths stay chainable while knitting", {
  skip_if_not_installed("knitr")
  page <- local_screenshot_page()
  dir <- withr::local_tempdir()
  withr::local_dir(dir)
  text <- paste(
    '```{r fig-manual, echo=FALSE}',
    'page |> pz_screenshot("manual.png", frame = "#shot-a") |> pz_act_click("#shot-a")',
    '```',
    sep = "\n"
  )

  markdown <- knitr::knit(text = text, envir = environment(), quiet = TRUE)
  expect_true(file.exists("manual.png"))
  expect_false(grepl("manual.png", markdown, fixed = TRUE))
})

test_that("pathless screenshots preview interactively without magick", {
  page <- local_screenshot_page()
  rlang::local_interactive()
  shown <- NULL
  withr::local_options(viewer = function(path) shown <<- path)

  preview <- pz_screenshot(page, frame = "#shot-a")
  withr::defer(unlink(unclass(preview)))
  expect_s3_class(preview, "paparazzi_preview")
  expect_true(file.exists(unclass(preview)))
  expect_identical(shown, NULL)
  expect_invisible(print(preview))
  expect_identical(shown, unclass(preview))
})

test_that("a missing screenshot path still errors in noninteractive scripts", {
  page <- local_screenshot_page()
  rlang::local_interactive(FALSE)
  expect_error(pz_screenshot(page), "path")
  expect_error(pz_screenshot(page, path = NULL), "path")
})

test_that("pz_screenshot validates its inputs", {
  page <- local_screenshot_page()
  path <- withr::local_tempfile(fileext = ".png")

  expect_error(
    pz_screenshot(page, path, frame = list()),
    class = "paparazzi_error_target"
  )
  expect_error(
    pz_screenshot(page, path, frame = 42),
    class = "paparazzi_error_unsupported"
  )
  expect_error(pz_screenshot(page, path, extra = 1), "empty")
  expect_error(pz_screenshot(page, 42), class = "rlang_error")
})

test_that("pz_screenshot clips to the current scope's pinned set", {
  page <- local_screenshot_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)

  ctx <- pz_find(page, "#shot-a")
  expect_invisible(pz_screenshot(ctx, path))
  expect_identical(png_dimensions(path), as.integer(round(c(100, 60) * dpr)))
})

test_that("pz_screenshot raises on a detached scope", {
  page <- local_screenshot_page()
  path <- withr::local_tempfile(fileext = ".png")

  ctx <- pz_find(page, "#shot-b")
  pz_js(page, "document.getElementById('shot-b').remove()")
  expect_error(pz_screenshot(ctx, path), class = "paparazzi_error_detached")
})

test_that("NULL and omitted screenshot paths both produce implicit output", {
  page <- local_screenshot_page()
  rlang::local_interactive()
  omitted <- pz_screenshot(page, frame = "#shot-a")
  explicit <- pz_screenshot(page, path = NULL, frame = "#shot-a")
  withr::defer(unlink(c(unclass(omitted), unclass(explicit))))
  expect_s3_class(omitted, "paparazzi_preview")
  expect_s3_class(explicit, "paparazzi_preview")
  expect_identical(
    readBin(omitted, "raw", file.info(omitted)$size),
    readBin(explicit, "raw", file.info(explicit)$size)
  )
})

test_that("frame promotes a bare locator to a frame spec", {
  page <- local_screenshot_page()
  path <- withr::local_tempfile(fileext = ".png")
  dpr <- page_dpr(page)

  # #shot-a: left 40, top 30, 100x60
  pz_screenshot(page, path, frame = "#shot-a")
  expect_identical(png_dimensions(path), as.integer(round(c(100, 60) * dpr)))

  # A list promotes to the union frame
  pz_screenshot(page, path, frame = list("#shot-a", "#shot-b"))
  expect_identical(png_dimensions(path), as.integer(round(c(300, 170) * dpr)))
})

test_that("the removed target argument errors", {
  page <- local_screenshot_page()
  path <- withr::local_tempfile(fileext = ".png")

  expect_error(pz_screenshot(page, path, target = "#shot-a"), "empty")
  expect_false(file.exists(path))
})

test_that("pathless screenshots produce previews during pkgdown examples", {
  skip_if_not_installed("pkgdown")
  rlang::local_interactive(FALSE)
  local_mocked_bindings(in_pkgdown = function() TRUE, .package = "pkgdown")
  page <- local_screenshot_page()
  preview <- pz_screenshot(page, frame = "#shot-a")
  withr::defer(unlink(unclass(preview)))

  expect_s3_class(preview, "paparazzi_preview")
  expect_true(file.exists(unclass(preview)))
  expect_true(startsWith(unclass(preview), tempdir()))
  expect_identical(
    png_dimensions(unclass(preview)),
    as.integer(c(100, 60) * page_dpr(page))
  )
})

test_that("pkgdown previews embed media and respect visibility", {
  skip_if_not_installed("pkgdown")
  skip_if_not_installed("htmltools")
  for (ext in c("png", "gif", "mp4", "webm")) {
    path <- withr::local_tempfile(fileext = paste0(".", ext))
    bytes <- as.raw(c(0, 1, 2, 255))
    writeBin(bytes, path)
    preview <- structure(path, class = "paparazzi_preview")
    tag <- pkgdown::pkgdown_print(preview)
    video <- ext %in% c("mp4", "webm")

    expect_s3_class(tag, "shiny.tag")
    expect_identical(tag$name, if (video) "video" else "img")
    mime <- paste0(if (video) "video/" else "image/", ext)
    expect_identical(
      tag$attribs$src,
      paste0("data:", mime, ";base64,AAEC/w==")
    )
    if (!video) {
      expect_true(nzchar(tag$attribs$alt))
    }
    expect_invisible(pkgdown::pkgdown_print(preview, visible = FALSE))
    expect_null(pkgdown::pkgdown_print(preview, visible = FALSE))
  }

  missing <- structure("no-such-preview.png", class = "paparazzi_preview")
  expect_null(pkgdown::pkgdown_print(missing, visible = FALSE))
  expect_error(pkgdown::pkgdown_print(missing), "no longer exists")

  jpeg <- withr::local_tempfile(fileext = ".jpg")
  writeBin(as.raw(0:3), jpeg)
  expect_error(
    pkgdown::pkgdown_print(structure(jpeg, class = "paparazzi_preview")),
    "Can't embed"
  )
})

test_that("pkgdown media data URIs do not wrap long base64 payloads", {
  skip_if_not_installed("pkgdown")
  skip_if_not_installed("htmltools")
  path <- withr::local_tempfile(fileext = ".png")
  bytes <- as.raw(0:255)
  writeBin(bytes, path)
  tag <- pkgdown::pkgdown_print(structure(path, class = "paparazzi_preview"))

  expect_false(grepl("[\r\n]", tag$attribs$src))
  expect_false(grepl("%0A", tag$attribs$src, fixed = TRUE))
  expect_false(grepl("%0A", htmltools::renderTags(tag)$html, fixed = TRUE))
  expect_identical(
    jsonlite::base64_dec(sub("^data:image/png;base64,", "", tag$attribs$src)),
    bytes
  )
})
