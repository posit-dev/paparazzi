shiny_input_fixture <- function() test_path("fixtures", "shiny-input")

local_shiny_input_page <- function(.env = parent.frame()) {
  skip_if_no_chrome()
  skip_if_no_shiny()
  page <- pz_open(shiny_input_fixture(), timeout = 8)
  withr::defer(pz_close(page), envir = .env)
  page
}

shiny_input_text <- function(page, id) {
  pz_js(page, paste0("document.getElementById(", jsonlite::toJSON(id, auto_unbox = TRUE), ").textContent"))
}

test_that("binding setters update control UI and server outputs, including repeated waits", {
  page <- local_shiny_input_page()
  expect_invisible(pz_set_shiny_input(page, "text", "first update"))
  expect_equal(pz_js(page, "document.getElementById('text').value"), "first update")
  expect_equal(shiny_input_text(page, "text_out"), "first update")
  for (i in seq_len(8)) {
    value <- paste("repeat", i)
    expect_invisible(pz_set_shiny_input(page, "text", value))
    expect_equal(shiny_input_text(page, "text_out"), value)
  }
  pz_set_shiny_input(page, "choice", "second")
  expect_equal(pz_js(page, "document.getElementById('choice').value"), "second")
  expect_equal(shiny_input_text(page, "choice_out"), "second")
  pz_set_shiny_input(page, "amount", 42)
  expect_equal(pz_js(page, "document.getElementById('amount').value"), "42")
  expect_equal(shiny_input_text(page, "amount_out"), "42")
  pz_set_shiny_input(page, "day", "2024-02-12")
  expect_equal(shiny_input_text(page, "day_out"), "2024-02-12")
  expect_equal(as.numeric(pz_js(page, "document.getElementById('day').value")), 1707696000000)
  pz_set_shiny_input(page, "dates", c("2024-02-01", "2024-02-06"))
  expect_equal(pz_js(page, "document.getElementById('dates').querySelector('input').value"), "2024-02-01")
  expect_equal(shiny_input_text(page, "dates_out"), "2024-02-01 / 2024-02-06")
  pz_set_shiny_input(page, "dates", list(start = "2024-03-01", end = "2024-03-04"))
  expect_equal(shiny_input_text(page, "dates_out"), "2024-03-01 / 2024-03-04")
  scoped <- pz_find(page, "#module-root")
  pz_set_shiny_input(scoped, "mod-text", "inside")
  expect_equal(shiny_input_text(page, "mod-out"), "inside")
  expect_error(pz_set_shiny_input(scoped, "text", "outside"), "text.*scope", class = "paparazzi_error_binding")
  expect_equal(shiny_input_text(page, "text_out"), "repeat 8")
  input_scope <- pz_find(page, "#mod-text")
  pz_set_shiny_input(input_scope, "mod-text", "root itself")
  expect_equal(shiny_input_text(page, "mod-out"), "root itself")
})

test_that("fine-step numeric binding retains precision in control and server", {
  page <- local_shiny_input_page()
  pz_set_shiny_input(page, "precise", 1.23456789)
  expect_equal(as.numeric(pz_js(page, "document.getElementById('precise').value")), 1.23456789, tolerance = 1e-10)
  expect_equal(shiny_input_text(page, "precise_out"), "1.23456789")
})

test_that("missing bindings, unsupported values and invalid arguments fail clearly", {
  page <- local_shiny_input_page()
  expect_error(pz_set_shiny_input(page, "absent", "x"), "absent.*scope", class = "paparazzi_error_binding")
  expect_error(pz_set_shiny_input(page, "text_out", "x"), "text_out.*scope", class = "paparazzi_error_binding")
  expect_error(pz_set_shiny_input(page, "button", "click"), "button.*scope", class = "paparazzi_error_binding")
  expect_error(pz_set_shiny_input(page, "file", "x"), "file.*scope", class = "paparazzi_error_binding")
  expect_error(pz_set_shiny_input(page, "dates", "2024-01-01"), "two date-range endpoints", class = "paparazzi_error_input")
  expect_error(pz_set_shiny_input(page, "", "x"), "id", class = "paparazzi_error_input")
  expect_error(pz_set_shiny_input(page, "text", NULL), class = "rlang_error")
  expect_error(pz_set_shiny_input(page, "text", "x", wait = NA), "wait")
  expect_error(pz_set_shiny_input(page, "text", "x", extra = 1), "empty")
  expect_error(pz_set_shiny_input(page, 1, "x"), "string")
  expect_error(pz_set_shiny_input(1, "text", "x"), class = "paparazzi_error_context")
  expect_invisible(pz_set_shiny_input(page, "text", "no wait", wait = FALSE))
  pz_expect_text(page, "no wait", target = "#text_out", match = "exact")
})

test_that("a non-Shiny page cannot have a bound Shiny input", {
  skip_if_no_chrome()
  page <- pz_open("about:blank")
  withr::defer(pz_close(page))
  expect_error(pz_set_shiny_input(page, "text", "x"), "text.*scope", class = "paparazzi_error_binding")
})

test_that("the owned fixture app has readable logs and stops at page close", {
  page <- local_shiny_input_page()
  owned <- page$.__enclos_env__$private$owned_app_
  port <- owned$port
  expect_true(any(grepl("PAPARAZZI_SHINY_INPUT_READY", owned$logs(), fixed = TRUE)))
  pz_set_shiny_input(page, "choice", "second")
  expect_equal(shiny_input_text(page, "choice_out"), "second")
  pz_close(page)
  expect_true(wait_until(function() !app_port_reachable(port)))
})

test_that("a taken port is retried while opening the widget fixture", {
  skip_if_no_chrome()
  skip_if_no_shiny()
  taken <- free_port()
  server <- httpuv::startServer("127.0.0.1", taken, list())
  withr::defer(httpuv::stopServer(server))
  page <- pz_open(shiny_input_fixture(), shiny_options = list(port = taken))
  withr::defer(pz_close(page))
  expect_false(identical(as.integer(pz_js(page, "location.port")), taken))
  pz_set_shiny_input(page, "text", "retried")
  expect_equal(shiny_input_text(page, "text_out"), "retried")
})

test_that("block errors close their owned widget app", {
  skip_if_no_chrome()
  skip_if_no_shiny()
  port <- NULL
  expect_error(pz_with_page(shiny_input_fixture(), function(page) {
    port <<- as.integer(pz_js(page, "location.port"))
    pz_set_shiny_input(page, "text", "before error")
    expect_equal(shiny_input_text(page, "text_out"), "before error")
    stop("fixture block failure")
  }), "fixture block failure")
  expect_true(wait_until(function() !app_port_reachable(port)))
})
