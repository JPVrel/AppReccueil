vault_format_id <- function() {
  charToRaw("APPRCVL1")
}

vault_password_rounds <- function() {
  64L
}

vault_envelope_header_bytes <- function() {
  8L + 16L + 12L + 4L + 16L
}

vault_max_file_bytes <- function() {
  256 * 1024^2
}

list_local_database_vaults <- function(data_dir) {
  if (!dir.exists(data_dir)) {
    return(character())
  }
  list.files(data_dir, pattern = "[.]sqlite[.]enc$", full.names = TRUE)
}

list_unencrypted_local_databases <- function(data_dir) {
  if (!dir.exists(data_dir)) {
    return(character())
  }
  list.files(data_dir, pattern = "[.]sqlite$", full.names = TRUE)
}

database_vault_path <- function(data_dir, database_name) {
  database_local_path(data_dir, database_name, encrypted = TRUE)
}

database_local_path <- function(data_dir, database_name, encrypted = FALSE) {
  if (length(database_name) != 1L || is.na(database_name) ||
    !grepl("^[A-Za-z0-9][A-Za-z0-9_-]{0,63}$", database_name)) {
    stop("Le nom de la base doit contenir 1 à 64 lettres, chiffres, tirets ou underscores.")
  }
  suffix <- if (isTRUE(encrypted)) ".sqlite.enc" else ".sqlite"
  file.path(data_dir, paste0(database_name, suffix))
}

validate_local_database_selection <- function(path, data_dir, suffix) {
  if (length(path) != 1L || is.na(path) || !nzchar(path) ||
    length(suffix) != 1L || is.na(suffix) || !startsWith(suffix, ".")) {
    stop("La sélection de base locale est invalide.")
  }
  root <- normalizePath(data_dir, mustWork = TRUE)
  selected <- normalizePath(path, mustWork = TRUE)
  if (!identical(dirname(selected), root) ||
    !endsWith(tolower(selected), tolower(suffix)) || isTRUE(file.info(selected)$isdir)) {
    stop("La base sélectionnée doit être un fichier ", suffix, " situé directement dans le dossier local.")
  }
  selected
}

validate_vault_password <- function(password, confirmation = NULL) {
  if (length(password) != 1L || is.na(password) || nchar(password, type = "chars") < 12L) {
    stop("Le mot de passe doit contenir au moins 12 caractères.")
  }
  if (!is.null(confirmation) && !identical(password, confirmation)) {
    stop("Les mots de passe ne correspondent pas.")
  }

  invisible(TRUE)
}

optional_vault_password <- function(password, confirmation = NULL) {
  password_empty <- is.null(password) || length(password) == 0L || is.na(password) || !nzchar(password)
  confirmation_empty <- is.null(confirmation) || length(confirmation) == 0L || is.na(confirmation) || !nzchar(confirmation)
  if (password_empty && confirmation_empty) {
    return(NULL)
  }
  if (password_empty || confirmation_empty) {
    stop("Renseigne et confirme le mot de passe, ou laisse les deux champs vides.")
  }

  validate_vault_password(password, confirmation)
  password
}

vault_derive_key <- function(password, salt, rounds = vault_password_rounds()) {
  openssl::bcrypt_pbkdf(password, salt, rounds = rounds, size = 32L)
}

database_lock_owner_path <- function(lock_path) {
  file.path(lock_path, "owner.rds")
}

write_database_lock_owner <- function(lock_path, mode, database_path, workspace = NULL) {
  owner <- list(
    pid = Sys.getpid(),
    host = Sys.info()[["nodename"]],
    mode = mode,
    database_path = normalizePath(database_path, mustWork = FALSE),
    workspace = workspace,
    created_at = Sys.time()
  )
  saveRDS(owner, database_lock_owner_path(lock_path), version = 3)
  Sys.chmod(database_lock_owner_path(lock_path), mode = "0600")
  invisible(owner)
}

database_lock_owner <- function(lock_path) {
  owner_path <- database_lock_owner_path(lock_path)
  if (!file.exists(owner_path)) {
    stop(
      "Un verrou de base sans propriétaire est présent : ", lock_path,
      ". Vérifie qu'aucune instance ne l'utilise, puis supprime ce verrou manuellement."
    )
  }
  owner <- tryCatch(readRDS(owner_path), error = function(error) NULL)
  required <- c("pid", "host", "mode", "database_path", "workspace")
  if (!is.list(owner) || !all(required %in% names(owner)) ||
    !is.numeric(owner$pid) || length(owner$pid) != 1L || !is.finite(owner$pid) ||
    owner$pid != trunc(owner$pid) || owner$pid < 1L || owner$pid > .Machine$integer.max ||
    length(owner$host) != 1L || is.na(owner$host)) {
    stop("Le fichier propriétaire du verrou est invalide : ", lock_path)
  }
  if (!owner$mode %in% c("vault", "plain", "copy", "creation") ||
    length(owner$database_path) != 1L || is.na(owner$database_path) ||
    (!is.null(owner$workspace) && (length(owner$workspace) != 1L || is.na(owner$workspace)))) {
    stop("Le fichier propriétaire du verrou est invalide : ", lock_path)
  }
  owner
}

database_owner_process_alive <- function(owner) {
  if (!identical(owner$host, Sys.info()[["nodename"]])) {
    return(NA)
  }
  if (!is.numeric(owner$pid) || length(owner$pid) != 1L || !is.finite(owner$pid) ||
    owner$pid != trunc(owner$pid) || owner$pid < 1L || owner$pid > .Machine$integer.max) {
    return(NA)
  }
  pid <- as.integer(owner$pid)
  if (.Platform$OS.type == "unix") {
    return(isTRUE(tryCatch(tools::pskill(pid, signal = 0L), error = function(error) FALSE)))
  }

  processes <- tryCatch(
    system2("tasklist", c("/FI", shQuote(paste("PID eq", pid))), stdout = TRUE, stderr = FALSE),
    error = function(error) character()
  )
  any(grepl(paste0("\\b", pid, "\\b"), processes))
}

is_private_database_workspace <- function(workspace) {
  if (length(workspace) != 1L || is.na(workspace) || !nzchar(workspace)) {
    return(FALSE)
  }
  if (!grepl("^appreccueil-db-", basename(workspace))) {
    return(FALSE)
  }
  parent <- normalizePath(dirname(workspace), mustWork = TRUE)
  temporary_root <- normalizePath(tempdir(), mustWork = FALSE)
  identical(parent, temporary_root)
}

checkpoint_sqlite_database <- function(connection) {
  checkpoint <- DBI::dbGetQuery(connection, "PRAGMA wal_checkpoint(FULL)")
  if (nrow(checkpoint) != 1L || checkpoint$busy[[1]] != 0L ||
    (checkpoint$log[[1]] >= 0L && checkpoint$log[[1]] != checkpoint$checkpointed[[1]])) {
    stop("Le journal SQLite ne peut pas être entièrement checkpointé.")
  }
  invisible(checkpoint)
}

recover_abandoned_database_lock <- function(lock_path, owner, password = NULL) {
  if (!identical(owner$host, Sys.info()[["nodename"]])) {
    stop("La base semble ouverte sur une autre machine ; son verrou ne peut pas être récupéré automatiquement.")
  }
  process_alive <- database_owner_process_alive(owner)
  if (isTRUE(process_alive)) {
    stop("Cette base est déjà ouverte dans une autre session.")
  }
  if (is.na(process_alive)) {
    stop("L'état du processus propriétaire ne peut pas être vérifié ; le verrou est conservé.")
  }

  workspace <- owner$workspace
  if (identical(owner$mode, "vault") &&
    (is.null(workspace) || !dir.exists(workspace) ||
      !file.exists(file.path(workspace, "working.sqlite")))) {
    stop("La copie de travail du coffre est absente ; le verrou est conservé pour éviter de perdre des modifications.")
  }
  if (!is.null(workspace) && dir.exists(workspace)) {
    if (!is_private_database_workspace(workspace)) {
      stop("Le dossier de travail abandonné est hors de l'espace temporaire privé ; le verrou est conservé.")
    }
    working_database <- file.path(workspace, "working.sqlite")
    if (identical(owner$mode, "vault") && file.exists(working_database)) {
      if (is.null(password)) {
        stop("Ce coffre a une copie de travail à récupérer ; saisis le mot de passe.")
      }
      recover_vault_replacement(owner$database_path, password)
      verification_workspace <- new_private_database_workspace()
      on.exit(unlink(verification_workspace$directory, recursive = TRUE), add = TRUE)
      decrypt_file_with_password(
        owner$database_path,
        verification_workspace$database,
        password
      )

      recovered_connection <- DBI::dbConnect(
        RSQLite::SQLite(),
        dbname = working_database,
        flags = RSQLite::SQLITE_RW
      )
      integrity <- tryCatch(
        DBI::dbGetQuery(recovered_connection, "PRAGMA integrity_check")[[1]],
        error = function(error) character()
      )
      if (identical(integrity, "ok")) {
        checkpoint_sqlite_database(recovered_connection)
      }
      disconnect_database(recovered_connection)
      if (!identical(integrity, "ok")) {
        stop("La copie de travail abandonnée n'est pas intègre ; elle a été conservée pour récupération manuelle.")
      }
      encrypt_file_with_password(working_database, owner$database_path, password)
    }
    unlink(workspace, recursive = TRUE)
  }

  unlink(lock_path, recursive = TRUE)
  invisible(TRUE)
}

acquire_database_recovery_claim <- function(lock_path) {
  claim_path <- paste0(lock_path, ".recovery")
  owner_path <- file.path(claim_path, "owner.rds")
  create_claim <- function() {
    if (!dir.create(claim_path, mode = "0700", showWarnings = FALSE)) {
      return(FALSE)
    }
    tryCatch({
      saveRDS(
        list(pid = Sys.getpid(), host = Sys.info()[["nodename"]], created_at = Sys.time()),
        owner_path,
        version = 3
      )
      Sys.chmod(owner_path, mode = "0600")
      TRUE
    }, error = function(error) {
      unlink(claim_path, recursive = TRUE)
      stop(error)
    })
  }

  if (create_claim()) {
    return(claim_path)
  }

  if (!dir.exists(claim_path) || !file.exists(owner_path)) {
    stop("Un verrou de récupération incomplet est présent ; vérifie les processus avant de le supprimer.")
  }
  owner <- tryCatch(readRDS(owner_path), error = function(error) NULL)
  if (!is.list(owner) || !is.numeric(owner$pid) || length(owner$pid) != 1L ||
    !is.finite(owner$pid) || owner$pid != trunc(owner$pid) || owner$pid < 1L ||
    owner$pid > .Machine$integer.max ||
    length(owner$host) != 1L || is.na(owner$host)) {
    stop("Le propriétaire du verrou de récupération est invalide ; intervention manuelle requise.")
  }
  if (!identical(owner$host, Sys.info()[["nodename"]])) {
    stop("La récupération est en cours sur une autre machine.")
  }
  owner_pid <- as.integer(owner$pid)
  if (isTRUE(tryCatch(tools::pskill(owner_pid, signal = 0L), error = function(error) FALSE))) {
    stop("La récupération de cette base est déjà en cours dans une autre session.")
  }
  stop("Un verrou de récupération abandonné est présent ; vérifie qu'aucune récupération ne tourne, puis supprime-le manuellement.")
}

release_database_recovery_claim <- function(claim_path) {
  owner_path <- file.path(claim_path, "owner.rds")
  owner <- if (file.exists(owner_path)) {
    tryCatch(readRDS(owner_path), error = function(error) NULL)
  } else {
    NULL
  }
  if (!is.list(owner) || !identical(owner$pid, Sys.getpid()) ||
    !identical(owner$host, Sys.info()[["nodename"]])) {
    return(invisible(FALSE))
  }
  unlink(claim_path, recursive = TRUE)
  invisible(TRUE)
}

acquire_database_lock <- function(lock_path, mode, database_path, workspace = NULL, password = NULL) {
  write_owner <- function() {
    acquired <- TRUE
    on.exit(if (acquired) release_database_lock(lock_path), add = TRUE)
    write_database_lock_owner(lock_path, mode, database_path, workspace)
    acquired <- FALSE
  }

  if (dir.create(lock_path, mode = "0700", showWarnings = FALSE)) {
    write_owner()
    return(invisible(lock_path))
  }
  if (!dir.exists(lock_path)) {
    stop("Le verrou de la base ne peut pas être créé : ", lock_path)
  }

  recovery_claim <- acquire_database_recovery_claim(lock_path)
  on.exit(release_database_recovery_claim(recovery_claim), add = TRUE)
  owner <- database_lock_owner(lock_path)
  expected_database_path <- normalizePath(database_path, mustWork = FALSE)
  owner_database_path <- normalizePath(owner$database_path, mustWork = FALSE)
  if (!identical(owner_database_path, expected_database_path)) {
    stop("Le propriétaire du verrou ne correspond pas à cette base.")
  }
  compatible_modes <- switch(
    owner$mode,
    vault = "vault",
    plain = c("plain", "copy"),
    copy = c("plain", "copy"),
    creation = "creation",
    character()
  )
  if (!mode %in% compatible_modes) {
    stop("Le mode du verrou ne correspond pas au type de base demandé.")
  }
  workspace_required <- owner$mode %in% c("vault", "copy")
  if (workspace_required && !is_private_database_workspace(owner$workspace)) {
    stop("Le dossier de travail indiqué par le verrou n'est pas privé ; intervention manuelle requise.")
  }
  if (!workspace_required && !is.null(owner$workspace)) {
    stop("Le verrou contient un dossier de travail inattendu ; intervention manuelle requise.")
  }
  recover_abandoned_database_lock(lock_path, owner, password)
  if (!dir.create(lock_path, mode = "0700", showWarnings = FALSE)) {
    stop("Cette base a été ouverte par une autre session pendant la récupération.")
  }
  write_owner()
  invisible(lock_path)
}

release_database_lock <- function(lock_path) {
  if (dir.exists(lock_path)) {
    unlink(lock_path, recursive = TRUE)
  }
  invisible(NULL)
}

reserve_database_creation <- function(database_path) {
  reservation_path <- paste0(database_path, ".creating")
  acquire_database_lock(reservation_path, "creation", database_path)
  reservation_path
}

remove_database_files <- function(database_path) {
  unlink(c(
    database_path,
    paste0(database_path, "-wal"),
    paste0(database_path, "-shm")
  ))
  invisible(NULL)
}

replace_vault_file <- function(source, destination) {
  if (file.rename(source, destination)) {
    return(invisible(destination))
  }

  backup <- paste0(destination, ".previous")
  if (file.exists(backup)) {
    stop("Une sauvegarde de coffre incomplète doit être récupérée avant remplacement.")
  }
  if (!file.exists(destination)) {
    stop("Le fichier chiffré ne peut pas être installé atomiquement.")
  }
  if (!file.rename(destination, backup)) {
    stop("Le coffre précédent ne peut pas être préservé avant remplacement.")
  }
  if (!file.rename(source, destination)) {
    if (file.rename(backup, destination)) {
      stop("Le nouveau coffre n'a pas été installé ; l'ancien coffre a été restauré.")
    }
    stop("Le nouveau coffre n'a pas été installé ; la sauvegarde précédente est conservée.")
  }

  Sys.chmod(destination, mode = "0600")
  if (file.exists(backup) && unlink(backup) != 0L) {
    stop("Le coffre est remplacé, mais sa sauvegarde précédente n'a pas pu être retirée.")
  }
  invisible(destination)
}

recover_vault_replacement <- function(encrypted_path, password) {
  backup <- paste0(encrypted_path, ".previous")
  if (!file.exists(backup)) {
    return(invisible(FALSE))
  }

  if (!file.exists(encrypted_path)) {
    if (!file.rename(backup, encrypted_path)) {
      stop("La sauvegarde précédente ne peut pas être restaurée automatiquement.")
    }
    return(invisible(TRUE))
  }

  verification_workspace <- new_private_database_workspace()
  on.exit(unlink(verification_workspace$directory, recursive = TRUE), add = TRUE)
  destination_valid <- tryCatch({
    decrypt_file_with_password(encrypted_path, verification_workspace$database, password)
    TRUE
  }, error = function(error) FALSE)
  if (destination_valid) {
    if (unlink(backup) != 0L) {
      stop("Le coffre est valide, mais sa sauvegarde précédente n'a pas pu être retirée.")
    }
    return(invisible(TRUE))
  }

  backup_valid <- tryCatch({
    decrypt_file_with_password(backup, verification_workspace$database, password)
    TRUE
  }, error = function(error) FALSE)
  if (!backup_valid) {
    stop("Le coffre et sa sauvegarde précédente ne peuvent pas être authentifiés.")
  }

  damaged <- paste0(encrypted_path, ".damaged-", format(Sys.time(), "%Y%m%d-%H%M%S", tz = "UTC"))
  if (!file.rename(encrypted_path, damaged) || !file.rename(backup, encrypted_path)) {
    stop("Le coffre précédent est authentique, mais n'a pas pu être restauré automatiquement.")
  }
  invisible(TRUE)
}

encrypt_file_with_password <- function(source_path, encrypted_path, password) {
  validate_vault_password(password)
  if (!file.exists(source_path)) {
    stop("Le fichier source n'existe pas.")
  }
  if (identical(normalizePath(source_path), normalizePath(encrypted_path, mustWork = FALSE))) {
    stop("Le fichier source et le fichier chiffré doivent être différents.")
  }

  dir.create(dirname(encrypted_path), recursive = TRUE, showWarnings = FALSE)
  source_size <- file.info(source_path)$size
  if (is.na(source_size) || source_size > vault_max_file_bytes()) {
    stop("Le fichier à chiffrer dépasse la limite de 256 Mio.")
  }
  source_bytes <- readBin(source_path, what = "raw", n = source_size)
  salt <- openssl::rand_bytes(16L)
  nonce <- openssl::rand_bytes(12L)
  rounds <- vault_password_rounds()
  key <- vault_derive_key(password, salt, rounds)
  ciphertext <- openssl::aes_gcm_encrypt(source_bytes, key, iv = nonce)
  tag <- attr(ciphertext, "tag")
  attributes(ciphertext) <- NULL

  temporary_path <- tempfile(".encrypted-", tmpdir = dirname(encrypted_path))
  on.exit(unlink(temporary_path), add = TRUE)
  output <- file(temporary_path, open = "wb")
  on.exit(try(close(output), silent = TRUE), add = TRUE)
  writeBin(vault_format_id(), output)
  writeBin(salt, output)
  writeBin(nonce, output)
  writeBin(as.integer(rounds), output, size = 4L, endian = "big")
  writeBin(tag, output)
  writeBin(ciphertext, output)
  close(output)
  Sys.chmod(temporary_path, mode = "0600")
  replace_vault_file(temporary_path, encrypted_path)
  invisible(encrypted_path)
}

decrypt_file_with_password <- function(encrypted_path, destination_path, password) {
  validate_vault_password(password)
  if (!file.exists(encrypted_path)) {
    stop("Le fichier chiffré n'existe pas.")
  }

  encrypted_size <- file.info(encrypted_path)$size
  header_size <- vault_envelope_header_bytes()
  if (is.na(encrypted_size) || encrypted_size < header_size + 16L ||
    encrypted_size > vault_max_file_bytes()) {
    stop("La taille du coffre est invalide ou dépasse la limite autorisée.")
  }

  input <- file(encrypted_path, open = "rb")
  on.exit(close(input), add = TRUE)
  format <- readBin(input, what = "raw", n = 8L)
  salt <- readBin(input, what = "raw", n = 16L)
  nonce <- readBin(input, what = "raw", n = 12L)
  rounds <- readBin(input, what = integer(), n = 1L, size = 4L, endian = "big")
  tag <- readBin(input, what = "raw", n = 16L)
  ciphertext_size <- as.integer(encrypted_size - header_size)
  ciphertext <- readBin(input, what = "raw", n = ciphertext_size)
  if (!identical(format, vault_format_id()) || length(salt) != 16L ||
    length(nonce) != 12L || length(rounds) != 1L || length(tag) != 16L ||
    length(ciphertext) != ciphertext_size) {
    stop("Le fichier n'est pas un coffre AppReccueil valide.")
  }
  if (!identical(rounds, vault_password_rounds()) || length(ciphertext) < 16L) {
    stop("Les paramètres cryptographiques du coffre sont invalides.")
  }

  attr(ciphertext, "tag") <- tag
  key <- vault_derive_key(password, salt, rounds)
  plaintext <- tryCatch(
    openssl::aes_gcm_decrypt(ciphertext, key, iv = nonce),
    error = function(error) stop("Mot de passe incorrect ou coffre endommagé.", call. = FALSE)
  )
  dir.create(dirname(destination_path), recursive = TRUE, showWarnings = FALSE, mode = "0700")
  writeBin(plaintext, destination_path)
  Sys.chmod(destination_path, mode = "0600")
  invisible(destination_path)
}

new_private_database_workspace <- function() {
  workspace <- tempfile("appreccueil-db-")
  if (!dir.create(workspace, mode = "0700")) {
    stop("Le dossier de travail privé ne peut pas être créé.")
  }
  Sys.chmod(workspace, mode = "0700")
  list(directory = workspace, database = file.path(workspace, "working.sqlite"))
}

open_database_vault <- function(encrypted_path, password) {
  validate_vault_password(password)
  lock_path <- paste0(encrypted_path, ".active")
  acquire_database_lock(lock_path, "vault", encrypted_path, password = password)

  workspace <- NULL
  opened <- FALSE
  connection <- NULL
  on.exit({
    if (!opened) {
      disconnect_database(connection)
      if (!is.null(workspace)) {
        unlink(workspace$directory, recursive = TRUE)
      }
      release_database_lock(lock_path)
    }
  }, add = TRUE)

  recover_vault_replacement(encrypted_path, password)
  workspace <- new_private_database_workspace()
  write_database_lock_owner(lock_path, "vault", encrypted_path, workspace$directory)
  decrypt_file_with_password(encrypted_path, workspace$database, password)
  connection <- DBI::dbConnect(RSQLite::SQLite(), dbname = workspace$database)
  initialize_database(connection)
  opened <- TRUE
  list(
    connection = connection,
    vault_path = encrypted_path,
    password = password,
    encrypted = TRUE,
    working_path = workspace$database,
    workspace = workspace$directory,
    lock_path = lock_path
  )
}

close_database_vault <- function(vault) {
  if (!file.exists(vault$working_path)) {
    if (!is.null(vault$workspace)) {
      unlink(vault$workspace, recursive = TRUE)
    }
    release_database_lock(vault$lock_path)
    return(invisible(vault$vault_path))
  }

  checkpoint_sqlite_database(vault$connection)
  disconnect_database(vault$connection)
  encrypt_file_with_password(vault$working_path, vault$vault_path, vault$password)
  unlink(vault$workspace, recursive = TRUE)
  if (dir.exists(vault$workspace)) {
    stop("Le dossier de travail déchiffré n'a pas pu être retiré ; le verrou est conservé.")
  }
  release_database_lock(vault$lock_path)
  invisible(vault$vault_path)
}

create_database_vault <- function(encrypted_path, password) {
  validate_vault_password(password)
  reservation <- reserve_database_creation(encrypted_path)
  on.exit(release_database_lock(reservation), add = TRUE)
  if (file.exists(encrypted_path)) {
    stop("Une base portant ce nom existe déjà.")
  }
  owns_destination <- TRUE
  created <- FALSE
  on.exit(if (owns_destination && !created) unlink(encrypted_path), add = TRUE)

  workspace <- new_private_database_workspace()
  on.exit(unlink(workspace$directory, recursive = TRUE), add = TRUE)
  connection <- DBI::dbConnect(RSQLite::SQLite(), dbname = workspace$database)
  on.exit(disconnect_database(connection), add = TRUE)
  initialize_database(connection)
  disconnect_database(connection)
  connection <- NULL
  encrypt_file_with_password(workspace$database, encrypted_path, password)
  created <- TRUE
  invisible(encrypted_path)
}

create_unencrypted_database <- function(database_path) {
  reservation <- reserve_database_creation(database_path)
  on.exit(release_database_lock(reservation), add = TRUE)
  if (file.exists(database_path)) {
    stop("Une base portant ce nom existe déjà.")
  }
  owns_destination <- TRUE
  created <- FALSE
  on.exit(if (owns_destination && !created) remove_database_files(database_path), add = TRUE)
  dir.create(dirname(database_path), recursive = TRUE, showWarnings = FALSE)
  connection <- DBI::dbConnect(RSQLite::SQLite(), dbname = database_path)
  on.exit(disconnect_database(connection), add = TRUE)
  initialize_database(connection)
  disconnect_database(connection)
  Sys.chmod(database_path, mode = "0600")
  created <- TRUE
  invisible(database_path)
}

open_unencrypted_database <- function(database_path) {
  if (!file.exists(database_path)) {
    stop("La base SQLite locale n'existe pas.")
  }
  lock_path <- paste0(database_path, ".active")
  acquire_database_lock(lock_path, "plain", database_path)

  connection <- NULL
  opened <- FALSE
  on.exit({
    if (!opened) {
      disconnect_database(connection)
      release_database_lock(lock_path)
    }
  }, add = TRUE)
  connection <- DBI::dbConnect(
    RSQLite::SQLite(),
    dbname = database_path,
    flags = RSQLite::SQLITE_RW
  )
  initialize_database(connection)
  opened <- TRUE
  list(
    connection = connection,
    vault_path = database_path,
    password = NULL,
    encrypted = FALSE,
    working_path = database_path,
    workspace = NULL,
    lock_path = lock_path
  )
}

close_unencrypted_database <- function(database_state) {
  disconnect_database(database_state$connection)
  release_database_lock(database_state$lock_path)
  invisible(database_state$vault_path)
}

close_database_state <- function(database_state) {
  if (isTRUE(database_state$remote)) {
    disconnect_database(database_state$connection)
    return(invisible(NULL))
  }
  if (isTRUE(database_state$encrypted)) {
    close_database_vault(database_state)
  } else {
    close_unencrypted_database(database_state)
  }
}

create_encrypted_database_copy <- function(source_path, encrypted_path, password) {
  validate_vault_password(password)
  if (!file.exists(source_path) || file.exists(encrypted_path)) {
    stop("La base source est absente ou la destination chiffrée existe déjà.")
  }

  destination_reservation <- reserve_database_creation(encrypted_path)
  on.exit(release_database_lock(destination_reservation), add = TRUE)
  if (file.exists(encrypted_path)) {
    stop("Une base chiffrée portant ce nom vient d'être créée.")
  }

  source_lock <- paste0(source_path, ".active")
  workspace <- new_private_database_workspace()
  on.exit(unlink(workspace$directory, recursive = TRUE), add = TRUE)
  acquire_database_lock(
    source_lock,
    "copy",
    source_path,
    workspace = workspace$directory
  )
  on.exit(release_database_lock(source_lock), add = TRUE)
  source_connection <- DBI::dbConnect(RSQLite::SQLite(), dbname = source_path)
  on.exit(disconnect_database(source_connection), add = TRUE)
  checkpoint_sqlite_database(source_connection)
  disconnect_database(source_connection)
  source_connection <- NULL

  if (!file.copy(source_path, workspace$database, overwrite = FALSE)) {
    stop("La base locale ne peut pas être copiée vers l'espace privé.")
  }
  Sys.chmod(workspace$database, mode = "0600")
  encrypt_file_with_password(workspace$database, encrypted_path, password)
  invisible(encrypted_path)
}

next_encrypted_export_path <- function(export_dir, format, export_time = Sys.time()) {
  if (length(format) != 1L || !format %in% c("csv", "xlsx", "rds")) {
    stop("Format d'export non pris en charge.")
  }
  dir.create(export_dir, recursive = TRUE, showWarnings = FALSE)
  if (!dir.exists(export_dir)) {
    stop("Le dossier d'exports ne peut pas être créé.")
  }

  timestamp <- format(export_time, "%Y%m%d-%H%M%S", tz = "UTC")
  base_name <- paste0("recueil-", timestamp, ".", format, ".enc")
  candidate <- file.path(export_dir, base_name)
  suffix <- 2L
  while (!reserve_spreadsheet_export_path(candidate)) {
    candidate <- file.path(
      export_dir,
      paste0("recueil-", timestamp, "-", suffix, ".", format, ".enc")
    )
    suffix <- suffix + 1L
  }
  candidate
}