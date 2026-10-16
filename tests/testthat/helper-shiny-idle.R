shiny_idle_fixture <- function() {
  test_path("fixtures", "shiny-idle")
}

# One app process per worker: pz_open() on the fixture directory spawns a
# fresh Rscript per call, while pz_open() on the shared handle spawns none
# and still gets its own Shiny session (and slow render) per page.
#
# Coupling to know about: the app is a single-threaded R process whose
# reactive blocks it for 0.8s, so a render orphaned by an earlier test
# (e.g. a page closed mid-render) can delay the next test's first render
# by up to 0.8s. The timeout = 3 budgets in test-wait.R have the room.
the_shiny_idle_app <- new.env(parent = emptyenv())

shared_shiny_idle_app <- function() {
  app <- mget("app", envir = the_shiny_idle_app, ifnotfound = list(NULL))[[1]]
  if (is.null(app)) {
    skip_if_no_shiny()
    app <- pz_serve_shiny(shiny_idle_fixture())
    if (!testthat::is_testing()) {
      return(app)
    }
    assign("app", app, envir = the_shiny_idle_app)
    withr::defer(app$stop(), envir = testthat::teardown_env())
  }
  app
}

# Tabbed app whose Slow-tab output is suspended while hidden: Shiny marks
# it .recalculating but never recomputes it until the tab shows. Exercises
# idle settling over a stuck recalculating class. The 0.8s render coupling
# from the shiny-idle app applies here too. Tab state is per Shiny session,
# so each test opens its own page (pz_local_page) to see the Slow tab hidden.
the_shiny_suspended_app <- new.env(parent = emptyenv())

shared_shiny_suspended_app <- function() {
  app <- mget("app", envir = the_shiny_suspended_app, ifnotfound = list(NULL))[[
    1
  ]]
  if (is.null(app)) {
    skip_if_no_shiny()
    app <- pz_serve_shiny(test_path("fixtures", "shiny-suspended"))
    if (!testthat::is_testing()) {
      return(app)
    }
    assign("app", app, envir = the_shiny_suspended_app)
    withr::defer(app$stop(), envir = testthat::teardown_env())
  }
  app
}

shiny_idle_state <- function(page) {
  pz_evaluate(
    page,
    "({connected: !!window.Shiny?.shinyapp?.$socket && Shiny.shinyapp.$socket.readyState === WebSocket.OPEN, busy: document.documentElement.classList.contains('shiny-busy'), recalculating: document.querySelectorAll('.recalculating').length, text: document.querySelector('#slow')?.textContent})"
  )
}
