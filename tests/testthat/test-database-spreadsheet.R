testthat::test_that("spreadsheet data preserves records and derived fields", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  age_id <- add_typed_column(connection, "age", "integer")
  visit_id <- add_typed_column(connection, "visit_number", "integer")
  add_derived_column(connection, "next_visit", list(
    mode = "binary",
    left_id = visit_id,
    operator = "add",
    right_id = age_id
  ))
  DBI::dbExecute(
    connection,
    "INSERT INTO collection_records (id, created_at, payload, age, visit_number) VALUES ('row-1', CURRENT_TIMESTAMP, '{}', 30, 2)"
  )

  spreadsheet <- database_spreadsheet_data(connection)

  testthat::expect_equal(nrow(spreadsheet), 1L)
  testthat::expect_equal(spreadsheet$age, 30L)
  testthat::expect_equal(spreadsheet$next_visit, 32)
  testthat::expect_false("payload" %in% names(spreadsheet))
})

testthat::test_that("spreadsheet data includes headers when there are no records", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  add_typed_column(connection, "participant_code", "text")

  spreadsheet <- database_spreadsheet_data(connection)

  testthat::expect_equal(nrow(spreadsheet), 0L)
  testthat::expect_true(all(c("id", "created_at", "participant_code") %in% names(spreadsheet)))
  testthat::expect_false("payload" %in% names(spreadsheet))
})

testthat::test_that("CSV export supports an unconnected empty spreadsheet", {
  csv_path <- tempfile(fileext = ".csv")
  on.exit(unlink(csv_path), add = TRUE)

  write_database_spreadsheet_csv(NULL, csv_path)
  exported <- utils::read.csv(csv_path, check.names = FALSE)

  testthat::expect_equal(nrow(exported), 0L)
  testthat::expect_equal(names(exported), c("id", "created_at"))
})

testthat::test_that("CSV export includes derived active fields and excludes hidden fields", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  source_id <- add_typed_column(connection, "baseline", "integer")
  followup_id <- add_typed_column(connection, "followup", "integer")
  derived_id <- add_derived_column(connection, "change", list(
    mode = "binary", left_id = followup_id, operator = "subtract", right_id = source_id
  ))
  hidden_id <- add_typed_column(connection, "private_note", "text")
  DBI::dbExecute(
    connection,
    "INSERT INTO collection_records (id, created_at, payload, baseline, followup, private_note) VALUES ('row-1', CURRENT_TIMESTAMP, '{}', 4, 9, 'do not export')"
  )
  hide_column(connection, hidden_id)
  csv_path <- tempfile(fileext = ".csv")
  on.exit(unlink(csv_path), add = TRUE)

  write_database_spreadsheet_csv(connection, csv_path)
  exported <- utils::read.csv(csv_path, check.names = FALSE)

  testthat::expect_equal(exported$change, 5)
  testthat::expect_false("private_note" %in% names(exported))
  testthat::expect_false("payload" %in% names(exported))
  testthat::expect_false(any(grepl("do not export", unlist(exported))))
  testthat::expect_true(derived_id %in% list_column_definitions(connection)$column_id)
})

testthat::test_that("spreadsheet header resolution selects active variables only", {
  definitions <- data.frame(
    column_id = c("age-id", "bmi-id", "hidden-id"),
    name = c("age", "bmi", "old_score"),
    sql_name = c("age", NA_character_, "old_score__hidden_1"),
    data_type = c("integer", "real", "real"),
    is_hidden = c(FALSE, FALSE, TRUE),
    formula = c(NA_character_, "formula", NA_character_)
  )

  testthat::expect_equal(spreadsheet_header_edit_target(definitions, "age")$column_id, "age-id")
  testthat::expect_equal(spreadsheet_header_edit_target(definitions, "bmi")$column_id, "bmi-id")
  testthat::expect_null(spreadsheet_header_edit_target(definitions, "old_score"))
  testthat::expect_null(spreadsheet_header_edit_target(definitions, "payload"))
  testthat::expect_null(spreadsheet_header_edit_target(definitions, "unknown"))
  testthat::expect_null(spreadsheet_header_edit_target(definitions, ""))
  testthat::expect_null(spreadsheet_header_edit_target(definitions, NA_character_))
  testthat::expect_null(spreadsheet_header_edit_target(definitions, c("age", "bmi")))
})

testthat::test_that("ambiguous spreadsheet headers cannot select a definition", {
  definitions <- data.frame(
    column_id = c("one", "two"),
    name = c("age", "age"),
    sql_name = c("age", "age_2"),
    data_type = c("integer", "integer"),
    is_hidden = c(FALSE, FALSE),
    formula = c(NA_character_, NA_character_)
  )

  testthat::expect_error(spreadsheet_header_edit_target(definitions, "age"), "ambigu")
})
