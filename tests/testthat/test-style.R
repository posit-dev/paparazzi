# pz_get_style() / pz_expect_style() read and check computed styles.
# Everything runs against style.html: a #sizes parent with a #half
# child sized in %, an #em-parent/#em-child pair sized in em, an
# #em-margin element with a 1em margin, a #current element using
# currentColor, a #primary button and an #rgb-box in hex, a #rem-box,
# a #vw-box, a #third with a subpixel width, a #spaced shorthand, three
# .card matches plus one .mixed odd one out, a #late element, and a
# #custom element with a custom property. style-empty.html is an
# empty-body page for the DOM-untouched checks.

# Same pattern as test-expect.R: test files can't rely on each other's
# sourcing order, so each failure-path file carries its own copy.
local_outside_testthat <- function(env = parent.frame()) {
  old <- Sys.getenv(c("TESTTHAT", "TESTTHAT_IS_TESTING"))
  Sys.setenv(TESTTHAT = "", TESTTHAT_IS_TESTING = "")
  withr::defer(do.call(Sys.setenv, as.list(old)), envir = env)
}

test_that("pz_get_style returns a tibble with one row per match and per-property columns", {
  page <- local_style_page()
  styles <- pz_get_style(page, c("color", "background_color"), target = "#primary")
  expect_s3_class(styles, "tbl_df")
  expect_named(styles, c("color", "background-color", "element"))
  expect_identical(nrow(styles), 1L)
  expect_identical(styles$color, "rgb(255, 255, 255)")
  expect_identical(styles[["background-color"]], "rgb(13, 110, 253)")
})

test_that("pz_get_style turns snake_case into kebab-case columns", {
  page <- local_style_page()
  styles <- pz_get_style(page, c("font_size", "margin_left"), target = "#rem-box")
  expect_named(styles, c("font-size", "margin-left", "element"))
  expect_identical(styles[["font-size"]], "24px")
})

test_that("pz_get_style with props = NULL returns every computed property", {
  page <- local_style_page()
  styles <- pz_get_style(page, target = "#rem-box")
  expect_identical(nrow(styles), 1L)
  # Chrome reports 400+ longhand properties and no shorthands.
  expect_gt(ncol(styles), 400L)
  expect_true("width" %in% names(styles))
  expect_false("margin" %in% names(styles))
})

test_that("pz_get_style with props = NULL unions properties across matches", {
  page <- local_style_page()
  # Only #custom reports --bs-primary: the column set is the union
  # across matches, so the column exists, and the #sizes row (no
  # such custom property) reads as "".
  styles <- pz_get_style(page, target = "#sizes, #custom")
  expect_identical(nrow(styles), 2L)
  expect_true("--bs-primary" %in% names(styles))
  expect_identical(styles["--bs-primary"][[1]], c("", "#0d6efd"))
})

test_that("pz_get_style reads one row per match in order", {
  page <- local_style_page()
  cards <- pz_get_style(page, "color", target = ".card")
  expect_identical(nrow(cards), 3L)
  expect_identical(cards$color, rep("rgb(51, 51, 51)", 3))
})

test_that("pz_get_style reads custom properties", {
  page <- local_style_page()
  styles <- pz_get_style(page, "--bs-primary", target = "#custom")
  expect_identical(styles[["--bs-primary"]], "#0d6efd")
})

test_that("the pz_get_style element column continues the chain", {
  page <- local_style_page()
  cards <- pz_get_style(page, "color", target = ".card")
  expect_type(cards$element, "list")
  expect_identical(length(cards$element), 3L)
  expect_true(all(vapply(cards$element, inherits, logical(1), "PaparazziContext")))
  expect_identical(pz_get_text(cards$element[[2]]), "two")
})

test_that("pz_get_style works from a scoped context and at the root", {
  page <- local_style_page()
  scoped <- pz_find(page, "#sizes")
  expect_identical(pz_get_style(scoped, "width")[["width"]], "200px")
  expect_identical(pz_get_style(page, "display")[["display"]], "block")
})

test_that("pz_get_style validates its inputs", {
  page <- local_style_page()
  expect_error(pz_get_style(page, "color", "extra"), class = "rlang_error")
  # With target = NULL a non-context ctx would crash deeper in the
  # scope stack; an explicit target routes through check_context.
  expect_error(
    pz_get_style(1, "color", target = "#primary"),
    class = "paparazzi_error_context"
  )
  expect_error(pz_get_style(page, 1), "character")
  expect_error(pz_get_style(page, NA_character_), class = "paparazzi_error_input")
  expect_error(
    pz_get_style(page, c("color", "font_size", "color")),
    class = "paparazzi_error_input"
  )
})

test_that("pz_get_style rejects shorthands and suggests longhands", {
  page <- local_style_page()
  err <- expect_error(
    pz_get_style(page, "margin", target = "#spaced"),
    class = "paparazzi_error_input"
  )
  expect_match(conditionMessage(err), "margin-top", fixed = TRUE)
  expect_error(
    pz_get_style(page, c("color", "background")),
    class = "paparazzi_error_input"
  )
})

test_that("hex expectations match computed rgb() values", {
  page <- local_style_page()
  res <- withVisible(
    pz_expect_style(page, color = "#ffffff", background_color = "#0d6efd", target = "#primary")
  )
  expect_false(res$visible)
  expect_identical(res$value, page)
})

test_that("em resolves against the parent font for font-size, the own font otherwise", {
  page <- local_style_page()
  # #em-child is 1.5em of #em-parent's 20px = 30px.
  pz_expect_style(page, font_size = "1.5em", target = "#em-child")
  pz_expect_style(page, font_size = "2em", target = "#em-child", not = TRUE)
  # margin-left: 1em uses the element's own 20px font.
  pz_expect_style(page, margin_left = "1em", target = "#em-margin")
})

test_that("percentages resolve against the parent's size", {
  page <- local_style_page()
  pz_expect_style(page, width = "50%", height = "25%", target = "#half")
})

test_that("currentColor resolves against the target's color", {
  page <- local_style_page()
  pz_expect_style(page, border_color = "currentColor", target = "#current")
})

test_that("rem and vw need no context", {
  page <- local_style_page()
  pz_expect_style(page, font_size = "1.5rem", target = "#rem-box")
  pz_expect_style(page, width = "50vw", target = "#vw-box")
})

test_that("keywords normalize to computed values", {
  page <- local_style_page()
  # font-weight: normal computes to 400.
  pz_expect_style(page, font_weight = "normal", target = "#primary")
})

test_that("numeric px comparisons tolerate ~0.5px of noise", {
  page <- local_style_page()
  # #third is 200px / 3 = 66.67px: 0.17px off passes, 0.67px off fails.
  pz_expect_style(page, width = "66.5px", target = "#third")
  local_outside_testthat()
  expect_error(
    pz_expect_style(page, width = "66px", target = "#third", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
})

test_that("every match must satisfy every pair", {
  page <- local_style_page()
  pz_expect_style(page, color = "#333333", target = ".card")
  local_outside_testthat()
  # .mixed has a fourth, differently colored member.
  err <- expect_error(
    pz_expect_style(page, color = "#333333", target = ".mixed", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
  expect_match(conditionMessage(err), "Last seen: color: rgb(51, 51, 51)", fixed = TRUE)
})

test_that("not = TRUE passes when at least one pair doesn't match", {
  page <- local_style_page()
  pz_expect_style(page, color = "#333333", target = ".mixed", not = TRUE)
  # All .card matches agree, so the negation fails.
  local_outside_testthat()
  expect_error(
    pz_expect_style(page, color = "#333333", target = ".card", not = TRUE, timeout = 0),
    class = "paparazzi_expectation_failure"
  )
})

test_that("not = TRUE passes when nothing matches", {
  page <- local_style_page()
  pz_expect_style(page, color = "red", target = ".never", not = TRUE)
})

test_that("!!! splices a list of style pairs", {
  page <- local_style_page()
  styles <- list(color = "#ffffff", font_weight = "normal")
  pz_expect_style(page, !!!styles, target = "#primary")
})

test_that("custom properties pass their names and values through", {
  page <- local_style_page()
  pz_expect_style(page, `--bs-primary` = "#0d6efd", target = "#custom")
})

test_that("normalize = FALSE compares raw computed strings", {
  page <- local_style_page()
  pz_expect_style(page, color = "rgb(13, 110, 253)", target = "#rgb-box", normalize = FALSE)
  # The px tolerance still applies in raw mode.
  pz_expect_style(page, width = "66.5px", target = "#third", normalize = FALSE)
  local_outside_testthat()
  expect_error(
    pz_expect_style(page, color = "#0d6efd", target = "#rgb-box", normalize = FALSE, timeout = 0),
    class = "paparazzi_expectation_failure"
  )
})

test_that("invalid CSS errors immediately, without retrying", {
  # The page default is 3s: an implementation that retried would burn
  # it before failing; invalid CSS aborts on the first check.
  page <- local_page(style_fixture_file(), timeout = 3)
  start <- Sys.time()
  expect_error(
    pz_expect_style(page, width = "nonsense", target = "#sizes"),
    class = "paparazzi_error_input"
  )
  expect_lt(as.numeric(difftime(Sys.time(), start, units = "secs")), 1)
  # An unknown property name is rejected the same way.
  expect_error(
    pz_expect_style(page, colour = "red", target = "#sizes"),
    class = "paparazzi_error_input"
  )
})

test_that("invalid CSS errors immediately even with no matches", {
  # The verdict is target-independent: with no matches a plain
  # expectation would retry to the timeout and not = TRUE would pass,
  # but invalid CSS still aborts on the first check.
  page <- local_page(style_fixture_file(), timeout = 3)
  start <- Sys.time()
  expect_error(
    pz_expect_style(page, color = "not-a-color", target = ".absent"),
    class = "paparazzi_error_input"
  )
  expect_error(
    pz_expect_style(page, color = "not-a-color", target = ".absent", not = TRUE),
    class = "paparazzi_error_input"
  )
  expect_lt(as.numeric(difftime(Sys.time(), start, units = "secs")), 1)
})

test_that("pz_expect_style rejects shorthands and suggests longhands", {
  page <- local_style_page()
  err <- expect_error(
    pz_expect_style(page, margin = "1rem", target = "#spaced"),
    class = "paparazzi_error_input"
  )
  expect_match(conditionMessage(err), "margin-top", fixed = TRUE)
  expect_error(
    pz_expect_style(page, background = "#0d6efd", target = "#primary"),
    class = "paparazzi_error_input"
  )
})

test_that("pz_expect_style retries until the style arrives", {
  page <- local_style_page()
  pz_js(
    page,
    "setTimeout(() => document.getElementById('late').classList.add('blue'), 300)",
    await = FALSE
  )
  pz_expect_style(page, color = "#0000ff", target = "#late", timeout = 5)
})

test_that("pz_expect_style failure has the classed error format", {
  page <- local_style_page()
  local_outside_testthat()
  err <- expect_error(
    pz_expect_style(page, color = "red", target = "#rgb-box", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
  msg <- conditionMessage(err)
  expect_match(msg, "Expected style to match color: \"red\"", fixed = TRUE)
  expect_match(msg, "Target: `#rgb-box`", fixed = TRUE)
  expect_match(msg, "Last seen: color: rgb(13, 110, 253)", fixed = TRUE)
  expect_match(msg, "Waited", fixed = TRUE)
})

test_that("pz_expect_style works from a scoped context and at the root", {
  page <- local_style_page()
  pz_find(page, "#em-parent") |> pz_expect_style(font_size = "20px")
  pz_find(page, "#sizes") |> pz_expect_style(width = "50%", target = "#half")
  # target = NULL at the root checks the body.
  pz_expect_style(page, display = "block")
})

test_that("pz_expect_style validates its inputs", {
  page <- local_style_page()
  expect_error(pz_expect_style(page, target = "#primary"), "pair")
  expect_error(pz_expect_style(page, "red", target = "#primary"), "named")
  expect_error(pz_expect_style(page, color = 1, target = "#primary"), "strings")
  expect_error(pz_expect_style(page, color = NA, target = "#primary"), "strings")
  expect_error(pz_expect_style(1, color = "red"), class = "paparazzi_error_context")
  expect_error(
    pz_expect_style(page, color = "red", normalize = "yes", target = "#primary"),
    "normalize"
  )
  expect_error(
    pz_expect_style(page, color = "red", not = "yes", target = "#primary"),
    "not"
  )
  expect_error(
    pz_expect_style(page, color = "red", timeout = -1, target = "#primary"),
    "timeout"
  )
  dup <- list(font_size = "10px", `font-size` = "12px")
  err <- expect_error(
    pz_expect_style(page, !!!dup, target = "#primary"),
    class = "paparazzi_error_input"
  )
  expect_match(conditionMessage(err), "Duplicated", fixed = TRUE)
})

test_that("the probe never enters the app's DOM", {
  page <- local_style_page()
  # documentElement children are head and body only, before any
  # normalization has run.
  expect_equal(pz_js(page, "document.documentElement.children.length"), 2)
  before <- pz_js(
    page,
    "document.documentElement.lastElementChild === document.body"
  )
  expect_true(before)
  before_count <- pz_get_count(page, target = "body div")
  pz_expect_style(page, width = "50%", target = "#half")
  pz_expect_style(page, font_size = "1.5em", target = "#em-child")
  # The probe host lives only inside the synchronous JS call: once
  # the expectations return, the DOM shows no trace -- no host anywhere
  # to find, documentElement's last child unchanged, no extra nodes.
  expect_true(pz_js(page, "document.querySelector('html > div') === null"))
  expect_equal(pz_js(page, "document.documentElement.children.length"), 2)
  expect_identical(
    pz_js(page, "document.documentElement.lastElementChild === document.body"),
    before
  )
  expect_identical(pz_get_count(page, target = "body div"), before_count)
})

test_that("the probe leaves body:empty matching unaffected", {
  page <- local_page(style_empty_fixture_file())
  expect_identical(pz_get_count(page, target = "body:empty"), 1L)
  pz_expect_style(page, display = "block", target = "body")
  # The body still matches :empty after normalization: the probe is
  # created and removed within the one JS call, never appended to
  # the body.
  expect_identical(pz_get_count(page, target = "body:empty"), 1L)
})
