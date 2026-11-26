project_package_library_path <- function(project_dir) {
  r_minor <- strsplit(R.version$minor, ".", fixed = TRUE)[[1]][[1]]
  r_family <- paste(R.version$major, r_minor, sep = ".")
  operating_system <- switch(
    Sys.info()[["sysname"]],
    Darwin = "macos",
    Windows = "windows",
    Linux = "linux",
    tolower(Sys.info()[["sysname"]])
  )

  file.path(
    project_dir,
    "renv",
    "library",
    operating_system,
    paste0("R-", r_family),
    R.version$arch
  )
}

activate_project_package_library <- function(project_dir) {
  library_path <- project_package_library_path(project_dir)
  release_marker <- file.path(project_dir, "RELEASE.txt")

  if (file.exists(release_marker) && !dir.exists(library_path)) {
    release_info <- paste(readLines(release_marker, warn = FALSE), collapse = "; ")
    stop(
      "Cette release n'a pas de bibliothèque compatible avec cette installation R. ",
      release_info
    )
  }

  if (dir.exists(library_path)) {
    .libPaths(unique(c(library_path, .libPaths())))
  }

  invisible(library_path)
}