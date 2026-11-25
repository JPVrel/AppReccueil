# Traduit les types métier de l'interface en types SQL portables entre les drivers DBI.
field_sql_types <- function() {
  c(
    text = "TEXT",
    integer = "INTEGER",
    real = "REAL",
    numeric = "NUMERIC",
    date = "DATE",
    boolean = "BOOLEAN",
    categorical = "TEXT"
  )
}

add_typed_column <- function(connection, name, data_type) {
  data_type <- tolower(data_type)
  sql_types <- field_sql_types()

  if (length(data_type) != 1L || is.na(data_type) || !data_type %in% names(sql_types)) {
    stop("Type de champ non pris en charge.")
  }

  DBI::dbWithTransaction(connection, {
    column_id <- create_record_column(connection, name, unname(sql_types[[data_type]]))
    data_type_sql <- quote_sql_value(connection, data_type)
    column_id_sql <- quote_sql_value(connection, column_id)
    DBI::dbExecute(
      connection,
      paste(
        "UPDATE column_definitions SET data_type =",
        data_type_sql,
        "WHERE column_id =",
        column_id_sql
      )
    )

    column_id
  })
}

update_column_definition_names <- function(connection, old_sql_name, new_name) {
  old_name_sql <- quote_sql_value(connection, old_sql_name)
  new_name_sql <- quote_sql_value(connection, new_name)
  DBI::dbExecute(
    connection,
    paste(
      "UPDATE column_definitions SET name =",
      new_name_sql,
      ", sql_name =",
      new_name_sql,
      "WHERE sql_name =",
      old_name_sql
    )
  )

  invisible(new_name)
}
