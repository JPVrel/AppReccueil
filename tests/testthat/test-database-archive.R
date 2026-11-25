testthat::test_that("hiding a physical column preserves its data and removes it from active fields", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  column_id <- add_typed_column(connection, "age", "integer")
  DBI::dbExecute(
    connection,
    "INSERT INTO collection_records (id, created_at, payload, age) VALUES ('row-1', CURRENT_TIMESTAMP, '{}', 42)"
  )

  hide_column(connection, column_id)
  hidden <- get_column_definition(connection, column_id)
  saved_value <- DBI::dbGetQuery(
    connection,
    paste("SELECT", DBI::dbQuoteIdentifier(connection, hidden$sql_name[[1]]),
          "FROM collection_records WHERE id = 'row-1'")
  )[[hidden$sql_name[[1]]]]

  testthat::expect_true(hidden$is_hidden)
  testthat::expect_false("age" %in% list_column_definitions(connection)$name)
  testthat::expect_equal(saved_value, 42L)
})

testthat::test_that("a hidden column can be restored under its original name", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  column_id <- add_typed_column(connection, "score", "real")
  hide_column(connection, column_id)

  restored_name <- restore_column(connection, column_id)

  testthat::expect_equal(restored_name, "score")
  testthat::expect_false(get_column_definition(connection, column_id)$is_hidden)
  testthat::expect_true("score" %in% list_record_columns(connection))
})

testthat::test_that("restoring archived duplicate names increments the suffix", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  first_id <- add_typed_column(connection, "age", "integer")
  hide_column(connection, first_id)
  second_id <- add_typed_column(connection, "age", "integer")
  hide_column(connection, second_id)
  third_id <- add_typed_column(connection, "age", "integer")

  first_restored_name <- restore_column(connection, first_id)
  second_restored_name <- restore_column(connection, second_id)

  testthat::expect_equal(first_restored_name, "age_2")
  testthat::expect_equal(second_restored_name, "age_3")
  testthat::expect_true("age" %in% list_record_columns(connection))
})

testthat::test_that("hiding a source does not break formulas that reference it", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  left_id <- add_typed_column(connection, "left_value", "integer")
  right_id <- add_typed_column(connection, "right_value", "integer")
  add_derived_column(connection, "total", list(
    mode = "binary", left_id = left_id, operator = "add", right_id = right_id
  ))
  hide_column(connection, left_id)
  definitions <- list_column_definitions(connection, include_hidden = TRUE)
  hidden_sql_name <- get_column_definition(connection, left_id)$sql_name[[1]]

  calculated <- calculate_derived_columns(
    setNames(data.frame(2L), hidden_sql_name) |> transform(right_value = 3L),
    definitions
  )

  testthat::expect_equal(calculated$total, 5)
})

testthat::test_that("technical columns cannot be hidden and visible columns cannot be restored", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  column_id <- add_typed_column(connection, "score", "integer")

  testthat::expect_error(hide_column(connection, "id"), "personnalisée")
  testthat::expect_error(restore_column(connection, column_id), "n'est pas masquée")
  testthat::expect_error(rename_column_definition(connection, column_id, "id"), "existe déjà")
  hide_column(connection, column_id)
  testthat::expect_error(hide_column(connection, column_id), "déjà masquée")
  testthat::expect_error(rename_column_definition(connection, column_id, "renamed"), "doit être restaurée")
})

testthat::test_that("derived columns can be hidden and restored without physical SQL fields", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  left_id <- add_typed_column(connection, "left_value", "integer")
  right_id <- add_typed_column(connection, "right_value", "integer")
  derived_id <- add_derived_column(connection, "total", list(
    mode = "binary", left_id = left_id, operator = "add", right_id = right_id
  ))

  hide_column(connection, derived_id)
  testthat::expect_false("total" %in% list_record_columns(connection))
  testthat::expect_equal(restore_column(connection, derived_id), "total")
  testthat::expect_true("total" %in% list_column_definitions(connection)$name)
})
