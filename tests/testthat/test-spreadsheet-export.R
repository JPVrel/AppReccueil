testthat::test_that("spreadsheet export directory defaults to the project exports folder", {
  project_dir <- tempfile("project-")

  testthat::expect_equal(
    database_spreadsheet_export_dir(project_dir),
    file.path(project_dir, "exports")
  )
})

testthat::test_that("spreadsheet export filenames are timestamped and collision-safe", {
  export_dir <- tempfile("exports-")
  on.exit(unlink(export_dir, recursive = TRUE), add = TRUE)
  export_time <- as.POSIXct("2026-11-25 12:34:56", tz = "UTC")

  first <- next_spreadsheet_export_path(export_dir, export_time)
  testthat::expect_true(dir.exists(export_dir))
  testthat::expect_true(file.create(first))
  second <- next_spreadsheet_export_path(export_dir, export_time)

  testthat::expect_match(basename(first), "^recueil-20261125-123456\\.csv$")
  testthat::expect_equal(basename(second), "recueil-20261125-123456-2.csv")
  testthat::expect_false(file.exists(second))
})

testthat::test_that("archive_database_spreadsheet_csv writes a protected, calculated snapshot", {
  connection <- DBI::dbConnect(RSQLite::SQLite(), ":memory:")
  on.exit(DBI::dbDisconnect(connection), add = TRUE)
  initialize_database(connection)
  baseline_id <- add_typed_column(connection, "baseline", "integer")
  followup_id <- add_typed_column(connection, "followup", "integer")
  add_derived_column(connection, "change", list(
    mode = "binary",
    left_id = followup_id,
    operator = "subtract",
    right_id = baseline_id
  ))
  private_id <- add_typed_column(connection, "private_note", "text")
  DBI::dbExecute(
    connection,
    "INSERT INTO collection_records (id, created_at, payload, baseline, followup, private_note) VALUES ('row-1', CURRENT_TIMESTAMP, '{}', 4, 9, 'private')"
  )
  hide_column(connection, private_id)
  export_dir <- tempfile("exports-")
  on.exit(unlink(export_dir, recursive = TRUE), add = TRUE)

  export_path <- archive_database_spreadsheet_csv(
    connection,
    export_dir,
    export_time = as.POSIXct("2026-11-25 12:34:56", tz = "UTC")
  )
  exported <- utils::read.csv(export_path, check.names = FALSE)

  testthat::expect_true(file.exists(export_path))
  testthat::expect_true("change" %in% names(exported))
  testthat::expect_equal(exported$change, 5)
  testthat::expect_false("payload" %in% names(exported))
  testthat::expect_false("private_note" %in% names(exported))
  testthat::expect_false(any(grepl("private", unlist(exported))))
})
