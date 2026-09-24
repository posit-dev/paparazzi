test_that("pz_wait pauses and returns ctx invisibly", {
  page <- local_page()
  start <- Sys.time()
  res <- withVisible(pz_wait(page, 0.3))
  elapsed <- as.numeric(difftime(Sys.time(), start, units = "secs"))

  expect_gte(elapsed, 0.25)
  expect_false(res$visible)
  expect_identical(res$value, page)
})

test_that("pz_wait pumps the child loop so timers fire during waits", {
  page <- local_page()
  fired <- FALSE
  later::later(function() fired <<- TRUE, delay = 0.1, loop = page$child_loop)
  pz_wait(page, 0.5)
  expect_true(fired)
})

test_that("pz_poll times out with a classed error", {
  page <- local_page()
  err <- expect_error(
    pz_poll(
      function() FALSE,
      timeout = 0.2,
      loop = page$child_loop,
      what = "never"
    ),
    class = "paparazzi_error_timeout"
  )
  # `what` is interpolated as plain text, not wrapped in {.val}.
  expect_match(
    conditionMessage(err),
    "Timed out after 0.2s waiting for never.",
    fixed = TRUE
  )
})

test_that("pz_poll returns as soon as the condition holds", {
  page <- local_page()
  n <- 0
  start <- Sys.time()
  pz_poll(
    function() {
      n <<- n + 1
      n >= 2
    },
    timeout = 5,
    loop = page$child_loop
  )
  expect_lt(as.numeric(difftime(Sys.time(), start, units = "secs")), 2)
})

# The wait-for functions run against waits.html: #ticker changes text
# every 50 ms then settles, #bouncer animates for 1.2 s then rests,
# #endless animates forever, #never-still never settles, and #nav-link
# points at nav-target.html.

test_that("pz_wait_for_js waits for a condition to become truthy", {
  page <- local_waits_page()
  pz_js(page, "setTimeout(function () { window.__ready = true; }, 300)", await = FALSE)
  start <- Sys.time()
  res <- withVisible(pz_wait_for_js(page, "window.__ready === true", timeout = 5))
  expect_false(res$visible)
  expect_identical(res$value, page)
  # It waited for the timer, not just one poll.
  expect_gte(as.numeric(difftime(Sys.time(), start, units = "secs")), 0.25)
})

test_that("pz_wait_for_js applies JavaScript truthiness", {
  page <- local_waits_page()
  # A non-empty string and a non-zero number count in JS, not in R:
  # with R-side truthiness both would fail to pass inside 0.5 s.
  expect_no_error(pz_wait_for_js(page, "'still here'", timeout = 0.5))
  expect_no_error(pz_wait_for_js(page, "1 + 1", timeout = 0.5))
})

test_that("pz_wait_for_js awaits promises", {
  page <- local_waits_page()
  # The promise resolves in 200 ms, well inside the 2 s budget: an
  # unwaited promise would read as truthy immediately, a rejected one
  # as an error.
  expect_no_error(
    pz_wait_for_js(page, "new Promise((r) => setTimeout(() => r(2), 200))", timeout = 2)
  )
})

test_that("pz_wait_for_js times out with a classed error", {
  page <- local_waits_page()
  err <- expect_error(
    pz_wait_for_js(page, "false", timeout = 0.3),
    class = "paparazzi_error_timeout"
  )
  expect_match(
    conditionMessage(err),
    "Timed out after 0.3s waiting for JS condition false.",
    fixed = TRUE
  )
})

test_that("pz_wait_for_js validates its inputs", {
  page <- local_waits_page()
  expect_error(pz_wait_for_js(page, 1), "string")
  expect_error(pz_wait_for_js(page, "true", extra = 1), "empty")
  expect_error(pz_wait_for_js(1, "true"), class = "paparazzi_error_context")
  expect_error(pz_wait_for_js(page, "true", timeout = -1), "timeout")
})

test_that("pz_wait_for_stable waits for text to stop changing", {
  page <- local_waits_page()
  res <- withVisible(pz_wait_for_stable(page, target = "#ticker", for_ms = 300, timeout = 10))
  expect_false(res$visible)
  expect_identical(res$value, page)
  # Once stable, the settled text is there.
  pz_expect_text(page, "settled", target = "#ticker", match = "exact")
})

test_that("pz_wait_for_stable samples layout with prop = 'rect'", {
  page <- local_waits_page()
  # #bouncer animates its box for 1.2 s, then rests; the wait returns
  # only once the box has held still.
  expect_no_error(
    pz_wait_for_stable(page, target = "#bouncer", prop = "rect", for_ms = 300, timeout = 5)
  )
  rects <- pz_get_rect(page, target = "#bouncer")
  expect_equal(nrow(rects), 1)
  # At rest the box sits at the top of #anim-space, its stable slot.
  r2 <- pz_get_rect(page, target = "#bouncer")
  expect_identical(rects$y, r2$y)
})

test_that("pz_wait_for_stable times out while the page keeps changing", {
  page <- local_waits_page()
  err <- expect_error(
    pz_wait_for_stable(page, target = "#never-still", for_ms = 400, timeout = 0.5),
    class = "paparazzi_error_timeout"
  )
  expect_match(
    conditionMessage(err),
    "the page to be stable for 400ms",
    fixed = TRUE
  )
  expect_error(
    pz_wait_for_stable(page, target = "#endless", prop = "rect", for_ms = 400, timeout = 0.5),
    class = "paparazzi_error_timeout"
  )
})

test_that("pz_wait_for_stable accepts a context instead of a target", {
  page <- local_waits_page()
  ctx <- pz_find(page, "#ticker")
  ctx |> pz_wait_for_stable(for_ms = 300, timeout = 10)
  # target = NULL is the pinned set: #ticker itself.
  ctx |> pz_expect_text("settled", match = "exact")
})

test_that("pz_wait_for_stable samples any single property", {
  page <- local_state_page()
  pz_js(page, "document.getElementById('scroll-box').scrollTop = 50")
  pz_wait_for_stable(page, target = "#scroll-box", prop = "scrollTop", for_ms = 100, timeout = 5)
  # Once stable at 50, the property reads back as settled.
  pz_expect_js(page, "el => el.scrollTop === 50", target = "#scroll-box")
})

test_that("pz_wait_for_stable passes immediately on a static page and for_ms = 0", {
  page <- local_state_page()
  start <- Sys.time()
  # Nothing in state.html changes after load, and for_ms = 0 passes on
  # the first sample: both return well inside a second either way.
  expect_no_error(pz_wait_for_stable(page, for_ms = 200, timeout = 5))
  expect_no_error(pz_wait_for_stable(page, target = "#btn-one", for_ms = 0, timeout = 1))
  expect_lt(as.numeric(difftime(Sys.time(), start, units = "secs")), 2)
})

test_that("pz_wait_for_stable validates its inputs", {
  page <- local_waits_page()
  expect_error(pz_wait_for_stable(page, prop = "getBoundingClientRect()"), "single JavaScript property name")
  expect_error(pz_wait_for_stable(page, prop = "rect x"), "single JavaScript property name")
  expect_error(pz_wait_for_stable(page, for_ms = -1), "number")
  expect_error(pz_wait_for_stable(page, target = "#ticker", timeout = -1), "timeout")
  expect_error(pz_wait_for_stable(page, extra = 1), "empty")
})

test_that("pz_wait_for_navigation times out when nothing navigates", {
  page <- local_waits_page()
  start <- Sys.time()
  expect_error(
    pz_wait_for_navigation(page, timeout = 0.4),
    class = "paparazzi_error_timeout"
  )
  expect_lt(as.numeric(difftime(Sys.time(), start, units = "secs")), 3)
})

test_that("pz_wait_for_navigation waits for a pending navigation and resets scope", {
  page <- local_waits_page()
  ctx <- pz_find(page, "#nav-link")
  pz_js(page, "setTimeout(function () { location.href = 'nav-target.html'; }, 300)", await = FALSE)
  res <- withVisible(ctx |> pz_wait_for_navigation(timeout = 5))
  expect_false(res$visible)
  reset <- res$value
  expect_s3_class(reset, "PaparazziContext")
  expect_length(reset$scope, 0)
  expect_identical(reset$page, page)
  expect_match(pz_get_url(reset), "nav-target.html", fixed = TRUE)
  # The reset context works against the new page.
  reset |> pz_expect_text("You made it.", target = "#target-text", match = "exact")
  # The pre-navigation scope is dead: the navigation destroyed the
  # execution context its pins lived in, and the object group was
  # released, so the next use errors instead of acting on a stale set.
  # (Released-while-alive contexts raise the classed
  # paparazzi_error_detached, like the wait = "none" test below; the
  # dead-context CDP message is the scope seam in R/scope.R, left to
  # its task.)
  expect_error(ctx |> pz_expect_text("x", timeout = 0.1))
})

test_that("pz_wait_for_navigation follows a clicked link", {
  page <- local_waits_page()
  ctx <- pz_find(page, "#nav-link")
  reset <- ctx |> pz_click() |> pz_wait_for_navigation(timeout = 5)
  expect_length(reset$scope, 0)
  expect_match(pz_get_url(reset), "nav-target.html", fixed = TRUE)
  reset |> pz_expect_title("paparazzi navigation target", match = "exact")
})

test_that("pz_wait_for_navigation(wait = 'none') resets without waiting", {
  page <- local_waits_page()
  ctx <- pz_find(page, "#ticker")
  start <- Sys.time()
  reset <- pz_wait_for_navigation(ctx, wait = "none")
  expect_lt(as.numeric(difftime(Sys.time(), start, units = "secs")), 0.2)
  expect_length(reset$scope, 0)
  # The group was released even though nothing navigated.
  expect_error(
    ctx |> pz_expect_text("settled"),
    class = "paparazzi_error_detached"
  )
  # The page itself is untouched.
  page |> pz_expect_text("Go to the target page", target = "#nav-link", match = "exact")
})

test_that("pz_wait_for_navigation validates its inputs", {
  page <- local_waits_page()
  expect_error(pz_wait_for_navigation(page, wait = "shiny"), "auto")
  expect_error(pz_wait_for_navigation(page, extra = 1), "empty")
  expect_error(pz_wait_for_navigation(page, timeout = -1), "timeout")
})
