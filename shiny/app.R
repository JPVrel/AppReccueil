# This file is evaluated by shiny::runApp() in the local server process.
project_dir <- Sys.getenv("RECUEIL_PROJECT_DIR", unset = dirname(normalizePath(getwd())))
source(file.path(project_dir, "R", "load_modules.R"))
load_modules(project_dir)

database_config <- read_database_config(
  file.path(project_dir, "config", "database.yml")
)

build_shiny_app(database_config)
