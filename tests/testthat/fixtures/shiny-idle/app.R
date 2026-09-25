shiny::shinyApp(
  ui = shiny::fluidPage(shiny::textOutput("slow")),
  server = function(input, output, session) {
    output$slow <- shiny::renderText({
      Sys.sleep(0.8)
      "reactive ready"
    })
  }
)
