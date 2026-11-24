testthat::test_that("database_value_or provides a fallback", {
  testthat::expect_equal(database_value_or(NULL, "local"), "local")
  testthat::expect_equal(database_value_or("remote", "local"), "remote")
})

testthat::test_that("read_database_config resolves the local SQLite path", {
  config <- read_database_config(file.path(project_dir, "config", "database.yml"))

  testthat::expect_equal(config$mode, "local")
  testthat::expect_true(grepl("recueil.sqlite$", config$local$path))
  testthat::expect_equal(config$project_dir, project_dir)
})

testthat::test_that("read_database_config rejects an unknown mode", {
  config_path <- file.path(tempdir(), "invalid-database.yml")
  yaml::write_yaml(list(database = list(mode = "unknown")), config_path)

  testthat::expect_error(
    read_database_config(config_path),
    "local.*remote"
  )
})
