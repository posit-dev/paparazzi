test_that("pz_example() lists the shipped examples", {
  expect_identical(pz_example(), c("tasks", "tasks-app"))
})

test_that("pz_example() returns paths without needing the extension", {
  tasks <- pz_example("tasks")
  expect_true(file.exists(tasks))
  expect_identical(basename(tasks), "tasks.html")

  app <- pz_example("tasks-app")
  expect_true(dir.exists(app))
  expect_true(file.exists(file.path(app, "app.R")))
})

test_that("pz_example() errors on unknown names", {
  expect_snapshot(error = TRUE, {
    pz_example("nope")
    pz_example(c("tasks", "tasks-app"))
  })
})

