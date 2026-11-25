# Charge les modules, y compris ceux rangés dans les sous-dossiers de domaine.
# Le tri garantit le même ordre de chargement sur chaque système.
load_modules <- function(project_dir, envir = parent.frame()) {
  module_files <- list.files(
    file.path(project_dir, "R"),
    pattern = "\\.R$",
    full.names = TRUE,
    recursive = TRUE
  )
  module_files <- module_files[basename(module_files) != "load_modules.R"]

  for (module_file in sort(module_files)) {
    sys.source(module_file, envir = envir)
  }

  invisible(module_files)
}
