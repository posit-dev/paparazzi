shiny::shinyApp(
  ui = shiny::fluidPage(
    shiny::textOutput("slow"),
    # Stamps the page-side moment the slow output receives its value
    # (shiny:value, just before the render and the idle transition), so
    # tests can measure the idle wait's stability hold against it.
    shiny::tags$script(shiny::HTML(
      "$(document).on('shiny:value', function(e) {",
      "  if (e.name === 'slow') window.__slowReadyAt = performance.now();",
      "});"
    ))
  ),
  server = function(input, output, session) {
    output$slow <- shiny::renderText({
      Sys.sleep(0.8)
      "reactive ready"
    })
  }
)
