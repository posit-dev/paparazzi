# Minimal headless-testable app. The marker lines let tests confirm the
# process started and that envvars reached it, via app$logs().
cat("PAPARAZZI_FIXTURE_APP\n")
cat("marker:", Sys.getenv("PAPARAZZI_TEST_MARKER", "<unset>"), "\n")

shiny::shinyApp(
  ui = shiny::fluidPage(shiny::textOutput("out")),
  server = function(input, output, session) {
    output$out <- shiny::renderText("hello paparazzi")
  }
)
