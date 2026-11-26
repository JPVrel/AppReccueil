# Ce script est exécuté par le lanceur dans un nouveau processus R.
# Il ne lance pas le navigateur : c'est la boîte de dialogue qui s'en charge.
args <- commandArgs(trailingOnly = TRUE)
port <- as.integer(args[[1]])
file_arg <- grep("^--file=", commandArgs(), value = TRUE)
app_dir <- dirname(normalizePath(sub("^--file=", "", file_arg[[1]])))
project_dir <- dirname(app_dir)
source(file.path(project_dir, "R", "package_library.R"))
activate_project_package_library(project_dir)
Sys.setenv(RECUEIL_PROJECT_DIR = project_dir)

shiny::runApp(
  appDir = app_dir,
  host = "127.0.0.1",
  port = port,
  launch.browser = FALSE,
  quiet = TRUE
)
