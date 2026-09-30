#' Run a Shiny app in a background process
#'
#' Starts a Shiny app -- a directory or an app file -- in a background R
#' process and returns a handle for its lifecycle. One app can back any
#' number of pages: pass the handle to [pz_open()] for each page. Closing
#' those pages leaves the app running.
#'
#' The handle has `$stop()` and `$logs()` methods and a `print()` method
#' showing the URL, port, and status -- the one place the paparazzi API
#' uses methods rather than `pz_*()` functions. `$stop()` interrupts,
#' waits, then kills, and is idempotent, so `withr::defer(app$stop())`
#' is a safe cleanup. A finalizer stops the app as a last resort.
#'
#' App stdout and stderr go to a temporary log file (never an undrained
#' pipe), readable mid-run with `$logs()`.
#'
#' @param app_dir A path to a Shiny app directory or an app file
#'   (anything [shiny::runApp()] accepts as a path).
#' @param ... Reserved; must be empty.
#' @param envvars Named character vector of environment variables set in
#'   the app process, on top of the inherited environment. `NULL` adds no
#'   environment overrides.
#' @param shiny_options Additional options for [shiny::runApp()], e.g.
#'   `list(test.mode = TRUE)`. `appDir` is reserved; use `app_dir` to select
#'   the app. `host` and `port` are managed by paparazzi: `host` defaults
#'   to `"127.0.0.1"`, and `port` (default `NULL`) picks a random free port.
#'   If startup fails because the port was taken, a new port is tried.
#' @param timeout Seconds to wait for the app to start listening;
#'   defaults to 10.
#'
#' @return A `PaparazziApp` handle with public fields `url` and `port`
#'   and methods `stop()`, `logs()`, and `is_running()`.
#'
#' @examplesIf paparazzi:::examples_run("shiny")
#' app <- pz_app(pz_example("tasks-app"))
#' app
#'
#' # Pages opened on a handle share the app, here at two screen sizes
#' desktop <- pz_open(app, width = 1280)
#' phone <- pz_open(app, width = 390, mobile = TRUE)
#' pz_get_text(phone, target = "#summary")
#' pz_close(desktop)
#' pz_close(phone)
#'
#' # Closing the pages leaves the app running until you stop it
#' app$is_running()
#' head(app$logs())
#' app$stop()
#'
#' @export
pz_app <- function(
  app_dir,
  ...,
  envvars = NULL,
  shiny_options = list(),
  timeout = 10
) {
  check_dots_empty()
  if (!is_string(app_dir)) {
    cli::cli_abort(
      "{.arg app_dir} must be a path to a Shiny app directory or app file, not {.obj_type_friendly {app_dir}}.",
      class = "paparazzi_error_input"
    )
  }
  envvars <- check_app_envvars(envvars)
  if (!is.list(shiny_options)) {
    stop_input_type(shiny_options, "a list")
  }
  if ("appDir" %in% names(shiny_options)) {
    cli::cli_abort(
      c(
        "{.arg shiny_options} must not set {.arg appDir}.",
        i = "Use {.arg app_dir} to select the app."
      ),
      class = "paparazzi_error_input"
    )
  }
  check_number_decimal(timeout, min = 0)
  rlang::check_installed("shiny", reason = "to run a Shiny app.")

  if (is_file_app(app_dir)) {
    app_dir <- normalizePath(app_dir, winslash = "/", mustWork = TRUE)
  } else if (dir.exists(app_dir)) {
    app_dir <- normalizePath(app_dir, winslash = "/", mustWork = TRUE)
  } else {
    cli::cli_abort(
      c(
        "{.arg app_dir} must be a Shiny app directory or app file: {.val {app_dir}}",
        i = "No such directory, or not an {.file .R} file."
      ),
      class = "paparazzi_error_input"
    )
  }

  app_start(app_dir, envvars, shiny_options, timeout)
}

# A file path is an app only if shiny::runApp() would source it.
is_file_app <- function(path) {
  grepl("[.]r$", tolower(path)) && file.exists(path) && !dir.exists(path)
}

check_app_envvars <- function(
  envvars,
  arg = caller_arg(envvars),
  call = caller_env()
) {
  if (is.null(envvars)) {
    return(NULL)
  }
  check_character(envvars, allow_null = TRUE, arg = arg, call = call)
  nms <- names(envvars)
  if (is.null(nms) || !all(nzchar(nms))) {
    cli::cli_abort(
      "{.arg {arg}} must have a name for every element.",
      class = "paparazzi_error_input",
      call = call
    )
  }
  envvars
}

# The picker races the actual bind (the probe socket closes before
# httpuv takes the port), so a taken port is a normal startup failure,
# retried on a fresh port.
app_start <- function(
  app_dir,
  envvars,
  shiny_options,
  timeout,
  call = caller_env()
) {
  max_attempts <- 5
  for (attempt in seq_len(max_attempts)) {
    port <- shiny_options$port %||% random_port()
    config <- c(
      list(appDir = app_dir),
      shiny_options,
      list(host = "127.0.0.1", port = port, launch.browser = FALSE)
    )
    config <- config[!duplicated(names(config), fromLast = TRUE)]
    app <- new_app(config, port, envvars)
    if (is.null(app)) {
      # A preflight connect succeeded. On some platforms a second bind
      # can also succeed, but traffic would reach the other listener.
      if (attempt < max_attempts) {
        shiny_options$port <- NULL
        next
      }
      app_startup_error(
        list(kind = "exited", port_taken = TRUE, log = character()),
        app_dir,
        timeout,
        call = call
      )
    }
    failure <- app_wait_ready(app, timeout)
    if (is.null(failure)) {
      return(app)
    }
    app$stop()
    if (failure$port_taken && attempt < max_attempts) {
      # Forced ports retry on a new random port like any other.
      shiny_options$port <- NULL
      next
    }
    app_startup_error(failure, app_dir, timeout, call = call)
  }
}

# NULL when the app is listening; otherwise a list(kind, port_taken, log).
app_wait_ready <- function(app, timeout) {
  deadline <- Sys.time() + timeout
  repeat {
    if (!app$is_running()) {
      log <- app$logs()
      return(list(
        kind = "exited",
        port_taken = any(grepl(
          "address already in use|failed to create server",
          log,
          ignore.case = TRUE
        )),
        log = log
      ))
    }
    if (app_port_connectable(app$port)) {
      return(NULL)
    }
    if (Sys.time() >= deadline) {
      return(list(kind = "timeout", port_taken = FALSE, log = app$logs()))
    }
    Sys.sleep(0.05)
  }
}

app_startup_error <- function(failure, app_dir, timeout, call) {
  what <- switch(
    if (failure$port_taken) "port_taken" else failure$kind,
    port_taken = "could not bind a port",
    timeout = cli::format_inline(
      "did not start within {.val {timeout}} seconds"
    ),
    exited = "exited during startup"
  )
  cli::cli_abort(
    c(
      "The Shiny app at {.path {app_dir}} {what}.",
      if (length(failure$log)) {
        # Tail and escape opaque child output before cli parses its braces.
        log <- paste(utils::tail(failure$log, 20L), collapse = "\n")
        log <- substr(log, max(1L, nchar(log) - 3999L), nchar(log))
        c(x = cli_escape(log))
      }
    ),
    class = "paparazzi_error_app_startup",
    call = call
  )
}

cli_escape <- function(x) {
  x <- gsub("{", "{{", x, fixed = TRUE)
  gsub("}", "}}", x, fixed = TRUE)
}

# Chrome refuses to navigate to these ports in 3000:8000, so they are
# useless to paparazzi even when free (same list shiny uses).
chrome_blocked_ports <- function() {
  c(3659, 4045, 5060, 5061, 6000, 6566, 6665:6669, 6697)
}

random_port <- function(call = caller_env()) {
  candidates <- setdiff(3000:8000, chrome_blocked_ports())
  for (i in 1:100) {
    port <- sample(candidates, 1)
    probe <- tryCatch(serverSocket(port), error = function(e) NULL)
    if (!is.null(probe)) {
      close(probe)
      return(port)
    }
  }
  cli::cli_abort(
    "Could not find a free port for the Shiny app.",
    class = "paparazzi_error_app_startup",
    call = call
  )
}

app_port_connectable <- function(port, host = "127.0.0.1") {
  # A refused connection warns as well as errors; the polls below would
  # otherwise spam a warning per attempt.
  con <- suppressWarnings(tryCatch(
    socketConnection(
      host = host,
      port = port,
      open = "r+",
      blocking = TRUE,
      timeout = 1
    ),
    error = function(e) NULL
  ))
  if (is.null(con)) {
    return(FALSE)
  }
  close(con)
  TRUE
}

new_app <- function(config, port, envvars) {
  config_file <- tempfile(pattern = "paparazzi-app-", fileext = ".rds")
  saveRDS(config, config_file)
  log_file <- tempfile(pattern = "paparazzi-app-", fileext = ".log")
  # The sole busy-port probe runs after serialization, just before spawn.
  if (app_port_connectable(port)) {
    return(NULL)
  }
  process <- processx::process$new(
    file.path(R.home("bin"), "Rscript"),
    args = c(
      "-e",
      "do.call(shiny::runApp, readRDS(commandArgs(TRUE)[[1]]))",
      config_file
    ),
    # File, never a pipe: an undrained pipe blocks the app's writes.
    stdout = log_file,
    stderr = "2>&1",
    # "current" keeps the inherited environment; envvars override it.
    env = c("current", envvars),
    cleanup = TRUE,
    cleanup_tree = TRUE
  )
  PaparazziApp$new(process, log_file, port)
}

PaparazziApp <- R6::R6Class(
  "PaparazziApp",
  public = list(
    url = NULL,
    port = NULL,

    initialize = function(process, log_file, port) {
      private$process_ <- process
      private$log_file_ <- log_file
      self$port <- port
      self$url <- sprintf("http://127.0.0.1:%d/", port)
    },

    # Interrupt, wait, kill; each step no-ops once the process is gone,
    # so repeated stop() is safe.
    stop = function() {
      if (!private$stopped_) {
        private$stopped_ <- TRUE
        if (private$process_$is_alive()) {
          private$process_$interrupt()
          private$process_$wait(2000)
        }
        if (private$process_$is_alive()) {
          private$process_$kill()
        }
      }
      invisible(self)
    },

    logs = function() {
      if (!file.exists(private$log_file_)) {
        return(character())
      }
      readLines(private$log_file_, warn = FALSE)
    },

    is_running = function() {
      !private$stopped_ && private$process_$is_alive()
    },

    print = function(...) {
      status <- if (self$is_running()) {
        sprintf("running (pid %d)", private$process_$get_pid())
      } else if (private$stopped_) {
        "stopped"
      } else {
        sprintf("exited (status %d)", private$process_$get_exit_status())
      }
      cli::cat_line("<paparazzi app> ", self$url, " -- ", status)
      invisible(self)
    }
  ),
  private = list(
    process_ = NULL,
    log_file_ = NULL,
    stopped_ = FALSE,
    finalize = function() {
      try(self$stop(), silent = TRUE)
    }
  )
)
