project_dir <- normalizePath(file.path(testthat::test_path(), "..", ".."))
source(file.path(project_dir, "R", "load_modules.R"))
load_modules(project_dir)
