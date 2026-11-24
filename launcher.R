library(tcltk)

app_dir <- normalizePath(getwd())
source(file.path(app_dir, "R", "load_modules.R"))
load_modules(app_dir)

config <- create_app_config(app_dir)
missing <- missing_packages(runtime_packages())

if (length(missing) > 0) {
  answer <- tcltk::tkmessageBox(
    title = "Dépendances manquantes",
    message = paste("Installer les packages manquants ?", paste(missing, collapse = ", ")),
    icon = "question",
    type = "yesno"
  )

  if (identical(as.character(answer), "yes")) {
    system2(
      config$rscript,
      c("--vanilla", file.path(app_dir, "scripts", "install_dependencies.R")),
      wait = TRUE
    )
  }
}

if (length(missing_packages(runtime_packages())) > 0) {
  stop("Les dépendances nécessaires ne sont pas installées.")
}

create_launcher_window(
  config = config,
  start_fn = start_server_process,
  stop_fn = stop_server_process
)
