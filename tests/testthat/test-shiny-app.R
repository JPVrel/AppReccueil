testthat::test_that("build_shiny_app returns a Shiny application", {
  testthat::expect_s3_class(build_shiny_app(), "shiny.appobj")
})

testthat::test_that("the UI renders the database column-management tab", {
  ui_html <- htmltools::renderTags(build_app_ui())$html

  testthat::expect_match(ui_html, "Base de données")
  testthat::expect_match(ui_html, "Importer des données")
  testthat::expect_match(ui_html, "database_overview")
  testthat::expect_match(ui_html, "import_file")
  testthat::expect_match(ui_html, "Gestion des variables")
  testthat::expect_match(ui_html, "database_spreadsheet")
  testthat::expect_match(ui_html, "add_column")
  testthat::expect_match(ui_html, "rename_column")
  testthat::expect_match(ui_html, "active_variables_table")
  testthat::expect_match(ui_html, "archived_variables_table")
  testthat::expect_match(ui_html, "category_entries")

  shiny::testServer(build_app_server(), {
    import_status <- htmltools::renderTags(output$import_file_status)$html
    testthat::expect_match(import_status, "source de confiance")
  })
})

testthat::test_that("a Shiny session creates, closes, and reopens an encrypted database", {
  project_dir <- tempfile("project-")
  data_dir <- file.path(project_dir, "data")
  dir.create(data_dir, recursive = TRUE)
  database_config <- list(
    mode = "local",
    project_dir = project_dir,
    local = list(path = file.path(data_dir, "recueil.sqlite"))
  )
  vault_path <- file.path(data_dir, "test_base.sqlite.enc")
  password <- "this-is-a-test-password"
  import_path <- tempfile()
  on.exit(unlink(c(project_dir, import_path), recursive = TRUE), add = TRUE)
  utils::write.csv(
    data.frame(`participant code` = "P001", age = "34", check.names = FALSE),
    import_path,
    row.names = FALSE
  )

  shiny::testServer(build_app_server(database_config), {
    testthat::expect_match(output$database_overview, "Bases chiffrées disponibles : 0")
    session$setInputs(import_file = list(
      name = "source.csv",
      datapath = import_path,
      size = file.info(import_path)$size,
      type = "text/csv"
    ))
    type_controls <- htmltools::renderTags(output$import_type_controls)$html
    testthat::expect_match(type_controls, "participant_code")
    session$setInputs(
      import_type__participant_code = "text",
      import_type__age = "integer"
    )
    session$setInputs(
      new_database_name = "test_base",
      new_database_password = password,
      new_database_password_confirm = password,
      create_database = 1
    )
    testthat::expect_match(output$database_overview, "test_base.sqlite.enc")

    session$setInputs(
      new_column_name = "note",
      new_column_type = "integer",
      add_column = 1
    )
    testthat::expect_match(output$column_status, "Colonne ajoutée : note")
    session$setInputs(close_database = 1)
    testthat::expect_match(output$database_workflow_status, "Base rechiffrée et fermée")
    testthat::expect_true(file.exists(vault_path))
  })

  imported_vault <- open_database_vault(vault_path, password)
  imported_records <- read_collection_records(imported_vault$connection)
  testthat::expect_equal(imported_records$participant_code, "P001")
  testthat::expect_equal(imported_records$age, 34L)
  close_database_vault(imported_vault)

  shiny::testServer(build_app_server(database_config), {
    session$setInputs(
      database_to_open = vault_path,
      open_database_password = password,
      open_database = 1
    )
    testthat::expect_match(output$database_overview, "test_base.sqlite.enc")
    session$setInputs(
      new_column_name = "participant_age",
      new_column_type = "integer",
      add_column = 1
    )
    testthat::expect_match(output$column_status, "Colonne ajoutée : participant_age")
    session$setInputs(close_database = 1)
  })
})

testthat::test_that("a new database can be created and opened without a password", {
  project_dir <- tempfile("passwordless-project-")
  data_dir <- file.path(project_dir, "data")
  dir.create(data_dir, recursive = TRUE)
  on.exit(unlink(project_dir, recursive = TRUE), add = TRUE)
  database_config <- list(
    mode = "local",
    project_dir = project_dir,
    local = list(path = file.path(data_dir, "recueil.sqlite"))
  )
  database_path <- file.path(data_dir, "plain_base.sqlite")

  shiny::testServer(build_app_server(database_config), {
    session$setInputs(
      new_database_name = "plain_base",
      new_database_password = "",
      new_database_password_confirm = "",
      create_database = 1
    )
    testthat::expect_true(file.exists(database_path))
    testthat::expect_false(file.exists(paste0(database_path, ".enc")))
    testthat::expect_match(output$database_overview, "sans mot de passe")
    session$setInputs(close_database = 1)

    session$setInputs(
      plain_database_to_open = database_path,
      open_plain_database = 1
    )
    testthat::expect_match(output$database_overview, "sans mot de passe")
  })

  testthat::expect_false(dir.exists(paste0(database_path, ".active")))
})

testthat::test_that("invalid imported data does not leave a partial database behind", {
  project_dir <- tempfile("failed-import-project-")
  data_dir <- file.path(project_dir, "data")
  dir.create(data_dir, recursive = TRUE)
  on.exit(unlink(project_dir, recursive = TRUE), add = TRUE)
  database_config <- list(
    mode = "local",
    project_dir = project_dir,
    local = list(path = file.path(data_dir, "default.sqlite"))
  )
  import_path <- tempfile(fileext = ".csv")
  on.exit(unlink(import_path), add = TRUE)
  utils::write.csv(data.frame(age = "not-an-integer"), import_path, row.names = FALSE)
  database_path <- file.path(data_dir, "retryable.sqlite")

  shiny::testServer(build_app_server(database_config), {
    session$setInputs(import_file = list(
      name = "bad.csv",
      datapath = import_path,
      size = file.info(import_path)$size,
      type = "text/csv"
    ))
    session$setInputs(import_type__age = "integer")
    session$setInputs(
      new_database_name = "retryable",
      new_database_password = "",
      new_database_password_confirm = "",
      create_database = 1
    )
    testthat::expect_match(output$database_workflow_status, "pas entière")
    testthat::expect_false(file.exists(database_path))
    testthat::expect_false(file.exists(paste0(database_path, ".active")))
  })
})

testthat::test_that("column-management actions explain when no database is connected", {
  shiny::testServer(build_app_server(), {
    session$setInputs(
      new_column_name = "age",
      new_column_type = "INTEGER",
      add_column = 1
    )
    testthat::expect_match(output$column_status, "base de données n'est pas connectée")
  })
})

testthat::test_that("forged database chooser paths outside data_dir are rejected", {
  project_dir <- tempfile("path-guard-project-")
  data_dir <- file.path(project_dir, "data")
  dir.create(data_dir, recursive = TRUE)
  on.exit(unlink(project_dir, recursive = TRUE), add = TRUE)
  config <- list(
    mode = "local",
    project_dir = project_dir,
    local = list(path = file.path(data_dir, "default.sqlite"))
  )
  outside_path <- tempfile(fileext = ".sqlite")
  on.exit(unlink(c(outside_path, paste0(outside_path, ".enc"))), add = TRUE)
  create_unencrypted_database(outside_path)
  before <- readBin(outside_path, what = "raw", n = file.info(outside_path)$size)

  shiny::testServer(build_app_server(config), {
    session$setInputs(
      plain_database_to_open = outside_path,
      open_plain_database = 1
    )
    testthat::expect_match(output$database_workflow_status, "directement dans le dossier local")

    session$setInputs(
      plain_database_to_protect = outside_path,
      protect_database_password = "external-path-password",
      protect_database_password_confirm = "external-path-password",
      protect_database = 1
    )
    testthat::expect_match(output$database_workflow_status, "directement dans le dossier local")
  })

  after <- readBin(outside_path, what = "raw", n = file.info(outside_path)$size)
  testthat::expect_identical(after, before)
  testthat::expect_false(file.exists(paste0(outside_path, ".enc")))
})

testthat::test_that("RDS uploads require explicit trust confirmation before deserialization", {
  project_dir <- tempfile("rds-trust-project-")
  data_dir <- file.path(project_dir, "data")
  dir.create(data_dir, recursive = TRUE)
  on.exit(unlink(project_dir, recursive = TRUE), add = TRUE)
  import_path <- tempfile()
  on.exit(unlink(import_path), add = TRUE)
  writeBin(charToRaw("not an RDS serialization"), import_path)
  config <- list(
    mode = "local",
    project_dir = project_dir,
    local = list(path = file.path(data_dir, "default.sqlite"))
  )

  shiny::testServer(build_app_server(config), {
    session$setInputs(import_file = list(
      name = "untrusted.rds",
      datapath = import_path,
      size = file.info(import_path)$size,
      type = "application/octet-stream"
    ))
    trust_controls <- htmltools::renderTags(output$import_rds_trust_ui)$html
    testthat::expect_match(trust_controls, "Je fais confiance à la source")
    blocked_status <- htmltools::renderTags(output$import_file_status)$html
    testthat::expect_match(blocked_status, "RDS n'a pas été chargé")

    session$setInputs(confirm_trusted_rds = TRUE)
    parsed_status <- htmltools::renderTags(output$import_file_status)$html
    testthat::expect_match(parsed_status, "RDS est invalide ou incompatible")
  })
})

testthat::test_that("a remotely configured database is connected at session startup", {
  database_config <- list(
    mode = "remote",
    project_dir = tempfile("remote-project-"),
    remote = list(
      driver_package = "RSQLite",
      driver_class = "SQLite",
      connection = list(dbname = ":memory:")
    )
  )

  shiny::testServer(build_app_server(database_config), {
    testthat::expect_equal(output$database_overview, "Base distante connectée.")
    testthat::expect_true(DBI::dbExistsTable(connection(), "column_definitions"))
    remote_controls <- htmltools::renderTags(output$open_database_controls)$html
    testthat::expect_match(remote_controls, "connexion distante configurée")
  })
})

testthat::test_that("the import conflict dialog applies explicit per-value choices", {
  project_dir <- tempfile("merge-project-")
  data_dir <- file.path(project_dir, "data")
  dir.create(data_dir, recursive = TRUE)
  on.exit(unlink(project_dir, recursive = TRUE), add = TRUE)
  vault_path <- file.path(data_dir, "merge.sqlite.enc")
  password <- "merge-test-password"
  create_database_vault(vault_path, password)
  vault <- open_database_vault(vault_path, password)
  add_typed_column(vault$connection, "participant_code", "text")
  add_typed_column(vault$connection, "age", "integer")
  add_typed_column(vault$connection, "note", "text")
  DBI::dbExecute(
    vault$connection,
    "INSERT INTO collection_records (id, created_at, payload, participant_code, age, note) VALUES ('row-existing', CURRENT_TIMESTAMP, '{}', 'P001', 30, NULL)"
  )
  close_database_vault(vault)

  import_path <- tempfile()
  utils::write.csv(
    data.frame(
      participant_code = c("P001", "P002"),
      age = c("35", "41"),
      note = c("filled", "new row"),
      stringsAsFactors = FALSE
    ),
    import_path,
    row.names = FALSE
  )

  shiny::testServer(build_app_server(list(
    mode = "local",
    project_dir = project_dir,
    local = list(path = file.path(data_dir, "default.sqlite"))
  )), {
    session$setInputs(
      database_to_open = vault_path,
      open_database_password = password,
      open_database = 1
    )
    session$setInputs(import_file = list(
      name = "merge.csv",
      datapath = import_path,
      size = file.info(import_path)$size,
      type = "text/csv"
    ))
    session$setInputs(import_merge_key = "participant_code", prepare_import_merge = 1)

    dialog_html <- htmltools::renderTags(output$merge_conflict_choices)$html
    testthat::expect_match(dialog_html, "Base actuelle")
    testthat::expect_match(dialog_html, "Fichier importé")
    session$setInputs(
      import_conflict_choice_1 = "imported",
      apply_import_conflicts = 1
    )
    testthat::expect_match(output$database_workflow_status, "conflit\\(s\\) arbitré\\(s\\)")
    session$setInputs(close_database = 1)
  })

  reopened <- open_database_vault(vault_path, password)
  on.exit(close_database_vault(reopened), add = TRUE)
  records <- read_collection_records(reopened$connection)
  testthat::expect_equal(nrow(records), 2L)
  testthat::expect_equal(records$age[records$participant_code == "P001"], 35L)
  testthat::expect_equal(records$note[records$participant_code == "P001"], "filled")
  testthat::expect_equal(records$age[records$participant_code == "P002"], 41L)
})

testthat::test_that("pending merge decisions are bound to their source database", {
  plan <- structure(list(key_field = "participant_code"), database_path = "/data/source.sqlite")
  source_database <- list(vault_path = "/data/source.sqlite")
  other_database <- list(vault_path = "/data/other.sqlite")

  testthat::expect_no_error(validate_pending_merge_database(plan, source_database))
  testthat::expect_error(
    validate_pending_merge_database(plan, other_database),
    "La base active a changé"
  )
  testthat::expect_error(validate_pending_merge_database(plan, NULL), "La base active a changé")
})

testthat::test_that("conflict decisions cannot be applied after switching databases", {
  project_dir <- tempfile("stale-merge-project-")
  data_dir <- file.path(project_dir, "data")
  dir.create(data_dir, recursive = TRUE)
  on.exit(unlink(project_dir, recursive = TRUE), add = TRUE)
  source_path <- file.path(data_dir, "source.sqlite.enc")
  other_path <- file.path(data_dir, "other.sqlite.enc")
  password <- "stale-merge-test-password"

  create_database_vault(source_path, password)
  source_vault <- open_database_vault(source_path, password)
  add_typed_column(source_vault$connection, "participant_code", "text")
  add_typed_column(source_vault$connection, "age", "integer")
  DBI::dbExecute(
    source_vault$connection,
    "INSERT INTO collection_records (id, created_at, payload, participant_code, age) VALUES ('row-source', CURRENT_TIMESTAMP, '{}', 'P001', 30)"
  )
  close_database_vault(source_vault)

  create_database_vault(other_path, password)
  other_vault <- open_database_vault(other_path, password)
  add_typed_column(other_vault$connection, "participant_code", "text")
  add_typed_column(other_vault$connection, "age", "integer")
  close_database_vault(other_vault)

  import_path <- tempfile(fileext = ".csv")
  on.exit(unlink(import_path), add = TRUE)
  utils::write.csv(data.frame(participant_code = "P001", age = "35"), import_path, row.names = FALSE)

  shiny::testServer(build_app_server(list(
    mode = "local",
    project_dir = project_dir,
    local = list(path = file.path(data_dir, "default.sqlite"))
  )), {
    session$setInputs(database_to_open = source_path, open_database_password = password, open_database = 1)
    session$setInputs(import_file = list(
      name = "update.csv",
      datapath = import_path,
      size = file.info(import_path)$size,
      type = "text/csv"
    ))
    session$setInputs(import_merge_key = "participant_code", prepare_import_merge = 1)
    session$setInputs(close_database = 1)
    session$setInputs(database_to_open = other_path, open_database = 1)
    session$setInputs(import_conflict_choice_1 = "imported", apply_import_conflicts = 1)
    testthat::expect_match(output$database_workflow_status, "base active a changé")
    session$setInputs(close_database = 2)
  })

  unchanged <- open_database_vault(source_path, password)
  on.exit(close_database_vault(unchanged), add = TRUE)
  source_records <- read_collection_records(unchanged$connection)
  testthat::expect_equal(source_records$age, 30L)
  close_database_vault(unchanged)

  other <- open_database_vault(other_path, password)
  on.exit(close_database_vault(other), add = TRUE)
  testthat::expect_equal(nrow(read_collection_records(other$connection)), 0L)
})
