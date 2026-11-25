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

  first <- next_spreadsheet_export_path(export_dir, export_time, "csv")
  testthat::expect_true(dir.exists(export_dir))
  testthat::expect_true(file.exists(first))
  second <- next_spreadsheet_export_path(export_dir, export_time, "csv")
  xlsx <- next_spreadsheet_export_path(export_dir, export_time, "xlsx")
  rds <- next_spreadsheet_export_path(export_dir, export_time, "rds")

  testthat::expect_match(basename(first), "^recueil-20261125-123456\\.csv$")
  testthat::expect_equal(basename(second), "recueil-20261125-123456-2.csv")
  testthat::expect_match(basename(xlsx), "^recueil-20261125-123456\\.xlsx$")
  testthat::expect_match(basename(rds), "^recueil-20261125-123456\\.rds$")
  testthat::expect_true(file.exists(second))
  testthat::expect_length(unique(c(first, second, xlsx, rds)), 4L)

  cluster <- parallel::makePSOCKcluster(2L)
  on.exit(parallel::stopCluster(cluster), add = TRUE)
  parallel::clusterExport(
    cluster,
    c("next_spreadsheet_export_path", "reserve_spreadsheet_export_path"),
    envir = globalenv()
  )
  parallel_paths <- unlist(parallel::parLapply(
    cluster,
    seq_len(12),
    function(index, path, time) next_spreadsheet_export_path(path, time, "rds"),
    path = export_dir,
    time = export_time
  ))
  testthat::expect_length(unique(parallel_paths), 12L)
  testthat::expect_true(all(file.exists(parallel_paths)))
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
  add_typed_column(connection, "comment", "text")
  DBI::dbExecute(
    connection,
    "INSERT INTO collection_records (id, created_at, payload, baseline, followup, private_note, comment) VALUES ('row-1', CURRENT_TIMESTAMP, '{}', 4, 9, 'private', ' =2+2')"
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
  testthat::expect_equal(exported$comment, "' =2+2")

  xlsx_path <- archive_database_spreadsheet(
    connection,
    export_dir,
    "xlsx",
    export_time = as.POSIXct("2026-11-25 12:34:56", tz = "UTC")
  )
  workbook_files <- utils::unzip(xlsx_path, list = TRUE)$Name
  workbook_dir <- tempfile("workbook-")
  dir.create(workbook_dir)
  on.exit(unlink(workbook_dir, recursive = TRUE), add = TRUE)
  utils::unzip(xlsx_path, exdir = workbook_dir)
  worksheet_xml <- paste(
    readLines(file.path(workbook_dir, "xl", "worksheets", "sheet1.xml"), warn = FALSE),
    collapse = ""
  )
  shared_strings_xml <- paste(
    readLines(file.path(workbook_dir, "xl", "sharedStrings.xml"), warn = FALSE),
    collapse = ""
  )

  testthat::expect_true("xl/worksheets/sheet1.xml" %in% workbook_files)
  testthat::expect_match(shared_strings_xml, "row-1")
  testthat::expect_match(shared_strings_xml, "change")
  testthat::expect_false(grepl("payload", shared_strings_xml))
  testthat::expect_match(worksheet_xml, "<c r=\"F2\"><v>5</v></c>")
  testthat::expect_false(grepl("<f>", worksheet_xml))
  testthat::expect_false(grepl("private_note|private", shared_strings_xml))

  rds_path <- archive_database_spreadsheet(
    connection,
    export_dir,
    "rds",
    export_time = as.POSIXct("2026-11-25 12:34:56", tz = "UTC")
  )
  exported_rds <- readRDS(rds_path)
  testthat::expect_s3_class(exported_rds, "data.frame")
  testthat::expect_equal(exported_rds$change, 5)
  testthat::expect_false("payload" %in% names(exported_rds))
  testthat::expect_false("private_note" %in% names(exported_rds))
  testthat::expect_equal(exported_rds$comment, " =2+2")
})

testthat::test_that("download handler archives and serves its selected format", {
  export_dir <- tempfile("exports-")
  on.exit(unlink(export_dir, recursive = TRUE), add = TRUE)
  handler <- database_spreadsheet_download_handler(NULL, export_dir, "rds")
  download <- new.env(parent = emptyenv())
  fake_session <- list(registerDownload = function(name, filename, contentType, content) {
    download$callbacks <- list(filename = filename, content = content)
  })
  handler(fake_session, "download_rds")
  download_name <- download$callbacks$filename()
  download_path <- tempfile(fileext = ".rds")
  on.exit(unlink(download_path), add = TRUE)

  download$callbacks$content(download_path)
  archived_path <- file.path(export_dir, download_name)

  testthat::expect_true(file.exists(archived_path))
  testthat::expect_identical(readRDS(download_path), readRDS(archived_path))
  testthat::expect_s3_class(readRDS(download_path), "data.frame")
})
