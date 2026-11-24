testthat::test_that("connect_database opens a local SQLite database", {
  config <- list(
    mode = "local",
    local = list(path = file.path(tempdir(), "connection.sqlite"))
  )

  connection <- connect_database(config)
  testthat::expect_true(DBI::dbIsValid(connection))
  disconnect_database(connection)
  testthat::expect_false(DBI::dbIsValid(connection))
})

testthat::test_that("connect_database reports a missing remote driver", {
  config <- list(
    mode = "remote",
    remote = list(
      driver_package = "MissingDatabaseDriver",
      driver_class = "Driver"
    )
  )

  testthat::expect_error(
    connect_database(config),
    "MissingDatabaseDriver"
  )
})
