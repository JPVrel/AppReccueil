testthat::test_that("read_collection_records calculates derived values on every read", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  left_id <- add_typed_column(connection, "left_value", "integer")
  right_id <- add_typed_column(connection, "right_value", "integer")
  add_derived_column(connection, "total", list(
    mode = "binary", left_id = left_id, operator = "add", right_id = right_id
  ))
  DBI::dbExecute(
    connection,
    "INSERT INTO collection_records (id, created_at, payload, left_value, right_value) VALUES ('row-1', CURRENT_TIMESTAMP, '{}', 2, 3)"
  )

  first_read <- read_collection_records(connection)
  DBI::dbExecute(connection, "UPDATE collection_records SET left_value = 10 WHERE id = 'row-1'")
  second_read <- read_collection_records(connection)

  testthat::expect_equal(first_read$total, 5)
  testthat::expect_equal(second_read$total, 13)
})

testthat::test_that("read_collection_records hides archived sources but still calculates from them", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  left_id <- add_typed_column(connection, "left_value", "integer")
  right_id <- add_typed_column(connection, "right_value", "integer")
  add_derived_column(connection, "total", list(
    mode = "binary", left_id = left_id, operator = "add", right_id = right_id
  ))
  DBI::dbExecute(
    connection,
    "INSERT INTO collection_records (id, created_at, payload, left_value, right_value) VALUES ('row-1', CURRENT_TIMESTAMP, '{}', 2, 3)"
  )
  hide_column(connection, left_id)

  records <- read_collection_records(connection)

  testthat::expect_false("left_value" %in% names(records))
  testthat::expect_false(grepl("__hidden_", paste(names(records), collapse = " ")))
  testthat::expect_equal(records$total, 5)
})

testthat::test_that("read_collection_records can calculate through a hidden derived field", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  first_id <- add_typed_column(connection, "first_value", "integer")
  second_id <- add_typed_column(connection, "second_value", "integer")
  subtotal_id <- add_derived_column(connection, "subtotal", list(
    mode = "binary", left_id = first_id, operator = "add", right_id = second_id
  ))
  add_derived_column(connection, "weighted_total", list(
    mode = "binary", left_id = subtotal_id, operator = "multiply", right_id = second_id
  ))
  DBI::dbExecute(
    connection,
    "INSERT INTO collection_records (id, created_at, payload, first_value, second_value) VALUES ('row-1', CURRENT_TIMESTAMP, '{}', 2, 3)"
  )
  hide_column(connection, subtotal_id)

  records <- read_collection_records(connection)

  testthat::expect_false("subtotal" %in% names(records))
  testthat::expect_equal(records$weighted_total, 15)
})

testthat::test_that("formulas stay attached to source identity after rename, reuse, and restore", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  original_id <- add_typed_column(connection, "measure", "integer")
  increment_id <- add_typed_column(connection, "increment", "integer")
  add_derived_column(connection, "adjusted_measure", list(
    mode = "binary", left_id = original_id, operator = "add", right_id = increment_id
  ))
  DBI::dbExecute(
    connection,
    "INSERT INTO collection_records (id, created_at, payload, measure, increment) VALUES ('row-1', CURRENT_TIMESTAMP, '{}', 7, 2)"
  )

  rename_column_definition(connection, original_id, "baseline_measure")
  renamed_read <- read_collection_records(connection)
  testthat::expect_equal(renamed_read$adjusted_measure, 9)

  hide_column(connection, original_id)
  replacement_id <- add_typed_column(connection, "baseline_measure", "integer")
  DBI::dbExecute(
    connection,
    "UPDATE collection_records SET baseline_measure = 100 WHERE id = 'row-1'"
  )
  reused_read <- read_collection_records(connection)
  testthat::expect_equal(reused_read$baseline_measure, 100L)
  testthat::expect_equal(reused_read$adjusted_measure, 9)

  restored_name <- restore_column(connection, original_id)
  restored_read <- read_collection_records(connection)
  testthat::expect_equal(restored_name, "baseline_measure_2")
  testthat::expect_equal(restored_read$baseline_measure_2, 7L)
  testthat::expect_equal(restored_read$adjusted_measure, 9)
  testthat::expect_true(replacement_id %in% list_column_definitions(connection)$column_id)
})

testthat::test_that("read_collection_records returns active column names for an empty table", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  add_typed_column(connection, "visit_date", "date")

  records <- read_collection_records(connection)

  testthat::expect_equal(nrow(records), 0L)
  testthat::expect_true(all(c("id", "created_at", "payload", "visit_date") %in% names(records)))
})
