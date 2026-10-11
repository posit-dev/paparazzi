shiny_idle_fixture <- function() {
  test_path("fixtures", "shiny-idle")
}

# One app process per worker: pz_open() on the fixture directory spawns a
# fresh Rscript per call, while pz_open() on the shared handle spawns none
# and still gets its own Shiny session (and slow render) per page.
the_shiny_idle_app <- new.env(parent = emptyenv())

shared_shiny_idle_app <- function() {
  app <- mget("app", envir = the_shiny_idle_app, ifnotfound = list(NULL))[[1]]
  if (is.null(app)) {
    skip_if_no_shiny()
    app <- pz_serve_shiny(shiny_idle_fixture())
    assign("app", app, envir = the_shiny_idle_app)
    withr::defer(app$stop(), envir = testthat::teardown_env())
  }
  app
}

shiny_idle_state <- function(page) {
  pz_js(
    page,
    "({connected: !!window.Shiny?.shinyapp?.$socket && Shiny.shinyapp.$socket.readyState === WebSocket.OPEN, busy: document.documentElement.classList.contains('shiny-busy'), recalculating: document.querySelectorAll('.recalculating').length, text: document.querySelector('#slow')?.textContent})"
  )
}
