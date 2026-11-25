testthat::test_that("load_modules loads modules from nested domain folders", {
  project_dir <- tempfile("module-project-")
  modules_dir <- file.path(project_dir, "R", "database")
  dir.create(modules_dir, recursive = TRUE)
  writeLines(
    "nested_module_value <- function() 42L",
    file.path(modules_dir, "nested_module.R")
  )
  target_environment <- new.env(parent = globalenv())

  load_modules(project_dir, envir = target_environment)

  testthat::expect_equal(target_environment$nested_module_value(), 42L)
})
