database_schema_sql <- function() {
  c(
    "CREATE TABLE IF NOT EXISTS app_metadata (key VARCHAR(255) PRIMARY KEY, value TEXT NOT NULL)",
    paste(
      "CREATE TABLE IF NOT EXISTS collection_records (",
      "id VARCHAR(36) PRIMARY KEY,",
      "created_at TIMESTAMP NOT NULL,",
      "payload TEXT NOT NULL",
      ")"
    )
  )
}

initialize_database <- function(connection) {
  for (statement in database_schema_sql()) {
    DBI::dbExecute(connection, statement)
  }

  invisible(connection)
}
