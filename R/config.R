script_directory <- function(command_args = commandArgs()) {
  file_arg <- grep("^--file=", command_args, value = TRUE)

  if (length(file_arg) > 0) {
    return(dirname(normalizePath(
      sub("^--file=", "", file_arg[[1]]),
      mustWork = FALSE
    )))
  }

  normalizePath(getwd())
}

create_app_config <- function(app_dir = script_directory(), host = "127.0.0.1", port = 8000L) {
  list(
    app_dir = app_dir,
    host = host,
    port = as.integer(port),
    shiny_dir = file.path(app_dir, "shiny"),
    shiny_runner = file.path(app_dir, "shiny", "run_app.R"),
    rscript = file.path(R.home("bin"), "Rscript"),
    app_url = sprintf("http://%s:%d", host, port)
  )
}
