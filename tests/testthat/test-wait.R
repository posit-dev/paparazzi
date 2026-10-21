test_that("Shiny idle settles on a real app and returns its context invisibly", {
  skip_if_no_chrome()
  skip_if_no_shiny()
  page <- pz_open(shared_shiny_idle_app(), wait = "none")
  withr::defer(pz_close(page))

  # Output delivery does not anchor idle; the controlled busy/idle tests
  # below pin the hold's duration.
  page |> pz_expect_text("reactive ready", target = "#slow")

  result <- withVisible(pz_wait_for_shiny_idle(page, timeout = 5))
  expect_false(result$visible)
  expect_identical(result$value, page)
})

test_that("Shiny idle restarts its stability window when busy returns", {
  skip_if_no_chrome()
  skip_if_no_shiny()
  page <- pz_open(shared_shiny_idle_app(), wait = "shiny")
  withr::defer(pz_close(page))

  # start precedes the pz_evaluate so the 600ms pulse provably starts
  # after the reference. Busy is injected the way Shiny signals it: the
  # class and the jQuery event together. The class read catches the busy
  # state even though the shiny:busy event fires before the wait attaches
  # its listeners; the shiny:idle event re-triggers the hold.
  start <- Sys.time()
  pz_evaluate(
    page,
    "document.documentElement.classList.add('shiny-busy'); window.jQuery(document).trigger('shiny:busy'); setTimeout(() => { document.documentElement.classList.remove('shiny-busy'); window.jQuery(document).trigger('shiny:idle'); }, 600)"
  )
  pz_wait_for_shiny_idle(page, timeout = 3)
  expect_gte(as.numeric(difftime(Sys.time(), start, units = "secs")), 0.78)
})

test_that("Shiny idle does not wait on recalculating outputs", {
  skip_if_no_chrome()
  skip_if_no_shiny()
  page <- pz_open(shared_shiny_idle_app(), wait = "shiny")
  withr::defer(pz_close(page))

  # A stuck .recalculating class is a per-output state the wait no longer
  # inspects (suspended outputs on hidden tabs keep it indefinitely), so
  # it neither blocks nor extends the wait.
  pz_evaluate(
    page,
    "document.querySelector('#slow').classList.add('recalculating')"
  )
  start <- Sys.time()
  pz_wait_for_shiny_idle(page, timeout = 3)
  expect_lt(as.numeric(difftime(Sys.time(), start, units = "secs")), 1)
  pz_evaluate(
    page,
    "document.querySelector('#slow').classList.remove('recalculating')"
  )
})

test_that("Shiny idle restarts the hold when busy returns mid-window", {
  skip_if_no_chrome()
  skip_if_no_shiny()
  page <- pz_open(shared_shiny_idle_app(), wait = "shiny")
  withr::defer(pz_close(page))

  pz_evaluate(
    page,
    "setTimeout(() => { document.documentElement.classList.add('shiny-busy'); window.jQuery(document).trigger('shiny:busy'); }, 100); setTimeout(() => { document.documentElement.classList.remove('shiny-busy'); window.jQuery(document).trigger('shiny:idle'); }, 360)"
  )

  start <- Sys.time()
  pz_wait_for_shiny_idle(page, timeout = 3)
  expect_gte(as.numeric(difftime(Sys.time(), start, units = "secs")), 0.5)
})

test_that("Shiny idle counts brief busy pulses inside the hold", {
  skip_if_no_chrome()
  skip_if_no_shiny()
  page <- pz_open(shared_shiny_idle_app(), wait = "shiny")
  withr::defer(pz_close(page))

  # A 50ms busy pulse lands entirely inside the 200ms hold, injected the
  # way Shiny signals it (class plus event at both ends). The shiny:busy
  # event must cancel the hold and shiny:idle restart it, so the wait
  # resolves about 200ms after the pulse ends, not at the original hold.
  pz_evaluate(
    page,
    r"[
window.__idlePulseEnd = null;
setTimeout(() => {
  document.documentElement.classList.add('shiny-busy');
  window.jQuery(document).trigger('shiny:busy');
}, 50);
setTimeout(() => {
  document.documentElement.classList.remove('shiny-busy');
  window.jQuery(document).trigger('shiny:idle');
  window.__idlePulseEnd = performance.now();
}, 100);
]"
  )
  pz_wait_for_shiny_idle(page, timeout = 3)

  expect_true(pz_evaluate(page, "window.__idlePulseEnd !== null"))
  # Reading the lag after the wait returns only inflates it, so the bound
  # is safe; the 10ms margin covers timer granularity.
  lag <- pz_evaluate(page, "performance.now() - window.__idlePulseEnd")
  expect_gte(lag, 190)
})

test_that("Shiny idle resets the hold on Shiny connection events", {
  skip_if_no_chrome()
  skip_if_no_shiny()
  page <- pz_open(shared_shiny_idle_app(), wait = "shiny")
  withr::defer(pz_close(page))

  pz_evaluate(
    page,
    r"[
window.__idleEventEnd = null;
setTimeout(() => window.jQuery(document).trigger('shiny:disconnected'), 50);
setTimeout(() => {
  window.jQuery(document).trigger('shiny:connected');
  window.__idleEventEnd = performance.now();
}, 100);
]"
  )

  pz_wait_for_shiny_idle(page, timeout = 3)
  expect_true(pz_evaluate(page, "window.__idleEventEnd !== null"))
  # Reading the lag after the wait returns only inflates it, so the bound
  # is safe; the 10ms margin covers timer granularity.
  expect_gte(
    pz_evaluate(page, "performance.now() - window.__idleEventEnd"),
    190
  )
})

test_that("Shiny idle settles with a suspended output on a hidden tab", {
  skip_if_no_chrome()
  skip_if_no_shiny()
  page <- pz_local_page(
    shared_shiny_suspended_app(),
    wait = "shiny",
    timeout = 10
  )

  # Arrange visible delivery; the hidden output stays recalculating.
  page |> pz_expect_text("fast ready", target = "#fast")
  state <- pz_evaluate(
    page,
    "({fast: document.querySelector('#fast').className, slow: document.querySelector('#slow').className})"
  )
  expect_false(grepl("recalculating", state$fast, fixed = TRUE))
  expect_true(grepl("recalculating", state$slow, fixed = TRUE))

  # Recheck after delivery so an early startup settle cannot satisfy this
  # regression.
  expect_no_error(pz_wait_for_shiny_idle(page, timeout = 5))
  expect_true(pz_evaluate(
    page,
    "document.querySelector('#slow').classList.contains('recalculating')"
  ))

  shot <- tempfile(fileext = ".png")
  pz_screenshot(page, shot)
  expect_true(file.exists(shot))
})

test_that("Shiny idle and wait=TRUE setters work after invalidating a suspended output", {
  skip_if_no_chrome()
  skip_if_no_shiny()
  page <- pz_local_page(
    shared_shiny_suspended_app(),
    wait = "shiny",
    timeout = 10
  )

  # Invalidating while the tab is hidden sticks .recalculating on the
  # suspended output; idle still settles (the recording idiom).
  page |>
    pz_act_click("#go") |>
    pz_wait_for_shiny_idle(timeout = 5)
  expect_true(pz_evaluate(
    page,
    "document.querySelector('#slow').classList.contains('recalculating')"
  ))

  # Showing the tab resumes rendering. The setter waits for idle;
  # expect delivered text separately.
  page |>
    pz_set_shiny_input("tabs", "Slow") |>
    pz_expect_text("slow ready", target = "#slow")
  # Delivery and the class clear happen in the same message processing.
  expect_false(pz_evaluate(
    page,
    "document.querySelector('#slow').classList.contains('recalculating')"
  ))
})

test_that("Shiny idle settles after a suspended output resumes", {
  skip_if_no_chrome()
  skip_if_no_shiny()
  page <- pz_local_page(
    shared_shiny_suspended_app(),
    wait = "shiny",
    timeout = 10
  )

  page |> pz_set_shiny_input("tabs", "Slow", wait = FALSE)
  # Observe server busy first; input dispatch may outlast an idle hold.
  # Controlled busy/idle tests pin the hold; expect delivery separately.
  pz_wait_for_js(
    page,
    "document.documentElement.classList.contains('shiny-busy')",
    timeout = 5
  )
  pz_wait_for_shiny_idle(page, timeout = 5)
  page |> pz_expect_text("slow ready", target = "#slow")
})

test_that("Shiny idle settles for a Shiny for Python app with a suspended tab output", {
  skip_if_no_chrome()
  skip_if_no_py_shiny()
  app <- serve_py_shiny(test_path("fixtures", "shiny-suspended-py", "app.py"))
  withr::defer(app$stop())

  page <- pz_open(app, timeout = 15)
  withr::defer(pz_close(page))

  # As in R, arrange delivery before testing the suspended-output state.
  page |> pz_expect_text("fast ready", target = "#fast")
  state <- pz_evaluate(
    page,
    "({fast: document.querySelector('#fast').className, slow: document.querySelector('#slow').className})"
  )
  expect_false(grepl("recalculating", state$fast, fixed = TRUE))
  expect_true(grepl("recalculating", state$slow, fixed = TRUE))

  # Recheck after delivery to exclude an early startup settle.
  expect_no_error(pz_wait_for_shiny_idle(page, timeout = 5))
  expect_true(pz_evaluate(
    page,
    "document.querySelector('#slow').classList.contains('recalculating')"
  ))

  page |>
    pz_act_click("#go") |>
    pz_wait_for_shiny_idle(timeout = 5) |>
    pz_set_shiny_input("tabs", "Slow") |>
    pz_expect_text("slow ready", target = "#slow")
  # Delivery and the class clear happen in the same message processing.
  expect_false(pz_evaluate(
    page,
    "document.querySelector('#slow').classList.contains('recalculating')"
  ))
})

test_that("Shiny idle deadline cleans page listeners", {
  skip_if_no_chrome()
  skip_if_no_shiny()
  page <- pz_open(shared_shiny_idle_app(), wait = "shiny")
  withr::defer(pz_close(page))

  listeners <- r"[
['shiny:connected', 'shiny:disconnected', 'shiny:busy', 'shiny:idle']
  .map((event) => (window.jQuery._data(document, 'events')?.[event] || []).length)
]"
  before <- pz_evaluate(page, listeners)

  pz_evaluate(page, "document.documentElement.classList.add('shiny-busy')")
  withr::defer(pz_evaluate(
    page,
    "document.documentElement.classList.remove('shiny-busy')"
  ))

  original_js <- pz_evaluate
  # The fixture is already loaded; exercise the browser deadline, not preflight.
  with_mocked_bindings(
    {
      expect_error(
        pz_wait_for_shiny_idle(page, timeout = 0.35),
        "Shiny idle",
        class = "paparazzi_error_timeout"
      )
    },
    wait_for_load = function(...) invisible(NULL),
    pz_evaluate = function(ctx, expr, ...) {
      if (identical(expr, "!!window.Shiny")) {
        return(TRUE)
      }
      original_js(ctx, expr, ...)
    }
  )

  expect_identical(pz_evaluate(page, listeners), before)
  pz_evaluate(page, "document.documentElement.classList.remove('shiny-busy')")
  expect_no_error(pz_wait_for_shiny_idle(page, timeout = 2))
})

test_that("Shiny idle waits for a late shinyapp after the Shiny global loads", {
  skip_if_no_chrome()
  page <- local_page(test_path("fixtures", "shiny-late-init.html"))

  pz_evaluate(
    page,
    r"[
setTimeout(() => {
  Shiny.shinyapp = { $socket: { readyState: WebSocket.OPEN } };
  document.dispatchEvent(new Event('shiny:connected'));
}, 150)
]"
  )

  expect_no_error(pz_wait_for_shiny_idle(page, timeout = 2))
  expect_true(pz_evaluate(page, "!!Shiny.shinyapp"))
})

test_that("Shiny global without an app times out waiting for idle", {
  skip_if_no_chrome()
  page <- local_page(test_path("fixtures", "shiny-late-init.html"))
  expect_error(
    pz_wait_for_shiny_idle(page, timeout = 0.35),
    "Timed out.*waiting for Shiny idle",
    class = "paparazzi_error_timeout"
  )
})

test_that("Shiny idle on non-Shiny pages fails clearly", {
  page <- local_waits_page()

  expect_error(
    pz_wait_for_shiny_idle(page, timeout = 1),
    "not a Shiny page",
    class = "paparazzi_error_unsupported"
  )
  expect_error(pz_wait_for_shiny_idle(page, extra = 1), "empty")
  expect_error(pz_wait_for_shiny_idle(page, timeout = -1), "timeout")
})

test_that("Shiny idle times out while the page remains busy", {
  skip_if_no_chrome()
  skip_if_no_shiny()
  page <- pz_open(shared_shiny_idle_app(), wait = "shiny")
  withr::defer(pz_close(page))

  pz_evaluate(page, "document.documentElement.classList.add('shiny-busy')")

  expect_error(
    pz_wait_for_shiny_idle(page, timeout = 0.35),
    "Shiny idle",
    class = "paparazzi_error_timeout"
  )
})

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

test_that("pz_poll appends detail lines to its timeout error", {
  loop <- later::create_loop()
  withr::defer(later::destroy_loop(loop))

  err <- expect_error(
    pz_poll(
      function() FALSE,
      timeout = 0.2,
      loop = loop,
      what = "never",
      detail = function() c("first detail", "second detail with {braces}")
    ),
    class = "paparazzi_error_timeout"
  )
  msg <- conditionMessage(err)
  expect_match(msg, "first detail", fixed = TRUE)
  # Literal braces in detail text are escaped before cli interpolation.
  expect_match(msg, "second detail with {braces}", fixed = TRUE)
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

  pz_evaluate(
    page,
    "setTimeout(function () { window.__ready = true; }, 300)",
    await = FALSE
  )

  start <- Sys.time()
  res <- withVisible(pz_wait_for_js(
    page,
    "window.__ready === true",
    timeout = 5
  ))
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
    pz_wait_for_js(
      page,
      "new Promise((r) => setTimeout(() => r(2), 200))",
      timeout = 2
    )
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

  res <- withVisible(pz_wait_for_stable(
    page,
    target = "#ticker",
    for_ms = 300,
    timeout = 10
  ))
  expect_false(res$visible)
  expect_identical(res$value, page)

  # Once stable, the settled text is there.
  pz_expect_text(page, "settled", target = "#ticker")
})

test_that("pz_wait_for_stable samples layout with prop = 'rect'", {
  page <- local_waits_page()

  # #bouncer animates its box for 1.2 s, then rests; the wait returns
  # only once the box has held still.
  expect_no_error(
    pz_wait_for_stable(
      page,
      target = "#bouncer",
      prop = "rect",
      for_ms = 300,
      timeout = 5
    )
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
    pz_wait_for_stable(
      page,
      target = "#never-still",
      for_ms = 400,
      timeout = 0.5
    ),
    class = "paparazzi_error_timeout"
  )
  expect_match(
    conditionMessage(err),
    "the page to be stable for 400ms",
    fixed = TRUE
  )

  expect_error(
    pz_wait_for_stable(
      page,
      target = "#endless",
      prop = "rect",
      for_ms = 400,
      timeout = 0.5
    ),
    class = "paparazzi_error_timeout"
  )
})

test_that("pz_wait_for_stable accepts a context instead of a target", {
  page <- local_waits_page()
  ctx <- pz_find(page, "#ticker")

  ctx |> pz_wait_for_stable(for_ms = 300, timeout = 10)
  # target = NULL is the pinned set: #ticker itself.
  ctx |> pz_expect_text("settled")
})

test_that("pz_wait_for_stable samples any single property", {
  page <- local_state_page()

  pz_evaluate(page, "document.getElementById('scroll-box').scrollTop = 50")
  pz_wait_for_stable(
    page,
    target = "#scroll-box",
    prop = "scrollTop",
    for_ms = 100,
    timeout = 5
  )

  # Once stable at 50, the property reads back as settled.
  pz_expect_js(page, "el => el.scrollTop === 50", target = "#scroll-box")
})

test_that("pz_wait_for_stable passes immediately on a static page and for_ms = 0", {
  page <- local_state_page()
  start <- Sys.time()

  # Nothing in state.html changes after load, and for_ms = 0 passes on
  # the first sample: both return well inside a second either way.
  expect_no_error(pz_wait_for_stable(page, for_ms = 200, timeout = 5))
  expect_no_error(pz_wait_for_stable(
    page,
    target = "#btn-one",
    for_ms = 0,
    timeout = 1
  ))
  expect_lt(as.numeric(difftime(Sys.time(), start, units = "secs")), 2)
})

test_that("pz_wait_for_stable keeps the locator and stability budgets separate", {
  page <- local_waits_page()

  # The target appears 0.6s into the 1s locator timeout. With the
  # budgets shared, only 0.4s would remain -- less than the 500ms
  # window -- and the wait would false-timeout; the stability loop
  # gets its own full budget, so the window completes.
  pz_evaluate(
    page,
    r"[
setTimeout(function() {
  const lateStableEl = document.createElement('p');
  lateStableEl.id = 'late-stable';
  lateStableEl.textContent = 'steady text';
  document.body.appendChild(lateStableEl);
}, 600)
]",
    await = FALSE
  )

  start <- Sys.time()
  expect_no_error(
    pz_wait_for_stable(page, target = "#late-stable", for_ms = 500, timeout = 1)
  )

  # The resolve (~0.6s) plus the full 500ms window, both inside the
  # 1s stability budget.
  elapsed <- as.numeric(difftime(Sys.time(), start, units = "secs"))
  expect_gte(elapsed, 1)
  expect_lt(elapsed, 3)
})

test_that("pz_wait_for_stable validates its inputs", {
  page <- local_waits_page()

  expect_error(
    pz_wait_for_stable(page, prop = "getBoundingClientRect()"),
    "single JavaScript property name"
  )
  expect_error(
    pz_wait_for_stable(page, prop = "rect x"),
    "single JavaScript property name"
  )
  expect_error(pz_wait_for_stable(page, for_ms = -1), "number")
  expect_error(
    pz_wait_for_stable(page, target = "#ticker", timeout = -1),
    "timeout"
  )
  expect_error(pz_wait_for_stable(page, extra = 1), "empty")
})

test_that("pz_wait_for_navigation times out when nothing navigates", {
  page <- local_waits_page()

  # The timeout clears the 0.5s settle window: the page is complete
  # and settled from the start, so without the navigation-evidence
  # requirement the wait would pass; instead it must time out with
  # the navigation-specific message.
  start <- Sys.time()
  err <- expect_error(
    pz_wait_for_navigation(page, timeout = 1.2),
    class = "paparazzi_error_timeout"
  )
  expect_match(
    conditionMessage(err),
    "Timed out after 1.2s waiting for the navigation to complete.",
    fixed = TRUE
  )

  elapsed <- as.numeric(difftime(Sys.time(), start, units = "secs"))
  expect_gte(elapsed, 1)
  expect_lt(elapsed, 5)
})

test_that("a completed link navigation is caught once after the click", {
  page <- local_nav_page()

  clicked <- pz_act_click(page, "#fast-link")
  # Ensure the new document has already completed before starting the wait.
  clicked |>
    pz_expect_text("B", target = "#page") |>
    pz_wait_for_js("document.readyState === 'complete'")

  reset <- pz_wait_for_navigation(clicked, timeout = 2)
  expect_length(reset$scope, 0)
  expect_match(pz_get_url(reset), "nav-b.html", fixed = TRUE)

  expect_error(
    pz_wait_for_navigation(reset, timeout = 0.8),
    class = "paparazzi_error_timeout"
  )
})

test_that("nav settle restarts its hold when the main-frame loader changes", {
  states <- list(
    list(loader = "old", js = "[true,2]"),
    list(loader = "new", js = "[true,2]"),
    list(loader = "new", js = "[false,3]"),
    list(loader = "new", js = "[true,3]"),
    list(loader = "new", js = "[true,3]")
  )
  index <- 0L
  frame_timeouts <- list()
  ctx <- list(
    page = list(
      child_loop = NULL,
      session = list(
        Page = list(getFrameTree = function(timeout_ = NULL) {
          frame_timeouts[[length(frame_timeouts) + 1L]] <<- timeout_
          list(
            frameTree = list(frame = list(loaderId = states[[index]]$loader))
          )
        })
      )
    )
  )
  local_mocked_bindings(
    pz_evaluate = function(...) states[[index]]$js,
    pz_poll = function(fn, ...) {
      for (i in seq_len(4)) {
        index <<- i
        expect_false(fn(), info = paste("sample", i, "must not settle"))
        Sys.sleep(0.02)
      }
      index <<- 5L
      expect_true(fn())
    }
  )

  nav_settle(
    ctx,
    settle = 0.005,
    timeout = 1,
    snapshot = list(complete = TRUE, origin = 2),
    action_loader = "old"
  )
  expect_identical(frame_timeouts, rep(list(1), 5))
})

test_that("nav_settle timeout reports the last read against the snapshot", {
  loop <- later::create_loop()
  withr::defer(later::destroy_loop(loop))
  ctx <- list(
    page = list(
      child_loop = loop,
      session = list(
        Page = list(
          getFrameTree = function(timeout_ = NULL) {
            list(frameTree = list(frame = list(loaderId = "old")))
          }
        )
      )
    )
  )
  local_mocked_bindings(pz_evaluate = function(...) "[true,3.5]")

  err <- expect_error(
    nav_settle(
      ctx,
      settle = 0.005,
      timeout = 0.2,
      # Whole numbers parse as integer and fail identical() against a
      # double snapshot; fractional timeOrigins match real page reads.
      snapshot = list(complete = TRUE, origin = 3.5)
    ),
    class = "paparazzi_error_timeout"
  )
  msg <- conditionMessage(err)
  expect_match(msg, "Last good read: readyState", fixed = TRUE)
  expect_match(msg, "loaderId", fixed = TRUE)
  expect_match(msg, "Pre-action snapshot: complete=TRUE", fixed = TRUE)
  expect_match(
    msg,
    "Unmet at timeout: navigation never detected",
    fixed = TRUE
  )
})

test_that("nav_settle timeout keeps the last good read when later reads fail", {
  loop <- later::create_loop()
  withr::defer(later::destroy_loop(loop))
  ctx <- list(
    page = list(
      child_loop = loop,
      session = list(
        Page = list(
          getFrameTree = function(timeout_ = NULL) {
            list(frameTree = list(frame = list(loaderId = "old")))
          }
        )
      )
    )
  )
  reads <- 0L
  local_mocked_bindings(
    pz_evaluate = function(...) {
      reads <<- reads + 1L
      if (reads > 2L) {
        stop("Execution context was destroyed")
      }
      "[true,3.5]"
    }
  )

  err <- expect_error(
    nav_settle(
      ctx,
      settle = 0.005,
      timeout = 0.4,
      snapshot = list(complete = TRUE, origin = 3.5)
    ),
    class = "paparazzi_error_timeout"
  )
  msg <- conditionMessage(err)
  expect_match(msg, "Last good read: readyState", fixed = TRUE)
  expect_match(msg, "final read before the timeout failed", fixed = TRUE)
  expect_false(grepl("Every read failed", msg, fixed = TRUE))
})

test_that("nav_settle_detail covers reads that never succeed", {
  expect_match(
    nav_settle_detail(
      NULL,
      read_failed = TRUE,
      stable_for = NULL,
      settle = 0.5,
      snapshot = list(complete = FALSE, origin = NULL),
      action_loader = NULL
    ),
    "mid-navigation for the whole timeout",
    fixed = TRUE
  )
})

test_that("nav_snapshot propagates closed-page and JavaScript errors", {
  failure <- NULL
  local_mocked_bindings(pz_evaluate = function(...) stop(failure))

  for (class in c("paparazzi_error_closed", "paparazzi_error_js")) {
    failure <- rlang::error_cnd(class, message = class)
    expect_error(nav_snapshot(NULL, 1), class = class)
  }
})

test_that("nav_snapshot treats a chromote swap error as in-flight", {
  local_mocked_bindings(pz_evaluate = function(...) {
    stop("Execution context was destroyed")
  })

  expect_identical(
    nav_snapshot(NULL, 1),
    list(complete = FALSE, origin = NULL)
  )
})

test_that("a completed bfcache restore is caught once after history.back()", {
  skip_if_no_chrome()
  testthat::skip_if_not_installed("httpuv")
  server <- pz_serve_static(test_path("fixtures", "nav-cache"))
  withr::defer(server$stop())
  page <- local_page(paste0(server$url, "a.html"))
  identity <- pz_evaluate(page, "window.identity")
  origin <- pz_evaluate(page, "performance.timeOrigin")

  pz_act_click(page, "#next")
  pz_wait_for_js(
    page,
    "document.readyState === 'complete' && !!document.querySelector('#back')"
  )

  back <- pz_find(page, "#back")
  pz_act_click(back)
  pz_wait_for_js(
    page,
    "document.readyState === 'complete' && !!document.querySelector('#next') && window.shows.includes(true)"
  )

  expect_identical(pz_evaluate(page, "window.identity"), identity)
  expect_identical(pz_evaluate(page, "performance.timeOrigin"), origin)
  expect_identical(
    pz_evaluate(page, "window.shows[window.shows.length - 1]"),
    TRUE
  )

  reset <- pz_wait_for_navigation(back, timeout = 2)
  expect_length(reset$scope, 0)
  expect_match(pz_get_url(reset), "/a.html", fixed = TRUE)

  expect_error(
    pz_wait_for_navigation(reset, timeout = 0.8),
    class = "paparazzi_error_timeout"
  )
})

test_that("a non-navigating action does not satisfy the navigation wait", {
  page <- local_nav_page()

  pz_act_click(page, "#scope-target")
  expect_error(
    pz_wait_for_navigation(page, timeout = 0.8),
    class = "paparazzi_error_timeout"
  )
})

test_that("pz_wait_for_navigation catches a navigation that starts after the wait", {
  page <- local_waits_page()

  # The redirect fires 100ms in: after the wait starts, well inside
  # its timeout, so the new document's timeOrigin is positive
  # evidence and the wait follows it out.
  pz_evaluate(
    page,
    "setTimeout(function () { location.href = 'nav-target.html'; }, 100)",
    await = FALSE
  )

  reset <- pz_wait_for_navigation(page, timeout = 5)
  expect_length(reset$scope, 0)
  expect_match(pz_get_url(reset), "nav-target.html", fixed = TRUE)
})

test_that("pz_wait_for_navigation waits for a pending navigation and resets scope", {
  page <- local_waits_page()
  ctx <- pz_find(page, "#nav-link")

  pz_evaluate(
    page,
    "setTimeout(function () { location.href = 'nav-target.html'; }, 300)",
    await = FALSE
  )

  res <- withVisible(ctx |> pz_wait_for_navigation(timeout = 5))
  expect_false(res$visible)
  reset <- res$value
  expect_s3_class(reset, "PaparazziContext")
  expect_length(reset$scope, 0)
  expect_identical(reset$page, page)
  expect_match(pz_get_url(reset), "nav-target.html", fixed = TRUE)

  # The reset context works against the new page.
  reset |>
    pz_expect_text("You made it.", target = "#target-text")

  # The pre-navigation scope is dead: the navigation destroyed the
  # execution context its pins lived in, and the object group was
  # released, so the next use raises the classed detach error -- not
  # the raw dead-context CDP error -- instead of acting on a stale
  # set.
  expect_error(
    ctx |> pz_expect_text("x", timeout = 0.1),
    class = "paparazzi_error_detached"
  )
})

test_that("pz_wait_for_navigation follows a clicked link", {
  page <- local_waits_page()
  ctx <- pz_find(page, "#nav-link")

  reset <- ctx |> pz_act_click() |> pz_wait_for_navigation(timeout = 5)
  expect_length(reset$scope, 0)
  expect_match(pz_get_url(reset), "nav-target.html", fixed = TRUE)
  reset |> pz_expect_title("paparazzi navigation target")

  # The same dead-scope verdict on the click-driven navigation: the
  # old pinned set's context is gone, and its next use maps to the
  # classed detach error rather than a raw chromote one.
  expect_error(
    ctx |> pz_get_text(),
    class = "paparazzi_error_detached"
  )
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
  page |>
    pz_expect_text(
      "Go to the target page",
      target = "#nav-link"
    )
})

test_that("pz_wait_for_navigation validates its inputs", {
  page <- local_waits_page()

  expect_error(pz_wait_for_navigation(page, extra = 1), "empty")
  expect_error(pz_wait_for_navigation(page, timeout = -1), "timeout")
})

test_that("explicit post-action navigation routes to Shiny idle on the destination", {
  app <- local_shiny_app(shiny_idle_fixture())
  page <- local_nav_page()
  spy <- local_shiny_idle_spy()

  pz_evaluate(
    page,
    sprintf(
      r"[
setTimeout(() => location.href = '%s', 100)
]",
      app$url
    ),
    await = FALSE
  )

  pz_wait_for_navigation(page, wait = "shiny", timeout = 5)
  expect_identical(spy$urls, app$url)
  page |> pz_expect_text("reactive ready", target = "#slow")
})

test_that("post-action auto waits for app-backed Shiny but not a different origin", {
  skip_if_no_shiny()
  app <- shared_shiny_idle_app()
  page <- pz_open(app, wait = "shiny")
  withr::defer(pz_close(page))
  spy <- local_shiny_idle_spy()

  pz_evaluate(page, "setTimeout(() => location.reload(), 100)", await = FALSE)
  pz_wait_for_navigation(page, timeout = 5)
  expect_identical(spy$urls, app$url)
  page |> pz_expect_text("reactive ready", target = "#slow")

  pz_evaluate(
    page,
    "setTimeout(() => location.href = 'about:blank', 100)",
    await = FALSE
  )
  pz_wait_for_navigation(page, timeout = 5)
  expect_identical(pz_evaluate(page, "location.href"), "about:blank")
  expect_identical(spy$urls, app$url)
})
