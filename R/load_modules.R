load_modules <- function(project_dir) {
  module_files <- list.files(
    file.path(project_dir, "R"),
    pattern = "\\.R$",
    full.names = TRUE
  )
  module_files <- module_files[basename(module_files) != "load_modules.R"]

  for (module_file in sort(module_files)) {
    sys.source(module_file, envir = parent.frame())
  }

  invisible(module_files)
}
