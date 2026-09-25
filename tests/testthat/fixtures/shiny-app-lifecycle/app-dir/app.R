# Minimal headless-testable app. The marker lines let tests confirm the
# process started and that envvars reached it, via app$logs(). They go
# to stderr (message()): a redirected stdout is block-buffered, so
# cat() output would not be readable mid-run.
message("PAPARAZZI_FIXTURE_APP")
message("marker: ", Sys.getenv("PAPARAZZI_TEST_MARKER", "<unset>"))

shiny::shinyApp(
  ui = shiny::fluidPage(shiny::textOutput("out")),
  server = function(input, output, session) {
    output$out <- shiny::renderText("hello paparazzi")
  }
)
