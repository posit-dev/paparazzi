#' Paparazzi contexts and pages
#'
#' @description
#' A **context** is the first argument and invisible return value of every
#' `pz_*()` function, enabling `|>` chains. A context is either the root (a
#' `PaparazziPage`) or a scoped context created by `pz_find*()` (not yet
#' implemented). Session-level state -- the Chromote session, default timeout,
#' staging settings, recorder state -- lives on the page.
#'
#' @keywords internal
PaparazziContext <- R6::R6Class(
  "PaparazziContext",
  public = list(
    #' @field page The root `PaparazziPage` this context belongs to.
    page = NULL,

    #' @field scope Stack of pinned element sets; empty for the root context.
    scope = list(),

    #' @description Create a context attached to a page.
    #' @param page A `PaparazziPage`.
    initialize = function(page) {
      self$page <- page
    }
  )
)

#' @rdname PaparazziContext
PaparazziPage <- R6::R6Class(
  "PaparazziPage",
  inherit = PaparazziContext,
  public = list(
    #' @description Wrap a `ChromoteSession` as a paparazzi page.
    #' @param session A `chromote::ChromoteSession`.
    #' @param timeout Default timeout in seconds for this session.
    initialize = function(session, timeout = 10) {
      stopifnot(inherits(session, "ChromoteSession"))
      private$chromote_ <- session
      private$default_timeout_ <- timeout
      self$page <- self
    },

    #' @description Close the page and its browser session. Idempotent.
    close = function() {
      if (!private$closed_) {
        private$closed_ <- TRUE
        private$chromote_$close()
      }
      invisible(self)
    },

    #' @description Open the live browser view (DevTools).
    view = function() {
      private$chromote_$view()
      invisible(self)
    },

    #' @description Has the page been closed?
    is_closed = function() {
      private$closed_
    },

    #' @description Print a short summary.
    print = function(...) {
      state <- if (private$closed_) "closed" else "open"
      cli::cat_line("<PaparazziPage: ", state, ">")
      if (!private$closed_) {
        url <- tryCatch(
          private$chromote_$Runtime$evaluate("location.href")$result$value,
          error = function(e) NULL
        )
        if (!is.null(url)) cli::cat_line("  URL: ", url)
      }
      invisible(self)
    }
  ),
  active = list(
    #' @field session The underlying `ChromoteSession` (read-only).
    session = function() {
      private$chromote_
    },

    #' @field child_loop chromote's private `later` event loop (read-only).
    #'   Waits must pump this loop so scheduled timers keep firing.
    child_loop = function() {
      private$chromote_$get_child_loop()
    },

    #' @field default_timeout Session default timeout in seconds.
    default_timeout = function(value) {
      if (missing(value)) {
        private$default_timeout_
      } else {
        check_number_decimal(value, min = 0)
        private$default_timeout_ <- value
      }
    }
  ),
  private = list(
    chromote_ = NULL,
    closed_ = FALSE,
    default_timeout_ = 10,
    # Reserved session-level state for later tasks (staging, recorder).
    staging_ = list(),
    recorder_ = NULL
  )
)
