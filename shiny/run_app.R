args <- commandArgs(trailingOnly = TRUE)
port <- as.integer(args[[1]])
file_arg <- grep("^--file=", commandArgs(), value = TRUE)
app_dir <- dirname(normalizePath(sub("^--file=", "", file_arg[[1]])))

shiny::runApp(
  appDir = app_dir,
  host = "127.0.0.1",
  port = port,
  launch.browser = FALSE,
  quiet = TRUE
)
