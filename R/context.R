# pillar rendering for the getters' element list-column: a short type
# label, and a shaft showing the top scope's description compactly
# (pillar truncates to the available width). Root contexts -- and
# pages, defensively -- never appear in the column; they show "root".
#' @importFrom pillar type_sum
#' @export
type_sum.PaparazziContext <- function(x) {
  "pz_ctx"
}

#' @importFrom pillar pillar_shaft
#' @export
pillar_shaft.PaparazziContext <- function(x, ...) {
  scoped <- scope_top(x)
  description <- if (is.null(scoped)) "root" else scoped$description
  pillar::new_pillar_shaft_simple(description, align = "left")
}

#' Paparazzi contexts and pages
#'
#' @description
#' A **context** is the first argument of `pz_*()` functions, enabling `|>`
#' chains. `pz_find*()` return contexts visibly; chainable actions return
#' them invisibly, except in a recording chain: the context returned by
#' [pz_record_start()] (and contexts derived from it) is returned visibly
#' while its recording runs, and printing it stops the recording. A
#' context is either the root (a
#' `PaparazziPage`) or a scoped context created by `pz_find*()`: a context
#' holding an immutable stack of pinned element sets. The stack is never
#' mutated in place -- `pz_find*()` derive a new context sharing the
#' parent's pinned sets -- and [pz_find_pop()]/[pz_find_reset()] unwind it
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

    #' @field recording The recorder a recording chain belongs to, or
    #'   `NULL` (internal).
    recording = NULL,

    #' @description Create a context attached to a page.
    #' @param page A `PaparazziPage`.
    #' @param scope Stack of pinned element sets; defaults to empty (the
    #'   root context).
    #' @param recording The recorder of the recording chain, if any.
    initialize = function(page, scope = list(), recording = NULL) {
      self$page <- page
      self$scope <- scope
      self$recording <- recording
    },

    #' @description Print the page summary (URL, device, scope stack,
    #'   recording state) without the target section or visuals; see
    #'   [pz_inspect()]. A recording chain whose recording is still
    #'   running stops it instead and, interactively, shows the video.
    #' @param ... Unused; included for compatibility with the `print()` generic.
    print = function(...) {
      if (ctx_recording(self)) {
        return(record_print_stop(self))
      }
      inspect_summary_print(self)
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
    #' @param owned_app App started by this page, if any.
    #' @param shared_app Caller-owned app handle kept alive while the page lives.
    initialize = function(
      session,
      timeout = 10,
      owned_app = NULL,
      shared_app = NULL
    ) {
      stopifnot(inherits(session, "ChromoteSession"))
      private$chromote_ <- session
      private$default_timeout_ <- timeout
      private$owned_app_ <- owned_app
      private$shared_app_ <- shared_app
      self$page <- self
    },

    #' @description Close the page's browser tab (its chromote session). Idempotent.
    close = function() {
      if (!private$closed_) {
        if (!is.null(private$owned_app_)) {
          on.exit(private$owned_app_$stop(), add = TRUE)
        }
        # A recorder on this page can't wait for its next tick or event:
        # tear it down before the session goes away.
        record_page_closed(self)
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
    #'   Internal: runs on close and before navigation resets scopes. (An
    #'   `@noRd` here would suppress the whole PaparazziPage topic, so it stays
    #'   documented like its siblings on this internal-keyword topic.)
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

    #' @description Print the page summary (URL, device, scope stack,
    #'   recording state) without the target section or visuals; see
    #'   [pz_inspect()]. A closed page prints one line.
    #' @param ... Unused; included for compatibility with the `print()` generic.
    print = function(...) {
      if (private$closed_) {
        cli::cat_line("<paparazzi page> (closed)")
        return(invisible(self))
      }
      inspect_summary_print(self)
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
    owned_app_ = NULL,
    shared_app_ = NULL,
    closed_ = FALSE,
    default_timeout_ = 10,
    # Main-frame loaderId captured before the last user action.
    last_action_loader_ = NULL,
    # One object group per page for every remote object a scope pinned,
    # released wholesale on close and navigation. A constant
    # is safe because groups are per session, so it can't collide across
    # pages.
    object_group_ = "paparazzi_scopes",
    staging_ = list(),
    recorder_ = NULL
  )
)

#' @exportS3Method knitr::knit_print
knit_print.PaparazziContext <- function(x, ...) {
  if (ctx_recording(x)) {
    return(knitr::knit_print(pz_record_stop(x), ...))
  }
  knitr::normal_print(x)
}

# Derived contexts stay in their recording chain.
ctx_derive <- function(ctx, scope) {
  PaparazziContext$new(ctx$page, scope = scope, recording = ctx$recording)
}

# The return value of every chainable function: visible only in a
# recording chain whose recording is still running, so autoprint at the
# end of the chain stops it.
ctx_return <- function(ctx) {
  if (ctx_recording(ctx)) ctx else invisible(ctx)
}

ctx_recording <- function(ctx) {
  rec <- ctx$recording
  !is.null(rec) && rec$active && identical(rec, page_recorder(ctx$page))
}
