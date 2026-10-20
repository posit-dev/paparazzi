shiny_input_fixture <- function() test_path("fixtures", "shiny-input")

local_shiny_input_page <- function(.env = parent.frame()) {
  skip_if_no_chrome()
  skip_if_no_shiny()
  page <- pz_open(shiny_input_fixture(), timeout = 8)
  withr::defer(pz_close(page), envir = .env)
  page
}

test_that("binding setters update control UI and server outputs, including repeated waits", {
  page <- local_shiny_input_page()

  expect_invisible(pz_set_shiny_input(page, "text", "first update"))
  expect_equal(
    pz_evaluate(page, "document.getElementById('text').value"),
    "first update"
  )
  pz_expect_text(page, "first update", target = "#text_out")

  for (i in seq_len(8)) {
    value <- paste("repeat", i)
    expect_invisible(pz_set_shiny_input(page, "text", value))
    pz_expect_text(page, value, target = "#text_out")
  }

  pz_set_shiny_input(page, "choice", "second")
  expect_equal(
    pz_evaluate(page, "document.getElementById('choice').value"),
    "second"
  )
  pz_expect_text(page, "second", target = "#choice_out")

  pz_set_shiny_input(page, "amount", 42)
  expect_equal(
    pz_evaluate(page, "document.getElementById('amount').value"),
    "42"
  )
  pz_expect_text(page, "42", target = "#amount_out")

  pz_set_shiny_input(page, "day", "2024-02-12")
  pz_expect_text(page, "2024-02-12", target = "#day_out")
  expect_equal(
    as.numeric(pz_evaluate(page, "document.getElementById('day').value")),
    1707696000000
  )

  pz_set_shiny_input(page, "dates", c("2024-02-01", "2024-02-06"))
  expect_equal(
    pz_evaluate(
      page,
      "document.getElementById('dates').querySelector('input').value"
    ),
    "2024-02-01"
  )
  pz_expect_text(
    page,
    "2024-02-01 / 2024-02-06",
    target = "#dates_out"
  )

  pz_set_shiny_input(
    page,
    "dates",
    list(start = "2024-03-01", end = "2024-03-04")
  )
  pz_expect_text(
    page,
    "2024-03-01 / 2024-03-04",
    target = "#dates_out"
  )

  scoped <- pz_find(page, "#module-root")
  pz_set_shiny_input(scoped, "mod-text", "inside")
  pz_expect_text(page, "inside", target = "#mod-out")
  expect_error(
    pz_set_shiny_input(scoped, "text", "outside"),
    "text.*scope",
    class = "paparazzi_error_binding"
  )
  # The prior expectation established this value; a rejected update sends nothing.
  expect_equal(pz_get_text(page, target = "#text_out"), "repeat 8")

  input_scope <- pz_find(page, "#mod-text")
  pz_set_shiny_input(input_scope, "mod-text", "root itself")
  pz_expect_text(page, "root itself", target = "#mod-out")
})

test_that("fine-step numeric binding retains precision in control and server", {
  page <- local_shiny_input_page()
  pz_set_shiny_input(page, "precise", 1.23456789)
  expect_equal(
    as.numeric(pz_evaluate(page, "document.getElementById('precise').value")),
    1.23456789,
    tolerance = 1e-10
  )
  pz_expect_text(page, "1.23456789", target = "#precise_out")
})

test_that("binding setters delegate to the real Shiny idle wait per the wait argument", {
  page <- local_shiny_input_page()
  pz_expect_text(page, "initial", target = "#text_out")
  spy <- local_shiny_idle_spy()
  url <- pz_get_url(page)

  expect_invisible(pz_set_shiny_input(page, "text", "default wait"))
  expect_equal(spy$urls, url)

  expect_invisible(
    pz_set_shiny_input(page, "text", "explicit wait", wait = TRUE)
  )
  expect_equal(spy$urls, c(url, url))

  expect_invisible(
    pz_set_shiny_input(page, "text", "no wait", wait = FALSE)
  )
  expect_equal(spy$urls, c(url, url))

  pz_expect_text(page, "no wait", target = "#text_out")
})

test_that("missing bindings, unsupported values and invalid arguments fail clearly", {
  page <- local_shiny_input_page()
  expect_error(
    pz_set_shiny_input(page, "absent", "x"),
    "absent.*scope",
    class = "paparazzi_error_binding"
  )
  expect_error(
    pz_set_shiny_input(page, "text_out", "x"),
    "text_out.*scope",
    class = "paparazzi_error_binding"
  )
  expect_error(
    pz_set_shiny_input(page, "button", "click"),
    "button.*scope",
    class = "paparazzi_error_binding"
  )
  expect_error(
    pz_set_shiny_input(page, "file", "x"),
    "file.*scope",
    class = "paparazzi_error_binding"
  )

  expect_error(
    pz_set_shiny_input(page, "dates", "2024-01-01"),
    "two date-range endpoints",
    class = "paparazzi_error_input"
  )
  expect_error(
    pz_set_shiny_input(page, "", "x"),
    "id",
    class = "paparazzi_error_input"
  )

  expect_error(pz_set_shiny_input(page, "text", NULL), class = "rlang_error")
  expect_error(pz_set_shiny_input(page, "text", "x", wait = NA), "wait")
  expect_error(pz_set_shiny_input(page, "text", "x", extra = 1), "empty")
  expect_error(pz_set_shiny_input(page, 1, "x"), "string")
  expect_error(
    pz_set_shiny_input(1, "text", "x"),
    class = "paparazzi_error_context"
  )

  expect_invisible(pz_set_shiny_input(page, "text", "no wait", wait = FALSE))
  pz_expect_text(page, "no wait", target = "#text_out")
})

test_that("a non-Shiny page cannot have a bound Shiny input", {
  skip_if_no_chrome()
  page <- pz_open("about:blank")
  withr::defer(pz_close(page))
  expect_error(
    pz_set_shiny_input(page, "text", "x"),
    "text.*scope",
    class = "paparazzi_error_binding"
  )
})

test_that("the owned fixture app has readable logs and stops at page close", {
  page <- local_shiny_input_page()
  owned <- page$app
  port <- owned$port

  expect_true(any(grepl(
    "PAPARAZZI_SHINY_INPUT_READY",
    owned$logs(),
    fixed = TRUE
  )))

  pz_close(page)
  expect_true(wait_until(function() !app_port_reachable(port)))
})

test_that("a taken port is retried while opening the widget fixture", {
  skip_if_no_chrome()
  skip_if_no_shiny()
  taken <- local_blocker_server()$port
  page <- pz_open(shiny_input_fixture(), shiny_options = list(port = taken))
  withr::defer(pz_close(page))

  expect_false(identical(as.integer(pz_evaluate(page, "location.port")), taken))

  pz_set_shiny_input(page, "text", "retried")
  pz_expect_text(page, "retried", target = "#text_out")
})

test_that("block errors close their owned widget app", {
  skip_if_no_chrome()
  skip_if_no_shiny()
  port <- NULL
  expect_error(
    pz_with_page(shiny_input_fixture(), function(page) {
      port <<- as.integer(pz_evaluate(page, "location.port"))
      pz_set_shiny_input(page, "text", "before error")
      pz_expect_text(
        page,
        "before error",
        target = "#text_out"
      )
      stop("fixture block failure")
    }),
    "fixture block failure"
  )

  expect_true(wait_until(function() !app_port_reachable(port)))
})
