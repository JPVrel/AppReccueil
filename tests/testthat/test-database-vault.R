testthat::test_that("vault encryption authenticates and restores file bytes", {
  source_path <- tempfile(fileext = ".sqlite")
  encrypted_path <- tempfile(fileext = ".sqlite.enc")
  decrypted_path <- tempfile(fileext = ".sqlite")
  on.exit(unlink(c(source_path, encrypted_path, decrypted_path)), add = TRUE)
  source_bytes <- charToRaw("SQLite content that must stay secret")
  writeBin(source_bytes, source_path)

  encrypt_file_with_password(source_path, encrypted_path, "a-long-test-password")
  encrypted_bytes <- readBin(encrypted_path, what = "raw", n = file.info(encrypted_path)$size)
  envelope <- readRDS(encrypted_path)
  decrypt_file_with_password(encrypted_path, decrypted_path, "a-long-test-password")

  testthat::expect_identical(envelope$format, vault_format_id())
  testthat::expect_false(identical(encrypted_bytes, source_bytes))
  testthat::expect_identical(readBin(decrypted_path, what = "raw", n = file.info(decrypted_path)$size), source_bytes)
  testthat::expect_error(
    decrypt_file_with_password(encrypted_path, decrypted_path, "wrong-long-password"),
    "Mot de passe incorrect"
  )

  envelope$rounds <- 2147483647L
  saveRDS(envelope, encrypted_path)
  testthat::expect_error(
    decrypt_file_with_password(encrypted_path, decrypted_path, "a-long-test-password"),
    "paramètres cryptographiques"
  )
})

testthat::test_that("database vault creates, opens, and reseals a SQLite database", {
  vault_path <- tempfile(fileext = ".sqlite.enc")
  on.exit(unlink(vault_path), add = TRUE)
  password <- "database-password-123"

  create_database_vault(vault_path, password)
  vault <- open_database_vault(vault_path, password)
  on.exit(close_database_vault(vault), add = TRUE)

  testthat::expect_true(DBI::dbExistsTable(vault$connection, "column_definitions"))
  testthat::expect_true(dir.exists(vault$workspace))
  close_database_vault(vault)
  testthat::expect_false(dir.exists(vault$workspace))
  testthat::expect_error(open_database_vault(vault_path, "wrong-password-123"), "Mot de passe incorrect")
  testthat::expect_null(optional_vault_password("", ""))
  testthat::expect_equal(optional_vault_password(password, password), password)
  testthat::expect_error(optional_vault_password(password, ""), "laisse les deux champs vides")
})

testthat::test_that("protecting a legacy SQLite database preserves the source file", {
  source_path <- tempfile(fileext = ".sqlite")
  encrypted_path <- paste0(source_path, ".enc")
  on.exit(unlink(c(source_path, encrypted_path)), add = TRUE)
  connection <- DBI::dbConnect(RSQLite::SQLite(), source_path)
  initialize_database(connection)
  add_typed_column(connection, "participant_code", "text")
  DBI::dbExecute(
    connection,
    "INSERT INTO collection_records (id, created_at, payload, participant_code) VALUES ('row-1', CURRENT_TIMESTAMP, '{}', 'P001')"
  )
  DBI::dbDisconnect(connection)

  create_encrypted_database_copy(source_path, encrypted_path, "legacy-copy-password")
  vault <- open_database_vault(encrypted_path, "legacy-copy-password")
  on.exit(close_database_vault(vault), add = TRUE)
  records <- read_collection_records(vault$connection)

  testthat::expect_true(file.exists(source_path))
  testthat::expect_true(source_path %in% list_unencrypted_local_databases(dirname(source_path)))
  testthat::expect_true(encrypted_path %in% list_local_database_vaults(dirname(encrypted_path)))
  testthat::expect_equal(records$participant_code, "P001")
})

testthat::test_that("protecting a database refuses an active application session", {
  source_path <- tempfile(fileext = ".sqlite")
  encrypted_path <- paste0(source_path, ".enc")
  on.exit(unlink(c(source_path, encrypted_path, paste0(source_path, ".active")), recursive = TRUE), add = TRUE)
  create_unencrypted_database(source_path)
  database_state <- open_unencrypted_database(source_path)
  on.exit(close_unencrypted_database(database_state), add = TRUE)

  testthat::expect_error(
    create_encrypted_database_copy(source_path, encrypted_path, "active-copy-password"),
    "déjà ouverte"
  )
  testthat::expect_false(file.exists(encrypted_path))
})

testthat::test_that("abandoned local database locks are recovered only after owner exit", {
  database_path <- tempfile(fileext = ".sqlite")
  on.exit(unlink(c(database_path, paste0(database_path, ".active")), recursive = TRUE), add = TRUE)
  create_unencrypted_database(database_path)
  lock_path <- paste0(database_path, ".active")
  dir.create(lock_path)
  write_database_lock_owner(lock_path, "plain", database_path)
  owner <- readRDS(database_lock_owner_path(lock_path))
  owner$pid <- .Machine$integer.max
  saveRDS(owner, database_lock_owner_path(lock_path))

  database_state <- open_unencrypted_database(database_path)
  on.exit(close_unencrypted_database(database_state), add = TRUE)

  testthat::expect_true(DBI::dbExistsTable(database_state$connection, "column_definitions"))
  testthat::expect_error(open_unencrypted_database(database_path), "déjà ouverte")
})

testthat::test_that("stale lock owner metadata must match the requested database", {
  database_path <- tempfile(fileext = ".sqlite")
  other_path <- tempfile(fileext = ".sqlite")
  lock_path <- paste0(database_path, ".active")
  on.exit(unlink(c(database_path, other_path, lock_path), recursive = TRUE), add = TRUE)
  create_unencrypted_database(database_path)
  create_unencrypted_database(other_path)
  before <- readBin(database_path, what = "raw", n = file.info(database_path)$size)
  dir.create(lock_path)
  write_database_lock_owner(lock_path, "plain", other_path)
  owner <- readRDS(database_lock_owner_path(lock_path))
  owner$pid <- .Machine$integer.max
  saveRDS(owner, database_lock_owner_path(lock_path))

  testthat::expect_error(
    open_unencrypted_database(database_path),
    "ne correspond pas à cette base"
  )
  after <- readBin(database_path, what = "raw", n = file.info(database_path)$size)
  testthat::expect_identical(after, before)
  testthat::expect_true(dir.exists(lock_path))
})

testthat::test_that("only one concurrent process can claim stale lock recovery", {
  lock_path <- tempfile("database-")
  claim_path <- paste0(lock_path, ".recovery")
  on.exit(unlink(c(lock_path, claim_path), recursive = TRUE), add = TRUE)
  dir.create(lock_path)
  write_database_lock_owner(lock_path, "plain", lock_path)
  owner <- readRDS(database_lock_owner_path(lock_path))
  owner$pid <- .Machine$integer.max
  saveRDS(owner, database_lock_owner_path(lock_path))

  cluster <- parallel::makePSOCKcluster(4L)
  on.exit(parallel::stopCluster(cluster), add = TRUE)
  parallel::clusterExport(
    cluster,
    "acquire_database_recovery_claim",
    envir = environment(acquire_database_recovery_claim)
  )
  claims <- parallel::parLapply(cluster, seq_len(12), function(index, path) {
    tryCatch(acquire_database_recovery_claim(path), error = function(error) NULL)
  }, lock_path)
  successful_claims <- Filter(Negate(is.null), claims)

  testthat::expect_length(successful_claims, 1L)
  testthat::expect_true(dir.exists(claim_path))
})

testthat::test_that("abandoned or invalid recovery claims fail closed", {
  lock_path <- tempfile("database-")
  claim_path <- paste0(lock_path, ".recovery")
  on.exit(unlink(c(lock_path, claim_path), recursive = TRUE), add = TRUE)
  dir.create(lock_path)
  dir.create(claim_path)
  saveRDS(
    list(pid = .Machine$integer.max, host = Sys.info()[["nodename"]]),
    file.path(claim_path, "owner.rds")
  )

  testthat::expect_error(
    acquire_database_recovery_claim(lock_path),
    "verrou de récupération abandonné"
  )
  testthat::expect_true(dir.exists(claim_path))

  saveRDS(
    list(pid = "not-a-pid", host = Sys.info()[["nodename"]]),
    file.path(claim_path, "owner.rds")
  )
  testthat::expect_error(acquire_database_recovery_claim(lock_path), "propriétaire.*invalide")
})

testthat::test_that("vault replacement recovery restores a valid previous envelope", {
  work_dir <- tempfile("vault-replacement-")
  dir.create(work_dir)
  on.exit(unlink(work_dir, recursive = TRUE), add = TRUE)
  vault_path <- file.path(work_dir, "database.sqlite.enc")
  backup_path <- paste0(vault_path, ".previous")
  old_plain <- file.path(work_dir, "old.sqlite")
  new_plain <- file.path(work_dir, "new.sqlite")
  restored_plain <- file.path(work_dir, "restored.sqlite")
  password <- "replacement-recovery-password"
  writeBin(charToRaw("old intact encrypted database"), old_plain)
  writeBin(charToRaw("new encrypted database"), new_plain)
  encrypt_file_with_password(old_plain, vault_path, password)
  encrypt_file_with_password(new_plain, backup_path, password)
  writeBin(charToRaw("damaged interrupted destination"), vault_path)

  testthat::expect_true(recover_vault_replacement(vault_path, password))
  decrypt_file_with_password(vault_path, restored_plain, password)

  testthat::expect_identical(
    readBin(restored_plain, what = "raw", n = file.info(restored_plain)$size),
    charToRaw("new encrypted database")
  )
  testthat::expect_false(file.exists(backup_path))
  testthat::expect_length(list.files(work_dir, pattern = "database[.]sqlite[.]enc[.]damaged-"), 1L)
})

testthat::test_that("an abandoned encrypted workspace is integrity-checked and recovered", {
  vault_path <- tempfile(fileext = ".sqlite.enc")
  on.exit(unlink(c(vault_path, paste0(vault_path, ".active")), recursive = TRUE), add = TRUE)
  password <- "stale-vault-password"
  create_database_vault(vault_path, password)
  stale <- open_database_vault(vault_path, password)
  add_typed_column(stale$connection, "recovered_field", "text")
  DBI::dbDisconnect(stale$connection)
  owner <- readRDS(database_lock_owner_path(stale$lock_path))
  owner$pid <- .Machine$integer.max
  saveRDS(owner, database_lock_owner_path(stale$lock_path))

  recovered <- open_database_vault(vault_path, password)
  on.exit(close_database_vault(recovered), add = TRUE)

  testthat::expect_true("recovered_field" %in% list_column_definitions(recovered$connection)$name)
  testthat::expect_false(dir.exists(stale$workspace))
  testthat::expect_error(open_database_vault(vault_path, password), "déjà ouverte")
})

testthat::test_that("encrypted spreadsheet downloads retain format behind the vault", {
  work_dir <- tempfile("encrypted-export-")
  dir.create(work_dir)
  on.exit(unlink(work_dir, recursive = TRUE), add = TRUE)
  vault_path <- file.path(work_dir, "database.sqlite.enc")
  export_dir <- file.path(work_dir, "exports")
  password <- "encrypted-export-password"
  create_database_vault(vault_path, password)
  vault <- open_database_vault(vault_path, password)
  on.exit(close_database_vault(vault), add = TRUE)
  handler <- encrypted_database_spreadsheet_download_handler(
    shiny::reactiveVal(vault),
    export_dir,
    "rds",
    function() password
  )
  download <- new.env(parent = emptyenv())
  fake_session <- list(registerDownload = function(name, filename, contentType, content) {
    download$callbacks <- list(filename = filename, content = content)
  })
  handler(fake_session, "download_rds")
  download_name <- download$callbacks$filename()
  downloaded_path <- file.path(work_dir, download_name)
  plaintext_path <- file.path(work_dir, "download.rds")
  on.exit(unlink(c(downloaded_path, plaintext_path)), add = TRUE)
  download$callbacks$content(downloaded_path)
  decrypt_file_with_password(downloaded_path, plaintext_path, password)

  testthat::expect_match(download_name, "[.]rds[.]enc$")
  testthat::expect_true(file.exists(file.path(export_dir, download_name)))
  testthat::expect_s3_class(readRDS(plaintext_path), "data.frame")
  testthat::expect_false("payload" %in% names(readRDS(plaintext_path)))
  
  plain_handler <- encrypted_database_spreadsheet_download_handler(
    shiny::reactiveVal(vault),
    export_dir,
    "csv"
  )
  plain_download <- new.env(parent = emptyenv())
  plain_session <- list(registerDownload = function(name, filename, contentType, content) {
    plain_download$callbacks <- list(filename = filename, content = content)
  })
  plain_handler(plain_session, "download_csv")
  plain_name <- plain_download$callbacks$filename()
  plain_path <- file.path(work_dir, plain_name)
  on.exit(unlink(plain_path), add = TRUE)
  plain_download$callbacks$content(plain_path)
  
  testthat::expect_match(plain_name, "[.]csv$")
  testthat::expect_true(nrow(utils::read.csv(plain_path)) == 0L)
})