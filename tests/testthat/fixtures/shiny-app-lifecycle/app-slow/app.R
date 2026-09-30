# Never starts listening within a test-sized budget: exercises the
# startup-timeout path (and pz_serve()'s duty to kill the child on
# startup failure).
Sys.sleep(3600)

shiny::shinyApp(
  ui = shiny::fluidPage("never seen"),
  server = function(input, output, session) NULL
)
