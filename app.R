app_dir <- normalizePath(getwd())
source(file.path(app_dir, "R", "load_modules.R"))
load_modules(app_dir)

build_shiny_app()
