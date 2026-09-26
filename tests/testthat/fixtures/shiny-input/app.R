cat("PAPARAZZI_SHINY_INPUT_READY\n")
module_ui <- function(id) {
  ns <- shiny::NS(id)
  shiny::tags$div(
    id = "module-root",
    shiny::textInput(ns("text"), "Module text", "module initial"),
    shiny::textOutput(ns("out"))
  )
}
module_server <- function(id) {
  shiny::moduleServer(id, function(input, output, session) {
    output$out <- shiny::renderText(input$text)
  })
}
shiny::shinyApp(
  ui = shiny::fluidPage(
    shiny::textInput("text", "Text", "initial"),
    shiny::selectizeInput("choice", "Choice", choices = c("first", "second")),
    shiny::sliderInput("amount", "Amount", min = 0, max = 100, value = 10),
    shiny::numericInput(
      "precise",
      "Precise",
      value = 1,
      min = 0,
      max = 2,
      step = 0.00000001
    ),
    shiny::sliderInput(
      "day",
      "Day",
      min = as.Date("2024-01-01"),
      max = as.Date("2024-12-31"),
      value = as.Date("2024-01-10")
    ),
    shiny::dateRangeInput(
      "dates",
      "Dates",
      start = "2024-01-01",
      end = "2024-01-05"
    ),
    shiny::textOutput("text_out"),
    shiny::textOutput("choice_out"),
    shiny::textOutput("amount_out"),
    shiny::textOutput("precise_out"),
    shiny::textOutput("day_out"),
    shiny::textOutput("dates_out"),
    shiny::actionButton("button", "Action"),
    shiny::fileInput("file", "File"),
    module_ui("mod")
  ),
  server = function(input, output, session) {
    output$text_out <- shiny::renderText(input$text)
    output$choice_out <- shiny::renderText(input$choice)
    output$amount_out <- shiny::renderText(input$amount)
    output$precise_out <- shiny::renderText(sprintf("%.8f", input$precise))
    output$day_out <- shiny::renderText(as.character(input$day))
    output$dates_out <- shiny::renderText(paste(input$dates, collapse = " / "))
    module_server("mod")
  }
)
