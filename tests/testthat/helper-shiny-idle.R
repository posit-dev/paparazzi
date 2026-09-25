shiny_idle_fixture <- function() {
  test_path("fixtures", "shiny-idle")
}

shiny_idle_state <- function(page) {
  pz_js(page, "({connected: !!window.Shiny?.shinyapp?.$socket && Shiny.shinyapp.$socket.readyState === WebSocket.OPEN, busy: document.documentElement.classList.contains('shiny-busy'), recalculating: document.querySelectorAll('.recalculating').length, text: document.querySelector('#slow')?.textContent})")
}
