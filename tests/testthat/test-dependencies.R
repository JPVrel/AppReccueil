testthat::test_that("runtime packages contain Shiny", {
  testthat::expect_equal(
    runtime_packages(),
    c("shiny", "DT", "DBI", "RSQLite", "yaml", "writexl", "readxl", "openssl")
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
