# Les noms sont validés avant d'être cités par DBI et utilisés dans du SQL DDL.
record_table_name <- function() {
  "collection_records"
}

protected_record_columns <- function() {
  c("id", "created_at", "payload", "is_deleted")
}

allowed_record_column_types <- function() {
  c("TEXT", "INTEGER", "REAL", "NUMERIC", "DATE", "BOOLEAN")
}

validate_record_column_name <- function(name) {
  if (length(name) != 1L || is.na(name) || !grepl("^[A-Za-z][A-Za-z0-9_]*$", name)) {
    stop("Le nom doit commencer par une lettre et contenir uniquement lettres, chiffres et underscores.")
  }
  if (nchar(name, type = "chars") > 64L) {
    stop("Le nom de colonne est trop long : 64 caractères maximum.")
  }

  invisible(name)
}

list_record_columns <- function(connection) {
  DBI::dbListFields(connection, record_table_name())
}

create_record_column <- function(connection, name, type) {
  validate_record_column_name(name)
  type <- toupper(type)

  if (length(type) != 1L || is.na(type) || !type %in% allowed_record_column_types()) {
    stop("Type SQL non autorisé.")
  }

  existing_columns <- list_record_columns(connection)
  active_definition_names <- list_column_definitions(connection)$name
  if (tolower(name) %in% tolower(c(existing_columns, active_definition_names))) {
    stop("Une colonne portant ce nom existe déjà.")
  }

  table_sql <- as.character(DBI::dbQuoteIdentifier(connection, record_table_name()))
  column_sql <- as.character(DBI::dbQuoteIdentifier(connection, name))
  DBI::dbExecute(
    connection,
    sprintf("ALTER TABLE %s ADD COLUMN %s %s", table_sql, column_sql, type)
  )

  data_type <- switch(
    type,
    TEXT = "text",
    INTEGER = "integer",
    REAL = "real",
    NUMERIC = "numeric",
    DATE = "date",
    BOOLEAN = "boolean"
  )
  register_column_definition(connection, name, name, data_type)
}

add_record_column <- function(connection, name, type) {
  DBI::dbWithTransaction(connection, {
    create_record_column(connection, name, type)
  })
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
  update_column_definition_names(connection, old_name, new_name)

  invisible(new_name)
}
