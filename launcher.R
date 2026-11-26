# Lanceur local de l'application. Il affiche une petite fenêtre Tcl/Tk
# au lieu de démarrer directement l'interface Shiny dans Positron.
library(tcltk)

app_dir <- normalizePath(getwd())
source(file.path(app_dir, "R", "package_library.R"))
activate_project_package_library(app_dir)
source(file.path(app_dir, "R", "load_modules.R"))
load_modules(app_dir)

# Le lanceur ne nécessite que Shiny pour l'exécution ; testthat reste
# optionnel et sera installé par le script de développement.
config <- create_app_config(app_dir)
missing <- missing_packages(runtime_packages())

# Si Shiny manque, l'utilisateur peut lancer l'installation sans quitter R.
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

# Les fonctions de processus sont injectées dans la fenêtre pour séparer
# l'interface graphique de la gestion du serveur et faciliter les tests.
create_launcher_window(
  config = config,
  start_fn = start_server_process,
  stop_fn = stop_server_process
)
