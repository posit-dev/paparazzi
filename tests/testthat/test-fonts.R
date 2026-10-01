silkscreen_fixture <- function() {
  # Silkscreen 400 (latin subset), OFL 1.1 -- see silkscreen-OFL.txt.
  test_path("fixtures", "fonts", "silkscreen-400.woff2")
}

bungee_fixture <- function() {
  # Bungee 400 (latin subset), OFL 1.1 -- see bungee-OFL.txt. Much wider
  # glyphs than Silkscreen; aliased under another family in some tests.
  test_path("fixtures", "fonts", "bungee-400.woff2")
}

local_corrupt_font <- function(.env = parent.frame()) {
  path <- withr::local_tempfile(.local_envir = .env, fileext = ".woff2")
  writeBin(charToRaw("not a real font"), path)
  path
}

page_font_families <- function(page) {
  unlist(pz_js(
    page,
    "[...document.fonts].map(f => f.family + '|' + f.weight + '|' + f.status)"
  ))
}

test_that("font constructors build classed font objects", {
  google <- pz_font_google("Open Sans", weight = 700)
  expect_s3_class(google, "paparazzi_font_google")
  expect_s3_class(google, "paparazzi_font")
  expect_equal(google$family, "Open Sans")
  expect_equal(google$weight, 700L)
  expect_equal(google$style, "normal")
  expect_match(google$url, "fonts.googleapis.com/css2", fixed = TRUE)
  expect_match(google$url, "family=Open+Sans", fixed = TRUE)
  expect_match(google$url, "wght@700", fixed = TRUE)

  italic <- pz_font_google("Open Sans", style = "italic")
  expect_match(italic$url, "ital,wght@1,400", fixed = TRUE)

  bunny <- pz_font_bunny("Open Sans", style = "italic")
  expect_s3_class(bunny, "paparazzi_font_bunny")
  expect_match(bunny$url, "fonts.bunny.net/css", fixed = TRUE)
  expect_match(bunny$url, "family=open-sans:400i", fixed = TRUE)

  file <- pz_font_file("Silkscreen", silkscreen_fixture())
  expect_s3_class(file, "paparazzi_font_file")
  expect_equal(file$format, "woff2")
  expect_true(nchar(file$data) > 0)
})

test_that("font constructors validate their inputs", {
  expect_error(pz_font_google(""), "empty")
  expect_error(pz_font_google(NA_character_), "NA")
  expect_error(pz_font_google("Inter", weight = 0), "weight")
  expect_error(pz_font_google("Inter", weight = 1001), "weight")
  expect_error(pz_font_google("Inter", weight = 400.5), "whole")
  expect_error(pz_font_google("Inter", style = "oblique"), "normal")
  expect_error(pz_font_file("X", tempfile()), "does not exist")
  otb <- withr::local_tempfile(fileext = ".otb")
  file.create(otb)
  expect_error(pz_font_file("X", otb), "woff2")
  # Quotes are stripped so the resolved CSS string stays intact
  expect_equal(pz_font_google('Weird "Family"')$family, "Weird Family")
})

test_that("font objects have a compact print method", {
  expect_output(
    print(pz_font_google("Inter", weight = 700)),
    "<paparazzi font> Inter (google, weight 700, normal)",
    fixed = TRUE
  )
})

test_that("font printing preserves literal text, newlines, and invisible return", {
  font <- pz_font_google("Braced {Font} {.arg x} 100% $value\\path\nline")
  output <- withr::local_tempfile()
  result <- withr::with_output_sink(output, withVisible(print(font)))

  expect_identical(
    readChar(output, file.info(output)$size, useBytes = TRUE),
    "<paparazzi font> Braced {Font} {.arg x} 100% $value\\path\nline (google, weight 400, normal)\n"
  )
  expect_identical(result, list(value = font, visible = FALSE))
})

test_that("pz_stage_fonts requires font objects", {
  page <- local_page()
  expect_error(pz_stage_fonts(page, "Silkscreen"), "pz_font_google")
  expect_error(pz_stage_fonts(page, list()), "pz_font_google")
  expect_error(
    pz_stage_fonts(
      page,
      pz_font_file("Silkscreen", silkscreen_fixture()),
      on_error = "cry"
    ),
    "stop"
  )
})

test_that("pz_stage_fonts stages a file font into document.fonts", {
  page <- local_page()
  font <- pz_font_file("Silkscreen", silkscreen_fixture())
  expect_invisible(pz_stage_fonts(page, font))
  expect_identical(pz_stage_fonts(page), page)

  staged <- page_fonts(page)
  expect_named(staged, "Silkscreen")
  expect_named(staged$Silkscreen, "400/normal")
  expect_identical(staged$Silkscreen[["400/normal"]]$family, "Silkscreen")

  expect_in("Silkscreen|400|loaded", page_font_families(page))
})

test_that("repeated staging adds faces and replaces by family, weight and style", {
  page <- local_page()
  pz_stage_fonts(page, pz_font_file("Silkscreen", silkscreen_fixture()))
  pz_stage_fonts(
    page,
    pz_font_file("Silkscreen", silkscreen_fixture(), weight = 700)
  )
  pz_stage_fonts(page, pz_font_file("Other", silkscreen_fixture()))
  staged <- page_fonts(page)
  expect_named(staged, c("Silkscreen", "Other"))
  expect_named(staged$Silkscreen, c("400/normal", "700/normal"))

  # Same family, weight and style: the face is replaced, not duplicated
  pz_stage_fonts(page, pz_font_file("Silkscreen", silkscreen_fixture()))
  expect_length(page_fonts(page)$Silkscreen, 2)
})

test_that("on_error routes load failures", {
  page <- local_page()
  corrupt <- pz_font_file("Corrupt", local_corrupt_font())

  expect_error(
    pz_stage_fonts(page, corrupt, on_error = "stop"),
    "Failed to load 1 font face"
  )
  expect_null(page_fonts(page))

  expect_warning(
    pz_stage_fonts(page, corrupt, on_error = "warn"),
    "Failed to load 1 font face"
  )
  expect_null(page_fonts(page))

  expect_no_warning(pz_stage_fonts(page, corrupt, on_error = "ignore"))
  expect_null(page_fonts(page))

  # The option sets the default
  withr::local_options(paparazzi.stage_fonts.on_error = "warn")
  expect_warning(
    pz_stage_fonts(page, corrupt),
    "Failed to load 1 font face"
  )
})

test_that("on_error = \"warn\" stages the faces that loaded", {
  page <- local_page()
  good <- pz_font_file("Silkscreen", silkscreen_fixture())
  bad <- pz_font_file("Corrupt", local_corrupt_font())
  expect_warning(pz_stage_fonts(page, good, bad, on_error = "warn"))
  expect_named(page_fonts(page), "Silkscreen")
  expect_in("Silkscreen|400|loaded", page_font_families(page))
})

test_that("an unstaged font object in font_family errors with a hint", {
  page <- local_page()
  font <- pz_font_file("Silkscreen", silkscreen_fixture())
  expect_error(
    pz_annotate(page, "h1", label = "Hi", font_family = font),
    "pz_stage_fonts"
  )
  expect_error(
    pz_stage_annotate(page, font_family = font),
    "pz_stage_fonts"
  )
  expect_error(
    pz_annotate_caption(page, "Hi", font_family = font),
    "pz_stage_fonts"
  )
})

test_that("a staged font object resolves to its quoted family with fallback", {
  page <- local_page()
  font <- pz_font_file("Silkscreen", silkscreen_fixture())
  pz_stage_fonts(page, font)

  pz_stage_annotate(page, font_family = font)
  expect_equal(
    page_stage(page)$annotate_font_family,
    '"Silkscreen", sans-serif'
  )

  pz_annotate(page, "h1", label = "Hi")
  style <- pz_js(
    page,
    "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotation span').style.fontFamily"
  )
  # The browser drops unneeded quotes when echoing the resolved value
  expect_equal(style, "Silkscreen, sans-serif")
})

test_that("badge text width differs from the sans-serif fallback", {
  page <- local_page()
  pz_stage_fonts(page, pz_font_file("Silkscreen", silkscreen_fixture()))
  badge_width <- function() {
    pz_js(
      page,
      "document.querySelector('#paparazzi-overlay-root').shadowRoot.querySelector('.pz-annotation span').offsetWidth"
    )
  }
  pz_annotate(page, "h1", label = "Width probe", font_family = "sans-serif")
  sans <- badge_width()
  pz_annotate_clear(page)
  pz_annotate(
    page,
    "h1",
    label = "Width probe",
    font_family = '"Silkscreen", sans-serif'
  )
  silkscreen <- badge_width()
  expect_gt(abs(silkscreen - sans), 0)
})

test_that("staged fonts are re-added lazily after navigation", {
  page <- local_page(nav_fixture_url("a"))
  pz_stage_fonts(page, pz_font_file("Silkscreen", silkscreen_fixture()))
  pz_nav_goto(page, nav_fixture_url("b"))

  # The new document starts without the staged faces
  expect_false(any(grepl("Silkscreen", page_font_families(page))))

  # The first annotation in the new document re-adds and awaits them
  pz_annotate(page, "#page", label = "Hi")
  expect_in("Silkscreen|400|loaded", page_font_families(page))
})

test_that("captions render in the staged font face", {
  page <- local_page()
  pz_stage_fonts(page, pz_font_file("Silkscreen", silkscreen_fixture()))
  caption <- list(
    text = "Hello caption",
    side = "bottom",
    color = "white",
    font_size = 20
  )
  staged_png <- withr::local_tempfile(fileext = ".png")
  fallback_png <- withr::local_tempfile(fileext = ".png")
  caption_render(
    page,
    c(caption, list(font_family = '"Silkscreen", sans-serif')),
    400,
    300,
    1,
    staged_png
  )
  caption_render(
    page,
    c(caption, list(font_family = "sans-serif")),
    400,
    300,
    1,
    fallback_png
  )
  expect_false(identical(
    readBin(staged_png, "raw", file.size(staged_png)),
    readBin(fallback_png, "raw", file.size(fallback_png))
  ))
})

test_that("re-staging a face with a different source replaces it in the document", {
  page <- local_page()
  silk <- pz_font_file("Silkscreen", silkscreen_fixture())
  # Same family key, different bytes: stands in for a second source
  bungee <- pz_font_file("Silkscreen", bungee_fixture())
  face_count <- function() {
    pz_js(
      page,
      "[...document.fonts].filter(f => f.family === 'Silkscreen' && f.weight === '400').length"
    )
  }
  probe_width <- function() {
    pz_js(
      page,
      paste0(
        "(() => { const el = document.createElement('span');",
        "el.textContent = 'Width probe';",
        "el.style.cssText = \"position:absolute;visibility:hidden;font:20px 'Silkscreen'\";",
        "document.body.appendChild(el); const w = el.offsetWidth;",
        "el.remove(); return w; })()"
      )
    )
  }

  pz_stage_fonts(page, silk)
  expect_equal(face_count(), 1)
  silk_width <- probe_width()

  pz_stage_fonts(page, bungee)
  expect_equal(face_count(), 1)
  expect_gt(abs(probe_width() - silk_width), 0)

  pz_stage_fonts(page, silk)
  expect_equal(face_count(), 1)
  expect_equal(probe_width(), silk_width)
})

test_that("load failures with braces in the family name stay literal", {
  page <- local_page()
  braced <- pz_font_file("Braced {Font}", local_corrupt_font())
  expect_error(
    pz_stage_fonts(page, braced, on_error = "stop"),
    "Braced \\{Font\\}",
    fixed = FALSE
  )
  expect_warning(
    pz_stage_fonts(page, braced, on_error = "warn"),
    "Braced \\{Font\\}"
  )
})

test_that("Google Fonts fonts load remotely", {
  skip_on_cran()
  skip_if_offline()
  page <- local_page()
  pz_stage_fonts(page, pz_font_google("Silkscreen"))
  expect_in("Silkscreen|400|loaded", page_font_families(page))
})

test_that("Bunny Fonts fonts load remotely", {
  skip_on_cran()
  skip_if_offline()
  page <- local_page()
  pz_stage_fonts(page, pz_font_bunny("Silkscreen"))
  expect_in("Silkscreen|400|loaded", page_font_families(page))
})
