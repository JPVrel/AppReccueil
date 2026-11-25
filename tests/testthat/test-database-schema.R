testthat::test_that("database_schema_sql defines both application tables", {
  statements <- database_schema_sql()

  testthat::expect_length(statements, 4)
  testthat::expect_true(any(grepl("app_metadata", statements)))
  testthat::expect_true(any(grepl("collection_records", statements)))
  testthat::expect_true(any(grepl("column_definitions", statements)))
  testthat::expect_true(any(grepl("category_dictionary", statements)))
})

testthat::test_that("initialize_database creates the application tables", {
  config <- list(
    mode = "local",
    local = list(path = file.path(tempdir(), "schema.sqlite"))
  )
  connection <- connect_database(config)
  on.exit(disconnect_database(connection), add = TRUE)

  initialize_database(connection)

  testthat::expect_true(
    all(c(
      "app_metadata",
      "collection_records",
      "column_definitions",
      "category_dictionary"
    ) %in% DBI::dbListTables(connection))
  )
})
