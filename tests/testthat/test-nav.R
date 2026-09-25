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
    pz_nav_goto(ctx, "about:blank", wait = "shiny"),
    class = "paparazzi_error_unsupported"
  )
  expect_error(
    pz_nav_reload(ctx, wait = "shiny"),
    class = "paparazzi_error_unsupported"
  )
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
