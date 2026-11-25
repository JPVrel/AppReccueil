testthat::test_that("database initialization creates the column catalog tables", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)

  initialize_database(connection)

  testthat::expect_true(
    all(c("column_definitions", "category_dictionary") %in% DBI::dbListTables(connection))
  )
  testthat::expect_equal(nrow(list_column_definitions(connection)), 0L)
})

testthat::test_that("initialize_database registers existing custom SQL columns", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  DBI::dbExecute(
    connection,
    paste(
      "CREATE TABLE collection_records (",
      "id TEXT PRIMARY KEY, created_at TIMESTAMP NOT NULL, payload TEXT NOT NULL,",
      "legacy_score REAL)"
    )
  )

  initialize_database(connection)
  definitions <- list_column_definitions(connection)

  testthat::expect_equal(definitions$name, "legacy_score")
  testthat::expect_equal(definitions$sql_name, "legacy_score")
  testthat::expect_equal(definitions$data_type, "real")
})

testthat::test_that("register_column_definition assigns unique stable identifiers", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)

  first_id <- register_column_definition(connection, "first", "first", "text")
  second_id <- register_column_definition(connection, "second", "second", "text")

  testthat::expect_type(first_id, "character")
  testthat::expect_false(identical(first_id, second_id))
  testthat::expect_equal(get_column_definition(connection, first_id)$name, "first")
})

testthat::test_that("list_column_definitions can include hidden definitions", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  register_column_definition(connection, "visible", "visible", "text")
  register_column_definition(connection, "hidden", "hidden", "text", is_hidden = TRUE)

  testthat::expect_equal(list_column_definitions(connection)$name, "visible")
  testthat::expect_setequal(
    list_column_definitions(connection, include_hidden = TRUE)$name,
    c("visible", "hidden")
  )
})
