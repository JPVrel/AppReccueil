project_dir <- normalizePath(file.path(testthat::test_path(), "..", ".."))
if (!identical(Sys.getenv("R_COVR"), "true")) {
  source(file.path(project_dir, "R", "load_modules.R"))
  load_modules(project_dir)
}
