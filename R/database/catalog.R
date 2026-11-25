# Le catalogue sépare le nom affiché, le nom SQL physique et les métadonnées métier.
# Les identifiants stables servent de références aux dictionnaires et aux formules.
column_definition_types <- function() {
  c("text", "integer", "real", "numeric", "date", "boolean", "categorical")
}

generate_column_id <- function() {
  paste0("col_", basename(tempfile()))
}

quote_sql_value <- function(connection, value) {
  as.character(DBI::dbQuoteString(connection, value))
}

column_catalog_sql <- function() {
  c(
    paste(
      "CREATE TABLE IF NOT EXISTS column_definitions (",
      "column_id VARCHAR(64) PRIMARY KEY,",
      "name VARCHAR(255) NOT NULL,",
      "sql_name VARCHAR(255) UNIQUE,",
      "data_type VARCHAR(32) NOT NULL,",
      "is_hidden INTEGER NOT NULL DEFAULT 0,",
      "formula TEXT",
      ")"
    ),
    paste(
      "CREATE TABLE IF NOT EXISTS category_dictionary (",
      "category_id VARCHAR(64) PRIMARY KEY,",
      "column_id VARCHAR(64) NOT NULL,",
      "code TEXT NOT NULL,",
      "label TEXT NOT NULL,",
      "sort_order INTEGER NOT NULL DEFAULT 0,",
      "UNIQUE (column_id, code)",
      ")"
    )
  )
}

register_column_definition <- function(
  connection,
  name,
  sql_name,
  data_type,
  column_id = generate_column_id(),
  formula = NULL,
  is_hidden = FALSE
) {
  validate_record_column_name(name)
  if (!is.null(sql_name)) {
    validate_record_column_name(sql_name)
  }
  if (length(data_type) != 1L || !data_type %in% column_definition_types()) {
    stop("Type de colonne non pris en charge.")
  }

  formula_value <- if (is.null(formula)) "NULL" else quote_sql_value(connection, yaml::as.yaml(formula))
  sql_name_value <- if (is.null(sql_name)) "NULL" else quote_sql_value(connection, sql_name)
  hidden_value <- if (isTRUE(is_hidden)) 1L else 0L
  statement <- paste(
    "INSERT INTO column_definitions",
    "(column_id, name, sql_name, data_type, is_hidden, formula)",
    "VALUES (",
    paste(
      quote_sql_value(connection, column_id),
      quote_sql_value(connection, name),
      sql_name_value,
      quote_sql_value(connection, data_type),
      hidden_value,
      formula_value,
      sep = ", "
    ),
    ")"
  )
  DBI::dbExecute(connection, statement)

  column_id
}

get_column_definition <- function(connection, column_id) {
  id_value <- quote_sql_value(connection, column_id)
  result <- DBI::dbGetQuery(
    connection,
    paste("SELECT * FROM column_definitions WHERE column_id =", id_value)
  )

  if (nrow(result) == 0L) {
    stop("La définition de colonne n'existe pas.")
  }

  result$is_hidden <- as.logical(result$is_hidden)
  result
}

list_column_definitions <- function(connection, include_hidden = FALSE) {
  query <- "SELECT * FROM column_definitions"
  if (!include_hidden) {
    query <- paste(query, "WHERE is_hidden = 0")
  }
  query <- paste(query, "ORDER BY name, column_id")
  result <- DBI::dbGetQuery(connection, query)
  result$is_hidden <- as.logical(result$is_hidden)
  result
}

infer_existing_column_type <- function(connection, column_name) {
  table_sql <- as.character(DBI::dbQuoteIdentifier(connection, record_table_name()))
  column_sql <- as.character(DBI::dbQuoteIdentifier(connection, column_name))
  query <- DBI::dbSendQuery(
    connection,
    sprintf("SELECT %s FROM %s WHERE 1 = 0", column_sql, table_sql)
  )
  on.exit(DBI::dbClearResult(query), add = TRUE)
  column_type <- DBI::dbColumnInfo(query)$type[[1]]

  switch(
    column_type,
    integer = "integer",
    double = "real",
    logical = "boolean",
    character = "text",
    "text"
  )
}

synchronize_column_catalog <- function(connection) {
  existing_definitions <- list_column_definitions(connection, include_hidden = TRUE)
  registered_sql_names <- existing_definitions$sql_name[!is.na(existing_definitions$sql_name)]
  physical_columns <- setdiff(list_record_columns(connection), protected_record_columns())
  unregistered <- setdiff(physical_columns, registered_sql_names)

  for (column_name in unregistered) {
    register_column_definition(
      connection,
      name = column_name,
      sql_name = column_name,
      data_type = infer_existing_column_type(connection, column_name)
    )
  }

  invisible(NULL)
}
