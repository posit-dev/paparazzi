js <- function(ctx, expr) {
  pz_js(ctx, expr)
}

test_that("pz_nav_goto navigates and returns the root context", {
  ctx <- local_nav_page()
  expect_identical(pz_js(ctx, "document.title"), "paparazzi nav A")

  root <- pz_nav_goto(ctx, nav_fixture_url("b"))
  expect_s3_class(root, "PaparazziContext")
  # At root, the returned context is the page itself.
  expect_identical(root, ctx)
  expect_equal(length(root$scope), 0L)
  expect_identical(pz_js(root, "document.title"), "paparazzi nav B")
  expect_match(pz_js(root, "location.href"), "nav-b\\.html$")

  expect_invisible(pz_nav_goto(root, nav_fixture_url("a")))
})

test_that("pz_nav_reload restores the page", {
  ctx <- local_nav_page()
  pz_js(ctx, "document.body.appendChild(document.createElement('div')).id = 'added'")
  expect_equal(js(ctx, "document.querySelectorAll('#added').length"), 1)

  root <- pz_nav_reload(ctx)
  expect_identical(pz_js(root, "document.title"), "paparazzi nav A")
  expect_equal(js(root, "document.querySelectorAll('#added').length"), 0)
})

test_that("pz_nav_goto waits for a delayed destination to settle", {
  # nav-slow.html keeps readyState below "complete" for well past a
  # poll interval; the wait must settle on the destination document,
  # not on the outgoing page's still-complete readyState.
  ctx <- local_nav_page()
  root <- pz_nav_goto(ctx, nav_fixture_url("slow"))
  expect_identical(pz_js(root, "document.title"), "paparazzi nav slow")
  expect_identical(pz_js(root, "document.readyState"), "complete")
})

test_that("pz_nav_goto handles a same-document fragment navigation", {
  ctx <- local_nav_page()
  # A fragment navigation commits no new document, so no
  # frameNavigated ever fires; the wait must not wait on one.
  root <- pz_nav_goto(ctx, paste0(nav_fixture_url("a"), "#page"))
  expect_match(pz_js(root, "location.hash"), "#page", fixed = TRUE)
  expect_identical(pz_js(root, "document.title"), "paparazzi nav A")
  # ...while a full navigation to the same URL anchor-less still works.
  expect_no_error(pz_nav_goto(root, nav_fixture_url("b")))
})

test_that("history traversal works: goto, back, forward", {
  ctx <- local_nav_page()

  ctx <- pz_nav_goto(ctx, nav_fixture_url("b"))
  expect_identical(pz_js(ctx, "document.title"), "paparazzi nav B")

  ctx <- pz_nav_back(ctx)
  expect_identical(pz_js(ctx, "document.title"), "paparazzi nav A")

  ctx <- pz_nav_forward(ctx)
  expect_identical(pz_js(ctx, "document.title"), "paparazzi nav B")
})

test_that("back at the history start is a no-op", {
  ctx <- local_nav_page()
  root <- pz_nav_back(ctx)
  expect_identical(pz_js(root, "document.title"), "paparazzi nav A")
  expect_equal(length(root$scope), 0L)
})

test_that("navigation resets scope and releases pinned objects", {
  ctx <- local_nav_page()
  scoped <- pz_find(ctx, "#scope-target")
  expect_equal(length(scoped$scope), 1L)

  root <- pz_nav_goto(scoped, nav_fixture_url("b"))
  # The returned context is at the root...
  expect_equal(length(root$scope), 0L)
  expect_no_error(pz_find(root, "#scope-target"))
  # ...while the pre-nav scoped context is dead: its pins were released.
  expect_error(pz_click(scoped), class = "paparazzi_error_detached")
  expect_error(pz_find_first(scoped), class = "paparazzi_error_detached")
})

test_that("pz_nav_reload and back/forward also reset scope", {
  ctx <- local_nav_page()
  scoped <- pz_find(ctx, "#scope-target")

  root <- pz_nav_reload(scoped)
  expect_equal(length(root$scope), 0L)
  expect_error(pz_click(scoped), class = "paparazzi_error_detached")

  scoped2 <- pz_find(root, "#scope-target")
  expect_equal(length(scoped2$scope), 1L)
  root2 <- pz_nav_back(scoped2)
  expect_equal(length(root2$scope), 0L)
  expect_error(pz_click(scoped2), class = "paparazzi_error_detached")

  # The page itself (already at root) is returned unchanged.
  expect_identical(pz_nav_forward(root2), root2)
})

test_that("pz_nav_goto fails cleanly on navigation errors", {
  ctx <- local_nav_page()
  expect_error(
    pz_nav_goto(ctx, "file:///nonexistent-paparazzi-fixture.html"),
    class = "paparazzi_error_navigation"
  )
})

test_that("nav functions validate their inputs", {
  ctx <- local_nav_page()

  expect_error(pz_nav_goto(42, "about:blank"), class = "paparazzi_error_context")
  expect_error(pz_nav_reload(42), class = "paparazzi_error_context")
  expect_error(pz_nav_back(42), class = "paparazzi_error_context")
  expect_error(pz_nav_forward(42), class = "paparazzi_error_context")

  expect_error(pz_nav_goto(ctx, 42), regexp = "single string")
  expect_error(pz_nav_goto(ctx, "about:blank", bogus = 1), class = "rlib_error_dots_nonempty")

  expect_error(
    pz_nav_goto(ctx, "about:blank", wait = "eternal"),
    regexp = "must be one of"
  )
})

test_that("wait = 'none' returns without settling", {
  ctx <- local_nav_page()
  expect_no_error(pz_nav_goto(ctx, nav_fixture_url("b"), wait = "none"))
  expect_no_error(pz_nav_reload(ctx, wait = "none"))
  expect_no_error(pz_nav_back(ctx))
  expect_no_error(pz_nav_forward(ctx))
})

test_that("nav functions return their context invisibly", {
  ctx <- local_nav_page()
  expect_invisible(pz_nav_goto(ctx, nav_fixture_url("b")))
  expect_invisible(pz_nav_reload(ctx))
  expect_invisible(pz_nav_back(ctx))
  expect_invisible(pz_nav_forward(ctx))
})

test_that("nav_await settles a promise that resolved before the wait", {
  ctx <- local_nav_page()
  # Under load the anchor event can be dispatched (and its promise
  # resolved) while the trigger command's own synchronize is still
  # pumping, i.e. before nav_await() runs. then() on an already-settled
  # promise queues the callback on the current loop; unless nav_await
  # pins it to the page's child loop -- the only loop pz_poll() pumps --
  # the callback never runs and every such wait times out.
  p <- promises::promise_resolve(TRUE)
  expect_no_error(nav_await(ctx$page, p, "a pre-settled promise"))

  p <- promises::promise_reject("boom")
  expect_error(
    nav_await(ctx$page, p, "a pre-settled promise"),
    "boom",
    class = "simpleError"
  )
})

test_that("explicit shiny navigation waits for reactive output", {
  app <- local_shiny_app(shiny_idle_fixture())
  page <- local_nav_page()
  pz_nav_goto(page, app$url, wait = "shiny")
  expect_identical(shiny_idle_state(page)$text, "reactive ready")
  pz_nav_reload(page, wait = "shiny")
  expect_identical(shiny_idle_state(page)$text, "reactive ready")
})

test_that("app-backed auto waits for Shiny only on its own origin", {
  skip_if_no_shiny()
  page <- pz_open(shiny_idle_fixture(), wait = "shiny")
  withr::defer(pz_close(page))
  pz_nav_reload(page)
  expect_identical(shiny_idle_state(page)$text, "reactive ready")
  pz_nav_goto(page, pz_get_url(page))
  expect_identical(shiny_idle_state(page)$text, "reactive ready")

  app_url <- pz_get_url(page)
  pz_nav_goto(page, nav_fixture_url("b"))
  expect_identical(pz_js(page, "document.title"), "paparazzi nav B")
  pz_nav_goto(page, app_url)
  pz_nav_back(page)
  expect_identical(pz_js(page, "document.title"), "paparazzi nav B")
})

test_that("plain-URL pages use load even when navigating to an app URL", {
  app <- local_shiny_app(shiny_idle_fixture())
  page <- local_nav_page()
  pz_nav_goto(page, app$url)
  expect_identical(pz_js(page, "document.readyState"), "complete")
  pz_js(page, "document.documentElement.classList.add('shiny-busy')")
  pz_nav_goto(page, paste0(app$url, "#plain"))
  expect_true(pz_js(page, "document.documentElement.classList.contains('shiny-busy')"))
  pz_nav_reload(page)
  expect_identical(pz_js(page, "document.readyState"), "complete")
})

test_that("shared app handle uses Shiny auto on its origin", {
  app <- local_shiny_app(shiny_idle_fixture())
  page <- pz_open(app, wait = "shiny")
  withr::defer(pz_close(page))
  pz_nav_reload(page)
  expect_identical(shiny_idle_state(page)$text, "reactive ready")
})
