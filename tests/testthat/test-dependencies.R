testthat::test_that("runtime packages contain Shiny", {
  testthat::expect_equal(runtime_packages(), c("shiny", "DT", "DBI", "RSQLite", "yaml"))
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
  install_fn <- function(packages, repos) installed <<- packages

  install_dependencies(c("shiny", "testthat"), installed_fn, install_fn)

  testthat::expect_equal(installed, "testthat")
})
