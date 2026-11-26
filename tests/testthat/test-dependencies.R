testthat::test_that("runtime packages contain Shiny", {
  testthat::expect_equal(
    runtime_packages(),
    c("shiny", "DT", "DBI", "RSQLite", "yaml", "writexl", "readxl", "openssl")
  )
})

testthat::test_that("dependency profiles include their direct packages", {
  testthat::expect_setequal(dependency_packages("runtime"), runtime_packages())
  testthat::expect_true(all(c("testthat", "htmltools") %in% dependency_packages("development")))
  testthat::expect_true("RPostgres" %in% dependency_packages("postgres"))
  testthat::expect_error(dependency_packages("unknown"), "'arg' should be one of")
})

testthat::test_that("the release package library is activated before system libraries", {
  project_dir <- tempfile("project-library-")
  library_path <- project_package_library_path(project_dir)
  dir.create(library_path, recursive = TRUE)
  original_libraries <- .libPaths()
  on.exit({
    .libPaths(original_libraries)
    unlink(project_dir, recursive = TRUE)
  }, add = TRUE)

  testthat::expect_identical(
    activate_project_package_library(project_dir),
    library_path
  )
  testthat::expect_identical(.libPaths()[[1]], normalizePath(library_path))
})

testthat::test_that("release library mismatch explains its build target", {
  project_dir <- tempfile("project-release-")
  dir.create(project_dir)
  writeLines("R family: 4.6; platform: example", file.path(project_dir, "RELEASE.txt"))
  on.exit(unlink(project_dir, recursive = TRUE), add = TRUE)

  testthat::expect_error(
    activate_project_package_library(project_dir),
    "R family: 4.6; platform: example"
  )
})

testthat::test_that("missing_packages identifies unavailable packages", {
  installed_fn <- function(package) identical(package, "shiny")

  testthat::expect_equal(
    missing_packages(c("shiny", "testthat"), installed_fn),
    "testthat"
  )
})

testthat::test_that("install_dependencies installs only missing packages", {
  installed_fn <- function(package) identical(package, "shiny")
  installed <- character()
  install_fn <- function(packages, repos, configure.vars = NULL) installed <<- packages

  install_dependencies(c("shiny", "testthat"), installed_fn, install_fn)

  testthat::expect_equal(installed, "testthat")
})

testthat::test_that("OpenSSL configuration finds a Homebrew installation on macOS", {
  prefix <- tempfile("openssl-")
  dir.create(file.path(prefix, "include", "openssl"), recursive = TRUE)
  dir.create(file.path(prefix, "lib"), recursive = TRUE)
  on.exit(unlink(prefix, recursive = TRUE), add = TRUE)

  configure_vars <- openssl_install_configure_vars(
    "openssl",
    platform = "Darwin",
    homebrew_roots = prefix
  )

  testthat::expect_named(configure_vars, "openssl")
  testthat::expect_match(configure_vars[[1]], "INCLUDE_DIR=")
  testthat::expect_match(configure_vars[[1]], "LIB_DIR=")
  testthat::expect_null(openssl_install_configure_vars("openssl", platform = "Linux"))
})
