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

testthat::test_that("record IDs use the configured prefix and increment past existing entries", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)

  testthat::expect_identical(new_collection_record_id(connection, "SUBJ-", 12), "SUBJ-12")
  create_unencrypted_database_record <- function(record_id, is_deleted = 0L) {
    DBI::dbExecute(
      connection,
      "INSERT INTO collection_records (id, created_at, payload, is_deleted) VALUES (?, CURRENT_TIMESTAMP, '{}', ?)",
      params = list(record_id, as.integer(is_deleted))
    )
  }
  create_unencrypted_database_record("SUBJ-12")
  create_unencrypted_database_record("SUBJ-13")

  testthat::expect_identical(new_collection_record_id(connection, "SUBJ-", 12), "SUBJ-14")
  create_unencrypted_database_record("SUBJ-20")
  create_unencrypted_database_record("SUBJ-30", is_deleted = 1L)

  testthat::expect_identical(new_collection_record_id(connection, "SUBJ-", 12), "SUBJ-21")
  testthat::expect_error(new_collection_record_id(connection, "bad prefix", 1), "sans espace")
  testthat::expect_error(new_collection_record_id(connection, "P", 0), "entier positif")
})

testthat::test_that("questionnaire records can be created, updated, masked, and restored", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  add_typed_column(connection, "participant_code", "text")
  add_typed_column(connection, "age", "integer")
  add_typed_column(connection, "visit_date", "date")
  category_id <- add_typed_column(connection, "group", "categorical")
  add_category_entry(connection, category_id, "control", "Control")

  record_id <- insert_collection_record(connection, list(
    participant_code = "P001",
    age = "34",
    visit_date = "2026-11-25",
    group = "control"
  ))
  testthat::expect_match(record_id, "^row_")
  record <- read_collection_records(connection)
  testthat::expect_equal(nrow(record), 1L)
  testthat::expect_equal(record$age, 34L)
  testthat::expect_identical(record$visit_date, as.Date("2026-11-25"))

  testthat::expect_error(
    insert_collection_record(connection, list(
      participant_code = "P002",
      age = "35",
      visit_date = "2026-11-25",
      group = "not-in-dictionary"
    ), "row-other"),
    "ne figure pas dans son dictionnaire"
  )
  testthat::expect_error(
    insert_collection_record(connection, list(
      participant_code = "P002",
      age = "35",
      visit_date = "2026-11-25",
      group = "control"
    ), record_id),
    "ID existe déjà"
  )

  update_collection_record(connection, record_id, "row-renamed", list(
    participant_code = "P001",
    age = "36",
    visit_date = "2026-11-25",
    group = "control"
  ))
  testthat::expect_equal(read_collection_records(connection)$age, 36L)
  testthat::expect_error(
    update_collection_record(connection, "row-renamed", "bad/id", list(
      participant_code = "P001", age = "36", visit_date = "2026-11-25", group = "control"
    )),
    "L'ID doit"
  )

  mask_collection_record(connection, "row-renamed")
  second_id <- insert_collection_record(connection, list(
    participant_code = "P002",
    age = "28",
    visit_date = "2026-11-25",
    group = "control"
  ), "row-second")
  testthat::expect_equal(nrow(read_collection_records(connection)), 1L)
  deleted <- list_deleted_collection_records(connection)
  testthat::expect_equal(deleted$id, "row-renamed")
  testthat::expect_error(update_collection_record(connection, "row-renamed", "row-renamed", list(
    participant_code = "P001", age = "37", visit_date = "2026-11-25", group = "control"
  )), "masquée")
  testthat::expect_error(
    restore_collection_record(connection, "row-renamed", second_id),
    "ID existe déjà"
  )
  restore_collection_record(connection, "row-renamed", "row-restored")
  testthat::expect_true("row-restored" %in% read_collection_records(connection)$id)
  testthat::expect_true("row-second" %in% read_collection_records(connection)$id)
})

testthat::test_that("database initialization adds the soft-delete marker to an old schema", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  DBI::dbExecute(
    connection,
    "CREATE TABLE collection_records (id VARCHAR(36) PRIMARY KEY, created_at TIMESTAMP NOT NULL, payload TEXT NOT NULL)"
  )
  DBI::dbExecute(
    connection,
    "INSERT INTO collection_records (id, created_at, payload) VALUES ('old-row', CURRENT_TIMESTAMP, '{}')"
  )

  initialize_database(connection)

  testthat::expect_true("is_deleted" %in% list_record_columns(connection))
  testthat::expect_equal(read_collection_records(connection)$id, "old-row")
  testthat::expect_equal(list_deleted_collection_records(connection), read_collection_records(connection)[0, ])
})

testthat::test_that("questionnaire rejects impossible text and date edge cases", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  add_typed_column(connection, "note", "text")

  testthat::expect_error(
    insert_collection_record(connection, list(note = strrep("A", 10001)), "row-long"),
    "10 000 caractères"
  )
})
