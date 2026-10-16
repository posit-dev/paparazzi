shiny::shinyApp(
  ui = shiny::fluidPage(
    shiny::tabsetPanel(
      id = "tabs",
      shiny::tabPanel(
        "Fast",
        shiny::actionButton("go", "Recalculate"),
        shiny::textOutput("fast")
      ),
      shiny::tabPanel("Slow", shiny::textOutput("slow"))
    )
  ),
  server = function(input, output, session) {
    output$fast <- shiny::renderText({
      input$go
      "fast ready"
    })
    # Depends on input$go so tests can invalidate it while its tab is
    # hidden: Shiny then marks it .recalculating but, being suspended,
    # never recomputes it until the Slow tab shows.
    output$slow <- shiny::renderText({
      input$go
      Sys.sleep(0.8)
      "slow ready"
    })
  }
)
