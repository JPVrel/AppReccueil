testthat::test_that("import readers preserve headers and normalize field names", {
  csv_path <- tempfile(fileext = ".csv")
  xlsx_path <- tempfile(fileext = ".xlsx")
  rds_path <- tempfile(fileext = ".rds")
  on.exit(unlink(c(csv_path, xlsx_path, rds_path)), add = TRUE)
  source_data <- data.frame(
    `participant code` = c("001", "002"),
    age = c("24", "31"),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )
  utils::write.csv(source_data, csv_path, row.names = FALSE, na = "")
  writexl::write_xlsx(source_data, xlsx_path)
  saveRDS(source_data, rds_path)

  csv_import <- read_database_import_file(csv_path)
  xlsx_import <- read_database_import_file(xlsx_path)
  rds_import <- read_database_import_file(rds_path)

  testthat::expect_identical(names(csv_import), c("participant_code", "age"))
  testthat::expect_identical(csv_import$participant_code, c("001", "002"))
  testthat::expect_identical(names(xlsx_import), names(csv_import))
  testthat::expect_identical(names(rds_import), names(csv_import))
})

testthat::test_that("malformed headers and unsupported input objects are rejected", {
  testthat::expect_error(normalize_import_field_names(c("age", "AGE")), "uniques")
  testthat::expect_error(normalize_import_field_names(c("age", "")), "non vide")
  testthat::expect_error(convert_database_import(data.frame(age = "1"), c(other = "integer")), "chaque colonne")

  malformed_path <- tempfile(fileext = ".xlsx")
  on.exit(unlink(malformed_path), add = TRUE)
  writeBin(charToRaw("not an xlsx archive"), malformed_path)
  testthat::expect_error(read_database_import_file(malformed_path), "classeur Excel est invalide")
})

testthat::test_that("import file size is bounded before parsing", {
  large_path <- tempfile(fileext = ".csv")
  on.exit(unlink(large_path), add = TRUE)
  connection <- file(large_path, open = "wb")
  seek(connection, where = database_import_limits()$file_bytes + 1, origin = "start")
  writeBin(as.raw(0), connection)
  close(connection)

  testthat::expect_error(
    read_database_import_file(large_path, "large.csv"),
    "limite de taille"
  )
})

testthat::test_that("CSV and XLSX row limits are enforced during parsing", {
  row_count <- database_import_limits()$rows + 1L
  source_data <- data.frame(value = seq_len(row_count))
  csv_path <- tempfile(fileext = ".csv")
  xlsx_path <- tempfile(fileext = ".xlsx")
  on.exit(unlink(c(csv_path, xlsx_path)), add = TRUE)
  utils::write.csv(source_data, csv_path, row.names = FALSE)
  writexl::write_xlsx(source_data, xlsx_path)

  testthat::expect_error(read_database_import_file(csv_path), "50 000 lignes")
  testthat::expect_error(read_database_import_file(xlsx_path), "50 000 lignes")
})

testthat::test_that("column and cell limits reduce parser row allowance before reading", {
  testthat::expect_equal(import_row_limit(1L), 50000)
  testthat::expect_equal(import_row_limit(10L), 50000)
  testthat::expect_equal(import_row_limit(500L), 2000)
  testthat::expect_error(import_row_limit(501L), "500 colonnes")

  csv_path <- tempfile(fileext = ".csv")
  xlsx_path <- tempfile(fileext = ".xlsx")
  on.exit(unlink(c(csv_path, xlsx_path)), add = TRUE)
  wide <- as.data.frame(setNames(rep(list(character()), 501L), paste0("field", seq_len(501L))))
  utils::write.csv(wide, csv_path, row.names = FALSE)
  writexl::write_xlsx(wide, xlsx_path)

  testthat::expect_error(read_database_import_file(csv_path), "500 colonnes")
  testthat::expect_error(read_database_import_file(xlsx_path), "500 colonnes")
})

testthat::test_that("RDS import rejects serialized objects that are not data frames", {
  rds_path <- tempfile(fileext = ".rds")
  on.exit(unlink(rds_path), add = TRUE)
  saveRDS(list(value = seq_len(10)), rds_path)

  testthat::expect_error(read_database_import_file(rds_path), "au moins une colonne")
})

testthat::test_that("encrypted spreadsheet exports can be re-imported with their password", {
  plain_path <- tempfile(fileext = ".csv")
  encrypted_path <- tempfile(fileext = ".enc")
  on.exit(unlink(c(plain_path, encrypted_path)), add = TRUE)
  utils::write.csv(data.frame(participant_code = "001"), plain_path, row.names = FALSE)
  encrypt_file_with_password(plain_path, encrypted_path, "import-export-password")

  imported <- read_database_import_upload(encrypted_path, "recueil.csv.enc", "import-export-password")

  testthat::expect_identical(imported$participant_code, "001")
  testthat::expect_error(
    read_database_import_upload(encrypted_path, "recueil.csv.enc", "wrong-password-123"),
    "Mot de passe incorrect"
  )
})

testthat::test_that("import type conversion validates values and preserves missing data", {
  imported <- data.frame(
    age = c("12", ""),
    visit_date = c("2026-11-25", NA_character_),
    eligible = c("oui", "false"),
    stringsAsFactors = FALSE
  )

  converted <- convert_database_import(imported, c(age = "integer", visit_date = "date", eligible = "boolean"))

  testthat::expect_identical(converted$age, c(12L, NA_integer_))
  testthat::expect_identical(converted$visit_date, as.Date(c("2026-11-25", NA)))
  testthat::expect_identical(converted$eligible, c(TRUE, FALSE))
  testthat::expect_error(
    convert_database_import(data.frame(age = "12.5"), c(age = "integer")),
    "pas entière"
  )
  testthat::expect_error(
    convert_database_import(data.frame(age = "2147483648"), c(age = "integer")),
    "hors de la plage"
  )
  testthat::expect_error(
    convert_database_import(data.frame(age = "-2147483649"), c(age = "integer")),
    "hors de la plage"
  )
  testthat::expect_error(
    convert_database_import(data.frame(age = "-2147483648"), c(age = "integer")),
    "hors de la plage"
  )
  testthat::expect_error(
    convert_database_import(data.frame(age = "2147483647.0000001"), c(age = "integer")),
    "pas entière"
  )
  testthat::expect_identical(
    convert_database_import(data.frame(age = "2147483647.0"), c(age = "integer"))$age,
    2147483647L
  )
  testthat::expect_identical(
    convert_database_import(data.frame(age = "0e-99999"), c(age = "integer"))$age,
    0L
  )
  testthat::expect_error(
    convert_database_import(data.frame(age = "Inf"), c(age = "integer")),
    "pas entière"
  )
})

testthat::test_that("new database imports create typed fields, categories, and records", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  imported <- data.frame(
    participant_code = c("P001", "P002"),
    group = c("control", "treatment"),
    age = c("30", "41"),
    stringsAsFactors = FALSE
  )

  create_imported_database(
    connection,
    imported,
    c(participant_code = "text", group = "categorical", age = "integer")
  )
  records <- read_collection_records(connection)
  definitions <- list_column_definitions(connection)
  group_definition <- definitions[definitions$name == "group", , drop = FALSE]

  testthat::expect_equal(nrow(records), 2L)
  testthat::expect_equal(records$age, c(30L, 41L))
  testthat::expect_equal(list_category_entries(connection, group_definition$column_id[[1]])$code, c("control", "treatment"))
  testthat::expect_identical(anyDuplicated(records$id), 0L)
})

testthat::test_that("SQL-looking and HTML-looking imported values remain literal data", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  sql_text <- "P1'); DROP TABLE collection_records; --"
  html_text <- "<img src=x onerror=alert(1)>"
  imported <- data.frame(
    participant_code = sql_text,
    note = html_text,
    stringsAsFactors = FALSE
  )

  create_imported_database(
    connection,
    imported,
    c(participant_code = "text", note = "text")
  )

  records <- read_collection_records(connection)
  testthat::expect_true(DBI::dbExistsTable(connection, "collection_records"))
  testthat::expect_identical(records$participant_code, sql_text)
  testthat::expect_identical(records$note, html_text)
})

testthat::test_that("database import rolls back columns when a later field fails", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  imported <- data.frame(age = "30", Age = "31", check.names = FALSE)

  testthat::expect_error(
    create_imported_database(connection, imported, c(age = "integer", Age = "integer")),
    "existe déjà"
  )
  testthat::expect_false("age" %in% list_record_columns(connection))
  testthat::expect_equal(nrow(list_column_definitions(connection)), 0L)

  create_imported_database(connection, data.frame(age = "42"), c(age = "integer"))
  testthat::expect_equal(read_collection_records(connection)$age, 42L)
})

testthat::test_that("merge planning fills missing values, identifies conflicts, and adds rows", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  add_typed_column(connection, "participant_code", "text")
  add_typed_column(connection, "age", "integer")
  add_typed_column(connection, "note", "text")
  DBI::dbExecute(
    connection,
    "INSERT INTO collection_records (id, created_at, payload, participant_code, age, note) VALUES ('row-existing', CURRENT_TIMESTAMP, '{}', 'P001', 30, NULL)"
  )
  imported <- data.frame(
    participant_code = c("P001", "P002"),
    age = c("31", "42"),
    note = c("filled from import", "new row"),
    unknown_field = c("ignored", "ignored"),
    stringsAsFactors = FALSE
  )

  plan <- prepare_import_merge(connection, imported, "participant_code")
  result <- apply_import_merge(connection, plan, "imported")
  records <- read_collection_records(connection)

  testthat::expect_equal(result$inserted, 1L)
  testthat::expect_equal(result$filled, 1L)
  testthat::expect_equal(result$conflicts, 1L)
  testthat::expect_equal(nrow(records), 2L)
  testthat::expect_equal(records$age[records$participant_code == "P001"], 31L)
  testthat::expect_equal(records$note[records$participant_code == "P001"], "filled from import")
  testthat::expect_equal(records$age[records$participant_code == "P002"], 42L)
  testthat::expect_false("unknown_field" %in% names(records))
})

testthat::test_that("merge requires a unique key and an explicit choice for each conflict", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  add_typed_column(connection, "participant_code", "text")
  add_typed_column(connection, "age", "integer")
  DBI::dbExecute(
    connection,
    "INSERT INTO collection_records (id, created_at, payload, participant_code, age) VALUES ('row-existing', CURRENT_TIMESTAMP, '{}', 'P001', 30)"
  )
  duplicate_import <- data.frame(participant_code = c("P001", "P001"), age = c("30", "31"))
  conflicting_import <- data.frame(participant_code = "P001", age = "31")

  testthat::expect_error(prepare_import_merge(connection, duplicate_import, "participant_code"), "unique")
  plan <- prepare_import_merge(connection, conflicting_import, "participant_code")
  testthat::expect_error(apply_import_merge(connection, plan), "Arbitre chaque conflit")
})

testthat::test_that("merge plans are rejected when the database changed after comparison", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  add_typed_column(connection, "participant_code", "text")
  add_typed_column(connection, "age", "integer")
  DBI::dbExecute(
    connection,
    "INSERT INTO collection_records (id, created_at, payload, participant_code, age) VALUES ('row-existing', CURRENT_TIMESTAMP, '{}', 'P001', 30)"
  )
  imported <- data.frame(participant_code = "P001", age = "31", stringsAsFactors = FALSE)
  plan <- prepare_import_merge(connection, imported, "participant_code")
  DBI::dbExecute(connection, "UPDATE collection_records SET age = 45 WHERE id = 'row-existing'")

  testthat::expect_error(
    apply_import_merge(connection, plan, "imported"),
    "La base a changé depuis la comparaison"
  )
  testthat::expect_equal(
    DBI::dbGetQuery(connection, "SELECT age FROM collection_records WHERE id = 'row-existing'")$age,
    45L
  )
})