test_that("page state bindings start empty", {
  page <- PaparazziPage$new(structure(list(), class = "ChromoteSession"))

  expect_identical(page$session_state, list())
  expect_null(page$staging)
  expect_null(page$recorder)
  expect_null(page$pre_action_loader)
  expect_null(page$app)
})

test_that("nested session-state assignments persist and preserve other settings", {
  page <- PaparazziPage$new(structure(list(), class = "ChromoteSession"))
  page$session_state <- list(
    cursor = list(x = 1),
    caption = list(text = "Ready")
  )

  page$session_state$cursor$x <- 3
  page$session_state$annotate_init_id <- "init-1"

  expect_identical(
    page$session_state,
    list(
      cursor = list(x = 3),
      caption = list(text = "Ready"),
      annotate_init_id = "init-1"
    )
  )
})

test_that("session state can be replaced and reset", {
  page <- PaparazziPage$new(structure(list(), class = "ChromoteSession"))
  page$session_state <- list(cursor = list(x = 1))
  page$session_state <- list(caption = list(text = "Ready"))

  expect_identical(page$session_state, list(caption = list(text = "Ready")))

  page$session_state <- list()
  expect_identical(page$session_state, list())
})

test_that("derived contexts carry staging, the page never does", {
  page <- PaparazziPage$new(structure(list(), class = "ChromoteSession"))

  staged <- ctx_derive(
    page,
    list(),
    staging = list(overrides = list(pause = 2), frame = list(zoom = 3))
  )
  expect_identical(staged$page, page)
  expect_identical(ctx_stage(staged)$pause, 2)
  expect_identical(ctx_frame(staged)$zoom, 3)

  # Scope derivation, pops, and resets all inherit staging
  scoped <- ctx_derive(staged, list(pinned = 1))
  expect_identical(ctx_stage(scoped)$pause, 2)
  popped <- ctx_derive(scoped, list())
  expect_identical(ctx_stage(popped)$pause, 2)

  # The empty case: the root page has no staging, and accessors
  # still resolve the built-in defaults.
  expect_null(page$staging)
  expect_identical(ctx_stage(page), STAGE_DEFAULTS)
  expect_null(ctx_frame(page))
})

test_that("recorder assignments persist and can be cleared", {
  page <- PaparazziPage$new(structure(list(), class = "ChromoteSession"))
  page$recorder <- list(active = TRUE, files = "first.png")

  page$recorder$files <- c("first.png", "second.png")

  expect_identical(
    page$recorder,
    list(active = TRUE, files = c("first.png", "second.png"))
  )

  page$recorder <- NULL
  expect_null(page$recorder)
})

test_that("pre-action loader can be stored and reset", {
  page <- PaparazziPage$new(structure(list(), class = "ChromoteSession"))

  page$pre_action_loader <- "loader-1"
  expect_identical(page$pre_action_loader, "loader-1")

  page$pre_action_loader <- NULL
  expect_null(page$pre_action_loader)
})

test_that("page state assignments do not leak into other pages", {
  session <- structure(list(), class = "ChromoteSession")
  page <- PaparazziPage$new(session)
  other <- PaparazziPage$new(session)

  page$session_state$caption <- list(text = "Hi")
  page$recorder <- list(active = TRUE)
  page$pre_action_loader <- "loader-1"
  page <- ctx_derive(page, list(), staging = list(overrides = list(pause = 1)))

  expect_identical(other$session_state, list())
  expect_null(other$recorder)
  expect_null(other$pre_action_loader)
  expect_null(other$staging)
})

test_that("app exposes the owned app before the shared app", {
  session <- structure(list(), class = "ChromoteSession")
  owned <- new.env(parent = emptyenv())
  shared <- new.env(parent = emptyenv())
  owned_page <- PaparazziPage$new(session, owned_app = owned)
  shared_page <- PaparazziPage$new(session, shared_app = shared)
  both_page <- PaparazziPage$new(
    session,
    owned_app = owned,
    shared_app = shared
  )

  expect_identical(owned_page$app, owned)
  expect_identical(shared_page$app, shared)
  expect_identical(both_page$app, owned)
})

test_that("app cannot be replaced through its binding", {
  session <- structure(list(), class = "ChromoteSession")
  app <- new.env(parent = emptyenv())
  page <- PaparazziPage$new(session, shared_app = app)

  expect_error(page$app <- NULL)
  expect_identical(page$app, app)
})
