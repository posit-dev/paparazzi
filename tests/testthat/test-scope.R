# The id of every element in a set: a stable, whitespace-free way to
# assert *which* elements a scope holds.
scope_ids <- function(els) {
  unlist(
    els$page$session$Runtime$callFunctionOn(
      "function() { return this.map((el) => el.id); }",
      objectId = els$object_id,
      returnByValue = TRUE
    )$result$value
  )
}

test_that("pz_find pins the matched set and pushes it immutably", {
  page <- local_elements_page()
  ctx <- expect_visible(pz_find(page, ".panel"))

  expect_s3_class(ctx, "PaparazziContext")
  expect_false(inherits(ctx, "PaparazziPage"))
  expect_identical(length(ctx$scope), 1L)

  pinned <- ctx$scope[[1]]
  expect_s3_class(pinned, "paparazzi_pinned")
  expect_s3_class(pinned, "paparazzi_elements")
  # Multi-match targets pin the whole set (panel-a, panel-inner, panel-b).
  expect_identical(pinned$count, 3L)
  expect_identical(pinned$description, "`.panel`")
  expect_identical(pinned$locs, list(pz_loc(".panel")))
  expect_identical(scope_ids(pinned), c("panel-a", "panel-inner", "panel-b"))

  # The parent is never mutated: a derived context shares its set.
  expect_identical(length(page$scope), 0L)
  ctx2 <- pz_find(ctx, ".btn")
  expect_identical(length(ctx$scope), 1L)
  expect_identical(length(ctx2$scope), 2L)
  expect_identical(ctx2$scope[[1]], pinned)
  expect_identical(ctx2$scope[[2]]$count, 6L)
})

test_that("all find variants return visibly, including root no-ops", {
  page <- local_elements_page()
  expect_visible(pz_find(page, ".panel"))
  expect_visible(pz_find_first(page, ".panel"))
  expect_visible(pz_find_last(page, ".panel"))
  expect_visible(pz_find_nth(page, 2, target = ".panel"))
  ctx <- pz_find(page, ".panel")
  expect_visible(pz_find_pop(ctx))
  expect_visible(pz_find_reset(ctx))
  expect_visible(pz_find_pop(page))
  expect_visible(pz_find_reset(page))
  root <- pz_find_pop(ctx)
  expect_visible(pz_find_pop(root))
  expect_visible(pz_find_reset(root))
})

test_that("pz_find auto-waits for a match and times out with no match", {
  page <- local_elements_page()
  err <- expect_error(
    pz_find(page, ".never"),
    class = "paparazzi_error_timeout"
  )
  expect_match(conditionMessage(err), "`\\.never`")

  late <- pz_find(page, ".late-text", from_root = TRUE)
  expect_identical(late$scope[[1]]$count, 1L)
})

test_that("pz_find resolves inside the current scope", {
  page <- local_elements_page()
  ctx <- pz_find(page, "#panel-b")
  # Only panel-b's two buttons match inside the scope, not the six
  # that match document-wide.
  scoped <- pz_find(ctx, ".btn")
  expect_identical(scoped$scope[[2]]$count, 2L)
  expect_setequal(elements_text(scoped$scope[[2]]), c("Delete", "Save"))
})

test_that("from_root resolves the target from the document, still on the stack", {
  page <- local_elements_page()
  ctx <- pz_find(page, "#panel-b")
  from_root <- pz_find(ctx, ".btn", from_root = TRUE)
  expect_identical(from_root$scope[[2]]$count, 6L)
  # The new scope sits on top of the old one; pop returns to it.
  expect_identical(length(pz_find_pop(from_root)$scope), 1L)
  expect_identical(pz_find_pop(from_root)$scope[[1]], ctx$scope[[1]])
})

test_that("pz_find_first/last/nth with a target pin the picked match", {
  page <- local_elements_page()
  first <- pz_find_first(page, ".btn")
  nth <- pz_find_nth(page, 3, target = ".btn")

  expect_identical(first$scope[[1]]$count, 1L)
  expect_identical(elements_text(first$scope[[1]]), "Save")
  expect_identical(elements_text(nth$scope[[1]]), "Save   now")
  # An out-of-range which on a target keeps auto-waiting: no match.
  expect_error(
    pz_find_nth(page, 99, target = ".btn"),
    class = "paparazzi_error_timeout"
  )
})

test_that("pz_find_nth accepts target by position", {
  page <- local_elements_page()

  nth <- pz_find_nth(page, 3, ".btn")
  expect_identical(nth$scope[[1]]$count, 1L)
  expect_identical(nth$scope[[1]]$description, "`.btn` (which: 3)")
  expect_identical(elements_text(nth$scope[[1]]), "Save   now")
})

test_that("a positional target on pz_find_nth resolves inside the scope", {
  page <- local_elements_page()
  ctx <- pz_find(page, "#panel-b")

  nth <- pz_find_nth(ctx, 2, ".btn")
  expect_identical(length(nth$scope), 2L)
  expect_identical(elements_text(nth$scope[[2]]), "Save")
  expect_identical(nth$scope[[2]]$description, "`.btn` (which: 2)")
})

test_that("pz_find_nth without a target narrows the current scope", {
  page <- local_scopes_page()
  ctx <- pz_find(page, "#scope-a .sc-item")

  nth <- pz_find_nth(ctx, 2)
  expect_identical(length(nth$scope), 2L)
  expect_identical(nth$scope[[2]]$description, "`#scope-a .sc-item` (which: 2)")
  expect_identical(pz_get_count(nth), 1L)
  expect_identical(pz_get_text(nth), "A2")
})

test_that("narrowing slices the current scope eagerly", {
  page <- local_elements_page()
  ctx <- pz_find(page, ".panel")

  first <- pz_find_first(ctx)
  expect_identical(length(ctx$scope), 1L)
  expect_identical(length(first$scope), 2L)
  expect_identical(first$scope[[2]]$count, 1L)
  expect_identical(first$scope[[2]]$description, "`.panel` (which: first)")

  last <- pz_find_last(ctx)
  expect_identical(last$scope[[2]]$count, 1L)
  expect_identical(last$scope[[2]]$description, "`.panel` (which: last)")

  nth <- pz_find_nth(ctx, 2)
  expect_identical(nth$scope[[2]]$count, 1L)
  expect_identical(nth$scope[[2]]$description, "`.panel` (which: 2)")
  # The narrowed loc keeps which, so the wrapper can format it.
  expect_identical(nth$scope[[2]]$locs, list(pz_loc(".panel", which = 2)))

  # Narrowing stacks: first of the nth is the same element.
  expect_identical(
    elements_text(pz_find_first(nth)$scope[[3]]),
    elements_text(nth$scope[[2]])
  )
})

test_that("narrowing a union scope keeps the match in the description", {
  page <- local_elements_page()
  ctx <- pz_find(page, list(".panel", "#messages"))
  narrowed <- pz_find_nth(ctx, 2)
  expect_identical(narrowed$scope[[2]]$count, 1L)
  expect_identical(
    narrowed$scope[[2]]$description,
    "`.panel` | `#messages` (match: 2)"
  )
  # A union can't take a which, so its locs pass through unchanged.
  expect_identical(narrowed$scope[[2]]$locs, ctx$scope[[1]]$locs)
})

test_that("narrowing errors are classed and immediate", {
  page <- local_elements_page()
  ctx <- pz_find(page, ".btn")

  err <- expect_error(pz_find_nth(ctx, 7), class = "paparazzi_error_scope")
  expect_match(
    conditionMessage(err),
    "The current scope has 6 elements; there is no match 7\\."
  )

  expect_error(pz_find_first(page), class = "paparazzi_error_scope")
  expect_error(
    pz_find_nth(page, 2, from_root = TRUE),
    class = "paparazzi_error_scope"
  )
})

test_that("the find family validates its inputs", {
  page <- local_elements_page()

  expect_error(pz_find(page), class = "paparazzi_error_target")
  expect_error(pz_find(page, NULL), class = "paparazzi_error_target")
  expect_error(pz_find(page, ".btn", "bogus"), "empty")
  expect_error(pz_find(page, ".btn", from_root = "yes"), class = "rlang_error")

  # A spec that already carries which is never silently overridden.
  expect_error(
    pz_find_first(page, pz_loc(".btn", which = "last")),
    class = "paparazzi_error_input"
  )
  # A union can't pick one match by position.
  expect_error(
    pz_find_first(page, list(".btn", ".message")),
    class = "paparazzi_error_input"
  )

  # n is a whole number; "first"/"last" are the wrappers, not values.
  expect_error(pz_find_nth(page, "first"), class = "paparazzi_error_input")
  expect_error(pz_find_nth(page, "first"), "pz_find_first")
  expect_error(pz_find_nth(page, 0), class = "rlang_error")
  expect_error(pz_find_nth(page, 1.5), class = "rlang_error")
  expect_error(pz_find_nth(page, 2, ".btn", extra = 1), class = "rlang_error")

  expect_error(
    pz_find("not a context", ".btn"),
    class = "paparazzi_error_context"
  )
})

test_that("lazy targets resolve inside the pinned scope at use time", {
  page <- local_elements_page()
  ctx <- pz_find(page, "#messages")

  els <- loc_resolve(ctx, ".message", multiple = "all")
  withr::defer(release_elements(els))
  expect_identical(els$count, 3L)

  # Re-renders within the scope are fine: the lazy target follows the
  # DOM, only the pinned set itself is frozen.
  pz_js(
    page,
    'document.getElementById("messages").innerHTML = \'<li class="message user">new</li>\''
  )
  again <- loc_resolve(ctx, ".message", multiple = "all")
  withr::defer(release_elements(again))
  expect_identical(again$count, 1L)
})

test_that("a detached scope errors and never silently re-queries", {
  page <- local_elements_page()
  ctx <- pz_find(page, "#panel-inner")

  pz_js(page, 'document.getElementById("panel-a").remove()')
  err <- expect_error(pz_act_click(ctx), class = "paparazzi_error_detached")
  msg <- paste(conditionMessage(err), collapse = " ")
  expect_match(msg, "Scope element is no longer in the page")
  expect_match(msg, "Scope: `#panel-inner`")
  expect_match(msg, "pz_find")
  expect_match(msg, "pz_loc")
})

test_that("pop and reset unwind without releasing, and no-op at the root", {
  page <- local_elements_page()
  ctx <- pz_find(page, ".panel")
  ctx2 <- pz_find(ctx, ".btn")

  expect_identical(pz_find_pop(ctx2)$scope, ctx$scope)
  expect_identical(pz_find_reset(ctx2)$scope, list())
  # The popped set still works in the context that holds it: nothing
  # was released. The lazy explicit target resolves against ctx's
  # still-live pinned set; a released array would raise the classed
  # detach error instead.
  expect_no_error(pz_act_click(ctx, "#panel-inner"))

  expect_identical(pz_find_pop(page), page)
  expect_identical(pz_find_reset(page), page)
})

test_that("the object group release turns stale contexts into detach errors", {
  page <- local_elements_page()
  ctx <- pz_find(page, ".btn")
  pinned <- ctx$scope[[1]]

  # A mid-session release (the navigation seam) invalidates the set;
  # the next use raises the classed error, not a raw chromote one.
  expect_no_error(page$release_object_group())
  expect_error(pz_act_click(ctx), class = "paparazzi_error_detached")
  expect_false(is.null(pinned$object_id))

  # A closed page reports closed before anything else runs.
  pz_close(page)
  expect_error(pz_act_click(ctx), class = "paparazzi_error_closed")
})

test_that("closing the page releases the object group", {
  page <- pz_open(elements_fixture_file())
  ctx <- pz_find(page, ".btn")
  object_id <- ctx$scope[[1]]$object_id
  pz_close(page)

  # chromote aborts any command on a closed session before it can
  # reach CDP, so the raw call raises chromote's own closed-session
  # error, not an object-related one; the group release itself ran
  # before the close (the mid-session release test covers the seam).
  expect_error(
    ctx$page$session$Runtime$callFunctionOn(
      "function() { return this.length; }",
      objectId = object_id,
      returnByValue = TRUE
    ),
    "have been closed"
  )
})

test_that("scoped contexts print their stack", {
  page <- local_elements_page()
  ctx <- pz_find(page, ".panel")
  ctx2 <- pz_find_nth(ctx, 2)

  out <- capture.output(print(ctx2))
  expect_match(out[[1]], "── paparazzi scope")
  expect_match(
    out[[2]],
    "^Scope      root › `\\.panel` \\(3\\) › `\\.panel` #2 \\(1\\)$"
  )

  expect_match(
    capture.output(print(ctx))[[2]],
    "^Scope      root › `\\.panel` \\(3\\)$"
  )
  root_out <- capture.output(print(pz_find_reset(ctx2)))
  expect_match(root_out[[1]], "── paparazzi page")
  expect_length(root_out, 4L)
  expect_false(any(grepl("^Scope ", root_out)))
})

test_that("pillar renders contexts compactly", {
  page <- local_scopes_page()
  ctx <- pz_find(page, "#scope-a")

  expect_identical(pillar::type_sum(ctx), "pz_ctx")
  expect_identical(pillar::type_sum(page), "pz_ctx")

  # The formatted shaft carries pillar attributes; strip them to
  # compare the rendered text itself.
  shaft <- function(x) {
    out <- format(pillar::pillar_shaft(x), 60)
    attributes(out) <- NULL
    trimws(out)
  }
  expect_identical(shaft(ctx), "`#scope-a`")
  # Root contexts -- and pages, defensively -- never appear in the
  # element column; they show "root".
  expect_identical(shaft(page), "root")
  expect_identical(shaft(pz_find_reset(ctx)), "root")
})

test_that("numeric narrowing slices the pinned position", {
  page <- local_scopes_page()
  ctx <- pz_find(page, "#scope-a .sc-item")

  # switch() on a numeric which would pick by position: 2 -> "last",
  # > 3 -> no function at all. Every position must slice its own match.
  expect_identical(elements_text(pz_find_first(ctx)$scope[[2]]), "A1")
  expect_identical(elements_text(pz_find_nth(ctx, 2)$scope[[2]]), "A2")
  expect_identical(elements_text(pz_find_nth(ctx, 4)$scope[[2]]), "nested-a")
  expect_identical(elements_text(pz_find_nth(ctx, 6)$scope[[2]]), "get_weather")
  expect_identical(elements_text(pz_find_last(ctx)$scope[[2]]), "get_weather")
})

test_that("narrowing keeps a loc's original which", {
  page <- local_scopes_page()

  # An element-column entry from a which-loc names its original match,
  # not match 1 of the array.
  rects <- pz_get_rect(
    page,
    target = pz_loc("#scope-a .sc-item", which = "last")
  )
  expect_identical(
    rects$element[[1]]$scope[[1]]$description,
    "`#scope-a .sc-item` (which: last)"
  )
  expect_identical(pz_get_text(rects$element[[1]]), "get_weather")

  # Narrowing a narrowed scope keeps the original selection too: the
  # narrowed set is that same element, not match 1 of the raw css.
  scoped <- pz_find_nth(page, 2, target = "#scope-a .sc-item")
  narrowed <- pz_find_first(scoped)
  expect_identical(narrowed$scope[[2]]$count, 1L)
  expect_identical(
    narrowed$scope[[2]]$description,
    "`#scope-a .sc-item` (which: 2)"
  )
  expect_identical(elements_text(narrowed$scope[[2]]), "A2")
})
