library(shiny)

ui <- fluidPage(
  title = "Tasks",
  tags$h1("Tasks"),
  textInput("title", "New task", placeholder = "What needs doing?"),
  selectInput("priority", "Priority", c("low", "normal", "high"), "normal"),
  actionButton("add", "Add", class = "btn-primary"),
  tags$h2("Open tasks"),
  textOutput("summary"),
  uiOutput("tasks")
)

server <- function(input, output, session) {
  tasks <- reactiveVal(data.frame(
    title = c("Renew passport", "Book dentist appointment"),
    priority = c("high", "normal")
  ))

  observeEvent(input$add, {
    req(nzchar(trimws(input$title)))
    tasks(rbind(
      tasks(),
      data.frame(title = trimws(input$title), priority = input$priority)
    ))
    updateTextInput(session, "title", value = "")
  })

  output$summary <- renderText({
    n <- nrow(tasks())
    paste(n, if (n == 1) "task" else "tasks")
  })

  # A slow render, so the app is busy for a moment after each change.
  output$tasks <- renderUI({
    Sys.sleep(0.5)
    items <- Map(
      function(title, priority) {
        tags$li(class = "task", `data-priority` = priority, title)
      },
      tasks()$title,
      tasks()$priority
    )
    tags$ul(class = "task-list", unname(items))
  })
}

shinyApp(ui, server)
