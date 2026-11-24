testthat::test_that("script_directory extracts the script directory", {
  temporary_file <- file.path(tempdir(), "app.R")

  testthat::expect_equal(
    script_directory(paste0("--file=", temporary_file)),
    dirname(normalizePath(temporary_file, mustWork = FALSE))
  )
})

testthat::test_that("create_app_config builds the local server configuration", {
  config <- create_app_config("/tmp/project", host = "localhost", port = 8123)

  testthat::expect_equal(config$host, "localhost")
  testthat::expect_equal(config$port, 8123L)
  testthat::expect_equal(config$app_url, "http://localhost:8123")
  testthat::expect_equal(config$shiny_runner, "/tmp/project/shiny/run_app.R")
})
