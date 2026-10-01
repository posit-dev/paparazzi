test_that("page state bindings start empty", {
  page <- PaparazziPage$new(structure(list(), class = "ChromoteSession"))

  expect_identical(page$staging, list())
  expect_null(page$recorder)
  expect_null(page$pre_action_loader)
  expect_null(page$app)
})

test_that("nested staging assignments persist and preserve other settings", {
  page <- PaparazziPage$new(structure(list(), class = "ChromoteSession"))
  page$staging <- list(stage = list(speed = 2), frame = list(zoom = 1))

  page$staging$frame$zoom <- 3
  page$staging$caption <- list(text = "Ready")

  expect_identical(
    page$staging,
    list(
      stage = list(speed = 2),
      frame = list(zoom = 3),
      caption = list(text = "Ready")
    )
  )
})

test_that("staging can be replaced and reset", {
  page <- PaparazziPage$new(structure(list(), class = "ChromoteSession"))
  page$staging <- list(frame = list(zoom = 1))
  page$staging <- list(caption = list(text = "Ready"))

  expect_identical(page$staging, list(caption = list(text = "Ready")))

  page$staging <- list()
  expect_identical(page$staging, list())
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

  page$staging$frame <- list(zoom = 2)
  page$recorder <- list(active = TRUE)
  page$pre_action_loader <- "loader-1"

  expect_identical(other$staging, list())
  expect_null(other$recorder)
  expect_null(other$pre_action_loader)
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

  expect_error(page$app <- NULL, "unused argument")
  expect_identical(page$app, app)
})
