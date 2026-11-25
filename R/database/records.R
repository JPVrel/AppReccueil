# Point de lecture commun : les formules sont recalculées depuis les valeurs sources
# et les colonnes masquées sont retirées du résultat destiné à l'application.
read_collection_records <- function(connection) {
  records <- DBI::dbReadTable(connection, record_table_name())
  definitions <- list_column_definitions(connection, include_hidden = TRUE)
  records <- calculate_derived_columns(records, definitions)

  hidden_sql_names <- definitions$sql_name[definitions$is_hidden & !is.na(definitions$sql_name)]
  records <- records[, setdiff(names(records), hidden_sql_names), drop = FALSE]

  active_physical <- definitions[!definitions$is_hidden & !is.na(definitions$sql_name), , drop = FALSE]
  for (row_index in seq_len(nrow(active_physical))) {
    old_name <- active_physical$sql_name[[row_index]]
    new_name <- active_physical$name[[row_index]]
    if (old_name %in% names(records) && !identical(old_name, new_name)) {
      names(records)[names(records) == old_name] <- new_name
    }
  }

  records
}
