record_table_name <- function() {
  "collection_records"
}

protected_record_columns <- function() {
  c("id", "created_at", "payload")
}

allowed_record_column_types <- function() {
  c("TEXT", "INTEGER", "REAL", "NUMERIC", "DATE", "BOOLEAN")
}

validate_record_column_name <- function(name) {
  if (length(name) != 1L || is.na(name) || !grepl("^[A-Za-z][A-Za-z0-9_]*$", name)) {
    stop("Le nom doit commencer par une lettre et contenir uniquement lettres, chiffres et underscores.")
  }

  invisible(name)
}

list_record_columns <- function(connection) {
  DBI::dbListFields(connection, record_table_name())
}

add_record_column <- function(connection, name, type) {
  validate_record_column_name(name)
  type <- toupper(type)

  if (length(type) != 1L || is.na(type) || !type %in% allowed_record_column_types()) {
    stop("Type SQL non autorisé.")
  }

  existing_columns <- list_record_columns(connection)
  if (tolower(name) %in% tolower(existing_columns)) {
    stop("Une colonne portant ce nom existe déjà.")
  }

  table_sql <- as.character(DBI::dbQuoteIdentifier(connection, record_table_name()))
  column_sql <- as.character(DBI::dbQuoteIdentifier(connection, name))
  DBI::dbExecute(
    connection,
    sprintf("ALTER TABLE %s ADD COLUMN %s %s", table_sql, column_sql, type)
  )

  invisible(name)
}

rename_record_column <- function(connection, old_name, new_name) {
  validate_record_column_name(old_name)
  validate_record_column_name(new_name)

  existing_columns <- list_record_columns(connection)
  old_column_index <- match(tolower(old_name), tolower(existing_columns))
  if (is.na(old_column_index)) {
    stop("La colonne à renommer n'existe pas.")
  }
  old_name <- existing_columns[[old_column_index]]
  if (tolower(old_name) %in% tolower(protected_record_columns())) {
    stop("Les colonnes techniques sont protégées.")
  }
  if (tolower(new_name) %in% tolower(existing_columns)) {
    stop("Une colonne portant ce nom existe déjà.")
  }

  table_sql <- as.character(DBI::dbQuoteIdentifier(connection, record_table_name()))
  old_column_sql <- as.character(DBI::dbQuoteIdentifier(connection, old_name))
  new_column_sql <- as.character(DBI::dbQuoteIdentifier(connection, new_name))
  DBI::dbExecute(
    connection,
    sprintf(
      "ALTER TABLE %s RENAME COLUMN %s TO %s",
      table_sql,
      old_column_sql,
      new_column_sql
    )
  )

  invisible(new_name)
}
