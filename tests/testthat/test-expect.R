# Inside testthat, the bridge routes failures through testthat::expect() so
# they register as test failures. These tests override the env var(s)
# testthat::is_testing() consults to exercise the outside-tests path,
# where the same calls abort with the classed error instead. The set is
# immediate and the restore is deferred on the caller, because
# withr::local_envvar()'s envir argument was renamed in withr 3 and a
# helper-wrapped call would otherwise restore when the helper returns.
local_outside_testthat <- function(env = parent.frame()) {
  old <- Sys.getenv(c("TESTTHAT", "TESTTHAT_IS_TESTING"))
  Sys.setenv(TESTTHAT = "", TESTTHAT_IS_TESTING = "")
  withr::defer(do.call(Sys.setenv, as.list(old)), envir = env)
}

test_that("pz_expect_exists passes and returns ctx invisibly", {
  page <- local_elements_page()
  res <- withVisible(pz_expect_exists(page, target = ".btn"))
  expect_false(res$visible)
  expect_identical(res$value, page)
})

test_that("pz_expect_exists trivially passes at the root", {
  page <- local_elements_page()
  pz_expect_exists(page)
})

test_that("pz_expect_exists failure has the classed error format", {
  page <- local_elements_page()
  local_outside_testthat()
  err <- expect_error(
    pz_expect_exists(page, target = ".never", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
  msg <- conditionMessage(err)
  expect_match(msg, "Expected an element to match", fixed = TRUE)
  expect_match(msg, "Target: `.never`", fixed = TRUE)
  expect_match(msg, "Last seen: 0 matches", fixed = TRUE)
  expect_match(msg, "Waited", fixed = TRUE)
})

test_that("pz_expect_count passes exact counts and inclusive bounds", {
  page <- local_elements_page()
  pz_expect_count(page, n = 1, target = ".story")
  pz_expect_count(page, n = 3, target = ".message")
  pz_expect_count(page, min = 1, target = ".btn")
  pz_expect_count(page, max = 10, target = ".btn")
  pz_expect_count(page, min = 5, max = 7, target = ".btn") # 6 matches
  # min = max is the same as n
  pz_expect_count(page, min = 2, max = 2, target = ".chat")
  # not = TRUE passes when the count is anything else
  pz_expect_count(page, n = 2, target = ".message", not = TRUE)
})

test_that("pz_expect_count(n = 0) passes on a missing target without waiting", {
  page <- local_elements_page()
  start <- Sys.time()
  pz_expect_count(page, n = 0, target = ".never", timeout = 0)
  expect_lt(as.numeric(difftime(Sys.time(), start, units = "secs")), 1)
})

test_that("pz_expect_count validates its inputs", {
  page <- local_elements_page()
  expect_error(pz_expect_count(page), "range")
  expect_error(pz_expect_count(page, n = 1, min = 1), "combine")
  expect_error(pz_expect_count(page, n = 1, max = 1), "combine")
  expect_error(pz_expect_count(page, min = 3, max = 2), class = "paparazzi_error_input")
  expect_error(pz_expect_count(page, n = 1.5), "whole")
  expect_error(pz_expect_count(page, n = -1), "whole")
  expect_error(pz_expect_count(page, n = 1, extra = 1), "empty")
})

test_that("pz_expect_count failure shows the observed count", {
  page <- local_elements_page()
  local_outside_testthat()
  err <- expect_error(
    pz_expect_count(page, n = 3, target = ".btn", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
  msg <- conditionMessage(err)
  expect_match(msg, "Expected count to be exactly 3", fixed = TRUE)
  expect_match(msg, "Last seen: 6 matches", fixed = TRUE)
})

test_that("pz_expect_visible requires every match to be visible", {
  page <- local_elements_page()
  pz_expect_visible(page, target = ".message")
  pz_expect_visible(page, target = ".story")

  local_outside_testthat()
  err <- expect_error(
    pz_expect_visible(page, target = ".ghost", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
  expect_match(conditionMessage(err), "0 of 1 visible", fixed = TRUE)
  expect_match(
    conditionMessage(err),
    "Expected all elements to be visible",
    fixed = TRUE
  )

  # A set mixing visible and hidden elements fails with the mix visible.
  err <- expect_error(
    pz_expect_visible(page, target = list(".story", ".ghost"), timeout = 0),
    class = "paparazzi_expectation_failure"
  )
  msg <- conditionMessage(err)
  expect_match(msg, "1 of 2 visible", fixed = TRUE)
  expect_match(msg, "Target: `.story` | `.ghost`", fixed = TRUE)
})

test_that("pz_expect_hidden is pz_expect_visible(not = TRUE)", {
  page <- local_elements_page()
  # .ghost is display: none; .veiled is visibility: hidden.
  pz_expect_hidden(page, target = ".ghost")
  pz_expect_hidden(page, target = ".veiled")
  pz_expect_visible(page, target = ".ghost", not = TRUE)
  # Zero matches counts as hidden, for both spellings.
  pz_expect_hidden(page, target = ".never")
  pz_expect_visible(page, target = ".never", not = TRUE)

  local_outside_testthat()
  err <- expect_error(
    pz_expect_hidden(page, target = ".story", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
  expect_match(
    conditionMessage(err),
    "Expected no element to be visible",
    fixed = TRUE
  )
})

test_that("pz_expect_text contains, exact, and regex, whitespace-collapsed", {
  page <- local_elements_page()
  pz_expect_text(page, "otters", target = ".story")
  pz_expect_text(page, "Once there were otters.", target = ".story", match = "exact")
  pz_expect_text(page, "ott+ers", target = ".story", match = "regex")
  # The fixture text runs "  Once   there were   otters.  "; both sides
  # collapse before comparing.
  pz_expect_text(page, "Once   there were otters.", target = ".story", match = "exact")
  # A single value applies to every match.
  pz_expect_text(page, "same words", target = ".twin", match = "exact")
})

test_that("pz_expect_text compares vectors pairwise in order", {
  page <- local_elements_page()
  texts <- c("What's the weather?", "The weather is sunny.", "Bring a hat.")
  pz_expect_text(page, texts, target = ".message", match = "exact")
  pz_expect_text(page, c("same words", "same words"), target = ".twin", match = "exact")

  local_outside_testthat()
  # Wrong order: pairwise comparison fails.
  expect_error(
    pz_expect_text(page, rev(texts), target = ".message", match = "exact", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
  # Length n requires exactly n matches: two values against three
  # elements never passes.
  expect_error(
    pz_expect_text(page, texts[1:2], target = ".message", match = "exact", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
})

test_that("pz_expect_text with not = TRUE", {
  page <- local_elements_page()
  pz_expect_text(page, "penguins", target = ".story", not = TRUE)
  # No match satisfies, including zero matches.
  pz_expect_text(page, "anything", target = ".never", not = TRUE, timeout = 0)
  # Partial satisfaction fails the negation too: 3 of 6 .btn contain
  # "Save", and the SPEC's negation needs NO match to satisfy.
  testthat::expect_failure(
    pz_expect_text(page, "Save", target = ".btn", not = TRUE, timeout = 0)
  )
  # Same for vectors: the first .twin satisfies its pairwise text, so
  # the negation fails even though the second pair doesn't match.
  testthat::expect_failure(
    pz_expect_text(
      page,
      c("same words", "WRONG"),
      target = ".twin",
      not = TRUE,
      timeout = 0
    )
  )
  # When the count differs from the vector length there is no pairwise
  # correspondence, so the negation passes vacuously.
  pz_expect_text(
    page,
    c("What's the weather?", "Bring a hat."),
    target = ".panel",
    not = TRUE,
    timeout = 0
  )
})

test_that("page text is never interpreted as cli markup", {
  page <- local_elements_page()
  local_outside_testthat()
  err <- expect_error(
    pz_expect_text(page, "nope", target = ".brace", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
  # If the observed text were glued as a template this would read "2".
  expect_match(conditionMessage(err), "{1 + 1}", fixed = TRUE)
})

test_that("pz_expect_text failure shows the last seen text", {
  page <- local_elements_page()
  local_outside_testthat()
  err <- expect_error(
    pz_expect_text(page, "penguins", target = ".story", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
  msg <- conditionMessage(err)
  expect_match(msg, 'Expected text to contain "penguins"', fixed = TRUE)
  expect_match(msg, "Target: `.story`", fixed = TRUE)
  expect_match(msg, 'Last seen: "Once there were otters."', fixed = TRUE)
  expect_match(msg, "Waited", fixed = TRUE)
})

test_that("target = NULL at the root resolves to document.body", {
  page <- local_elements_page()
  pz_expect_text(page, "otters")

  local_outside_testthat()
  err <- expect_error(
    pz_expect_text(page, "penguins", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
  expect_match(conditionMessage(err), "Target: document.body", fixed = TRUE)
})

test_that("expectations retry until they pass", {
  page <- local_elements_page()
  # The element gains the expected text only after 300 ms.
  pz_js(
    page,
    "setTimeout(() => { document.querySelector('.late-text').textContent = 'ready now'; }, 300)",
    await = FALSE
  )
  pz_expect_text(page, "ready now", target = ".late-text", timeout = 5)
})

test_that("timeout = 0 checks once and fails fast", {
  page <- local_elements_page()
  pz_js(
    page,
    "setTimeout(() => { document.querySelector('.late-text').textContent = 'ready now'; }, 300)",
    await = FALSE
  )
  local_outside_testthat()
  start <- Sys.time()
  expect_error(
    pz_expect_text(page, "ready now", target = ".late-text", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
  expect_lt(as.numeric(difftime(Sys.time(), start, units = "secs")), 1)
})

test_that("the testthat bridge counts passes and reports failures", {
  page <- local_elements_page()
  expect_success(pz_expect_exists(page, target = ".btn"))
  expect_failure(pz_expect_exists(page, target = ".never", timeout = 0))
})

test_that("outside of testthat, failures abort with the classed error", {
  page <- local_elements_page()
  local_outside_testthat()
  expect_error(
    pz_expect_visible(page, target = ".ghost", timeout = 0),
    class = "paparazzi_expectation_failure"
  )
})

test_that("expectations validate their inputs", {
  page <- local_elements_page()
  expect_error(pz_expect_exists(page, extra = 1), "empty")
  expect_error(pz_expect_exists(1, target = ".btn"), class = "paparazzi_error_context")
  expect_error(pz_expect_exists(page, target = ".btn", not = "yes"), "yes")
  expect_error(pz_expect_hidden(page, target = ".btn", not = 1), "not")
  expect_error(pz_expect_exists(page, target = ".btn", timeout = -1), "timeout")
  expect_error(pz_expect_text(page, 1), "character")
  expect_error(
    pz_expect_text(page, "x", target = ".btn", match = "near"),
    "contains"
  )
  expect_error(pz_expect_visible(page, target = list()), class = "paparazzi_error_target")
})

test_that("expect_retry returns the last failure without aborting", {
  page <- local_elements_page()
  n <- 0
  result <- expect_retry(
    function() {
      n <<- n + 1
      list(pass = FALSE, observed = n)
    },
    timeout = 0.25,
    loop = page$child_loop
  )
  expect_false(result$pass)
  expect_identical(result$observed, n)
  expect_gte(n, 2)
})

test_that("expect_retry with timeout = 0 checks once", {
  page <- local_elements_page()
  n <- 0
  result <- expect_retry(
    function() {
      n <<- n + 1
      list(pass = TRUE)
    },
    timeout = 0,
    loop = page$child_loop
  )
  expect_true(result$pass)
  expect_identical(n, 1)
})

test_that("expect_retry pumps the page's event loop between checks", {
  page <- local_elements_page()
  fired <- FALSE
  later::later(function() fired <<- TRUE, delay = 0.1, loop = page$child_loop)
  result <- expect_retry(
    function() list(pass = fired),
    timeout = 2,
    loop = page$child_loop
  )
  expect_true(result$pass)
})
