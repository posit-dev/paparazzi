#' Paparazzi contexts and pages
#'
#' @description
#' A **context** is the first argument and invisible return value of every
#' `pz_*()` function, enabling `|>` chains. A context is either the root (a
#' `PaparazziPage`) or a scoped context created by `pz_find*()`: a context
#' holding an immutable stack of pinned element sets. The stack is never
#' mutated in place -- `pz_find*()` derive a new context sharing the
#' parent's pinned sets -- and `pz_find_pop()`/`pz_find_reset()` unwind it
#' the same way. Session-level state -- the Chromote session, default
#' timeout, staging settings, recorder state -- lives on the page.
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
    #' @param scope Stack of pinned element sets; defaults to empty (the
    #'   root context).
    initialize = function(page, scope = list()) {
      self$page <- page
      self$scope <- scope
    },

    #' @description Print the scope stack.
    #' @param ... Unused; included for compatibility with the `print()` generic.
    print = function(...) {
      cli::cat_line("<PaparazziContext>")
      scope <- vapply(
        self$scope,
        function(pinned) pinned$description,
        character(1)
      )
      cli::cat_line(
        "  Scope: ",
        if (length(scope)) paste(scope, collapse = " ") else "root"
      )
      invisible(self)
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
        # Release every pinned scope object before the session goes away;
        # contexts that survive the release raise the classed detach
        # error on their next use instead of a raw chromote one.
        self$release_object_group()
        private$closed_ <- TRUE
        private$chromote_$close()
      }
      invisible(self)
    },

    #' @description Release every remote object a scope pinned.
    #'   Internal: runs on close, and the navigation task calls it before
    #'   a navigation resets scopes. (An `@noRd` here would suppress the
    #'   whole PaparazziPage topic, so it stays documented like its
    #'   siblings on this internal-keyword topic.)
    release_object_group = function() {
      try(
        private$chromote_$Runtime$releaseObjectGroup(
          objectGroup = private$object_group_
        ),
        silent = TRUE
      )
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
    #' @param ... Unused; included for compatibility with the `print()` generic.
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
    },

    #' @field object_group The CDP object group holding every remote
    #'   object a scope pinned (read-only; internal).
    object_group = function() {
      private$object_group_
    }
  ),
  private = list(
    chromote_ = NULL,
    closed_ = FALSE,
    default_timeout_ = 10,
    # One object group per page for every remote object a scope pinned,
    # released wholesale on close (and, later, navigation). A constant
    # is safe because groups are per session, so it can't collide across
    # pages; the field indirection keeps per-page uniqueness a later
    # change without touching callers.
    object_group_ = "paparazzi_scopes",
    # Reserved session-level state for later tasks (staging, recorder).
    staging_ = list(),
    recorder_ = NULL
  )
)
