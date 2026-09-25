# Flush stdout explicitly so both redirected streams can be checked mid-run.
cat("PAPARAZZI_FIXTURE_STDOUT\n")
flush(stdout())
message("PAPARAZZI_FIXTURE_STDERR")
message("PAPARAZZI_FIXTURE_APP")
message("marker: ", Sys.getenv("PAPARAZZI_TEST_MARKER", "<unset>"))

shiny::shinyApp(
  ui = shiny::fluidPage(shiny::textOutput("out")),
  server = function(input, output, session) {
    output$out <- shiny::renderText("hello paparazzi")
  }
)
