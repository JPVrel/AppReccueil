testthat::test_that("column schema helpers declare the table, protected columns, and types", {
  testthat::expect_equal(record_table_name(), "collection_records")
  testthat::expect_equal(protected_record_columns(), c("id", "created_at", "payload"))
  testthat::expect_equal(
    allowed_record_column_types(),
    c("TEXT", "INTEGER", "REAL", "NUMERIC", "DATE", "BOOLEAN")
  )
})

testthat::test_that("validate_record_column_name accepts safe names and rejects invalid ones", {
  testthat::expect_no_error(validate_record_column_name("participant_age2"))
  testthat::expect_error(validate_record_column_name("2participant"), "commencer par une lettre")
  testthat::expect_error(validate_record_column_name("participant-age"), "uniquement lettres")
  testthat::expect_error(validate_record_column_name(c("age", "sex")), "commencer par une lettre")
  testthat::expect_error(validate_record_column_name(NA_character_), "commencer par une lettre")
})

testthat::test_that("list_record_columns returns the existing SQL columns", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)

  testthat::expect_equal(
    list_record_columns(connection),
    c("id", "created_at", "payload")
  )
})

testthat::test_that("add_record_column adds an allowed SQL column", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)

  add_record_column(connection, "age", "INTEGER")

  testthat::expect_true("age" %in% list_record_columns(connection))
})

testthat::test_that("add_record_column supports every allowed SQL type", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)

  for (type in allowed_record_column_types()) {
    add_record_column(connection, paste0("field_", tolower(type)), type)
  }

  testthat::expect_length(list_record_columns(connection), 3 + length(allowed_record_column_types()))
})

testthat::test_that("stored columns cannot reuse a derived variable name", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  left_id <- add_typed_column(connection, "left_value", "integer")
  right_id <- add_typed_column(connection, "right_value", "integer")
  add_derived_column(connection, "combined_value", list(
    mode = "binary", left_id = left_id, operator = "add", right_id = right_id
  ))

  testthat::expect_error(add_typed_column(connection, "combined_value", "integer"), "existe déjà")
  testthat::expect_false("combined_value" %in% list_record_columns(connection))
})

testthat::test_that("add_record_column rejects unsafe or unsupported definitions", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)

  testthat::expect_error(
    add_record_column(connection, "age; DROP TABLE collection_records", "INTEGER"),
    "Le nom doit commencer"
  )
  testthat::expect_error(add_record_column(connection, "age", "BLOB"), "Type SQL")
  testthat::expect_error(add_record_column(connection, "id", "TEXT"), "existe déjà")
  add_record_column(connection, "Age", "INTEGER")
  testthat::expect_error(add_record_column(connection, "age", "INTEGER"), "existe déjà")
})

testthat::test_that("failed catalog registration rolls back the physical column", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  register_column_definition(connection, "legacy", "orphan_name", "text")

  testthat::expect_error(add_record_column(connection, "orphan_name", "TEXT"))
  testthat::expect_false("orphan_name" %in% list_record_columns(connection))
})

testthat::test_that("rename_record_column preserves existing values", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  add_record_column(connection, "age", "INTEGER")
  DBI::dbExecute(
    connection,
    "INSERT INTO collection_records (id, created_at, payload, age) VALUES ('row-1', CURRENT_TIMESTAMP, '{}', 42)"
  )

  rename_record_column(connection, "age", "participant_age")
  saved_value <- DBI::dbGetQuery(
    connection,
    "SELECT participant_age FROM collection_records WHERE id = 'row-1'"
  )$participant_age

  testthat::expect_equal(saved_value, 42L)
  testthat::expect_false("age" %in% list_record_columns(connection))
})

testthat::test_that("rename_record_column protects technical columns", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)

  testthat::expect_error(
    rename_record_column(connection, "payload", "answers"),
    "protégées"
  )
  testthat::expect_error(
    rename_record_column(connection, "PAYLOAD", "answers"),
    "protégées"
  )
})

testthat::test_that("rename_record_column rejects missing, duplicate, or invalid names", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  add_record_column(connection, "age", "INTEGER")

  testthat::expect_error(rename_record_column(connection, "missing", "new_name"), "n'existe pas")
  testthat::expect_error(rename_record_column(connection, "age", "id"), "existe déjà")
  testthat::expect_error(rename_record_column(connection, "age", "invalid-name"), "commencer par une lettre")
})
