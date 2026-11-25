# Les réponses stockent le code de catégorie ; les libellés restent modifiables.
# Les changements de code et les réaffectations sont exécutés dans une transaction.
get_category_entry <- function(connection, category_id) {
  category_id_sql <- quote_sql_value(connection, category_id)
  category <- DBI::dbGetQuery(
    connection,
    paste("SELECT * FROM category_dictionary WHERE category_id =", category_id_sql)
  )

  if (nrow(category) == 0L) {
    stop("L'entrée du dictionnaire n'existe pas.")
  }

  category
}

validate_category_field <- function(connection, column_id) {
  definition <- get_column_definition(connection, column_id)
  if (!identical(definition$data_type, "categorical")) {
    stop("Le dictionnaire est disponible uniquement pour les colonnes catégorielles.")
  }
  if (isTRUE(definition$is_hidden)) {
    stop("Une colonne masquée ne peut pas être modifiée.")
  }

  definition
}

validate_category_text <- function(value, field_name) {
  if (length(value) != 1L || is.na(value) || !nzchar(trimws(value))) {
    stop("Le code et le libellé sont obligatoires.")
  }

  invisible(value)
}

list_category_entries <- function(connection, column_id) {
  validate_category_field(connection, column_id)
  column_id_sql <- quote_sql_value(connection, column_id)
  DBI::dbGetQuery(
    connection,
    paste(
      "SELECT category_id, column_id, code, label, sort_order",
      "FROM category_dictionary WHERE column_id =",
      column_id_sql,
      "ORDER BY sort_order, code"
    )
  )
}

add_category_entry <- function(connection, column_id, code, label) {
  validate_category_text(code, "code")
  validate_category_text(label, "label")
  definition <- validate_category_field(connection, column_id)
  existing <- list_category_entries(connection, column_id)

  if (code %in% existing$code) {
    stop("Une entrée avec ce code existe déjà.")
  }

  next_order <- if (nrow(existing) == 0L) 1L else max(existing$sort_order) + 1L
  category_id <- generate_column_id()
  DBI::dbExecute(
    connection,
    paste(
      "INSERT INTO category_dictionary",
      "(category_id, column_id, code, label, sort_order) VALUES (",
      paste(
        quote_sql_value(connection, category_id),
        quote_sql_value(connection, definition$column_id[[1]]),
        quote_sql_value(connection, code),
        quote_sql_value(connection, label),
        next_order,
        sep = ", "
      ),
      ")"
    )
  )

  category_id
}

update_category_entry <- function(connection, category_id, new_code, new_label) {
  validate_category_text(new_code, "code")
  validate_category_text(new_label, "label")
  category <- get_category_entry(connection, category_id)
  definition <- validate_category_field(connection, category$column_id[[1]])
  siblings <- list_category_entries(connection, definition$column_id[[1]])
  siblings <- siblings[siblings$category_id != category_id, , drop = FALSE]

  if (new_code %in% siblings$code) {
    stop("Une entrée avec ce code existe déjà.")
  }

  DBI::dbWithTransaction(connection, {
    if (!identical(category$code[[1]], new_code)) {
      table_sql <- as.character(DBI::dbQuoteIdentifier(connection, record_table_name()))
      column_sql <- as.character(DBI::dbQuoteIdentifier(connection, definition$sql_name[[1]]))
      DBI::dbExecute(
        connection,
        sprintf(
          "UPDATE %s SET %s = %s WHERE %s = %s",
          table_sql,
          column_sql,
          quote_sql_value(connection, new_code),
          column_sql,
          quote_sql_value(connection, category$code[[1]])
        )
      )
    }

    DBI::dbExecute(
      connection,
      paste(
        "UPDATE category_dictionary SET code =",
        quote_sql_value(connection, new_code),
        ", label =",
        quote_sql_value(connection, new_label),
        "WHERE category_id =",
        quote_sql_value(connection, category_id)
      )
    )
  })

  invisible(category_id)
}

remove_category_entry <- function(connection, category_id, replacement_category_id = NULL) {
  if (is.null(replacement_category_id)) {
    stop("Une réaffectation vers une autre catégorie est obligatoire.")
  }

  category <- get_category_entry(connection, category_id)
  definition <- validate_category_field(connection, category$column_id[[1]])
  replacement <- get_category_entry(connection, replacement_category_id)

  if (!identical(category$column_id[[1]], replacement$column_id[[1]])) {
    stop("La catégorie de remplacement doit appartenir au même dictionnaire.")
  }
  if (identical(category_id, replacement_category_id)) {
    stop("La catégorie de remplacement doit être différente.")
  }

  table_sql <- as.character(DBI::dbQuoteIdentifier(connection, record_table_name()))
  column_sql <- as.character(DBI::dbQuoteIdentifier(connection, definition$sql_name[[1]]))

  DBI::dbWithTransaction(connection, {
    DBI::dbExecute(
      connection,
      sprintf(
        "UPDATE %s SET %s = %s WHERE %s = %s",
        table_sql,
        column_sql,
        quote_sql_value(connection, replacement$code[[1]]),
        column_sql,
        quote_sql_value(connection, category$code[[1]])
      )
    )
    DBI::dbExecute(
      connection,
      paste(
        "DELETE FROM category_dictionary WHERE category_id =",
        quote_sql_value(connection, category_id)
      )
    )
  })

  invisible(replacement_category_id)
}
