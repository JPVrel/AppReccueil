# Le schéma est idempotent : une nouvelle session peut initialiser une base existante.
database_schema_sql <- function() {
  c(
    "CREATE TABLE IF NOT EXISTS app_metadata (key VARCHAR(255) PRIMARY KEY, value TEXT NOT NULL)",
    paste(
      "CREATE TABLE IF NOT EXISTS collection_records (",
      "id VARCHAR(36) PRIMARY KEY,",
      "created_at TIMESTAMP NOT NULL,",
      "payload TEXT NOT NULL,",
      "is_deleted INTEGER NOT NULL DEFAULT 0",
      ")"
    ),
    column_catalog_sql()
  )
}

initialize_database <- function(connection) {
  for (statement in database_schema_sql()) {
    DBI::dbExecute(connection, statement)
  }

  if (!"is_deleted" %in% list_record_columns(connection)) {
    DBI::dbExecute(
      connection,
      paste("ALTER TABLE", as.character(DBI::dbQuoteIdentifier(connection, record_table_name())),
        "ADD COLUMN is_deleted INTEGER NOT NULL DEFAULT 0")
    )
  }

  synchronize_column_catalog(connection)

  invisible(connection)
}
