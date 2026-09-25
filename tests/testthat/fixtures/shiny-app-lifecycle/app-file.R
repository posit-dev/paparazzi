# Single-file form of the minimal app, for the app.R-path branch of
# pz_app(). Kept beside (not inside) app-dir/ so the two forms stay
# independent.
# message() (stderr), not cat(): see app-dir/app.R for why.
message("PAPARAZZI_FIXTURE_APP_FILE")

shiny::shinyApp(
  ui = shiny::fluidPage(shiny::textOutput("out")),
  server = function(input, output, session) {
    output$out <- shiny::renderText("hello paparazzi")
  }
)
