import time

from shiny import App, render, ui

app_ui = ui.page_fluid(
    ui.navset_tab(
        ui.nav_panel(
            "Fast",
            ui.input_action_button("go", "Recalculate"),
            ui.output_text("fast"),
        ),
        ui.nav_panel("Slow", ui.output_text("slow")),
        id="tabs",
    )
)


def server(input, output, session):
    @render.text
    def fast():
        input.go()
        return "fast ready"

    # Depends on input.go so tests can invalidate it while its tab is
    # hidden: Shiny then marks it .recalculating but, being suspended,
    # never recomputes it until the Slow tab shows.
    @render.text
    def slow():
        input.go()
        time.sleep(0.8)
        return "slow ready"


app = App(app_ui, server)
