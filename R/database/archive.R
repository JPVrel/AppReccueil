# Le masquage change le nom SQL interne, mais conserve les valeurs et l'identité du champ.
rename_physical_column <- function(connection, old_name, new_name) {
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
}

update_column_archive_state <- function(connection, column_id, name, sql_name, is_hidden) {
  sql_name_value <- if (is.null(sql_name)) "NULL" else quote_sql_value(connection, sql_name)
  hidden_value <- if (isTRUE(is_hidden)) 1L else 0L
  DBI::dbExecute(
    connection,
    paste(
      "UPDATE column_definitions SET name =",
      quote_sql_value(connection, name),
      ", sql_name =",
      sql_name_value,
      ", is_hidden =",
      hidden_value,
      "WHERE column_id =",
      quote_sql_value(connection, column_id)
    )
  )
}

next_archive_sql_name <- function(connection, name) {
  existing <- list_record_columns(connection)
  suffix <- 1L
  repeat {
    candidate <- paste0(name, "__hidden_", suffix)
    if (!candidate %in% existing) {
      return(candidate)
    }
    suffix <- suffix + 1L
  }
}

hide_column <- function(connection, column_id) {
  if (column_id %in% protected_record_columns()) {
    stop("Les colonnes techniques ne sont pas des colonnes personnalisées.")
  }
  definition <- get_column_definition(connection, column_id)
  if (isTRUE(definition$is_hidden[[1]])) {
    stop("La colonne est déjà masquée.")
  }
  if (definition$name[[1]] %in% protected_record_columns()) {
    stop("Les colonnes techniques ne sont pas des colonnes personnalisées.")
  }

  sql_name <- definition$sql_name[[1]]
  archive_name <- if (is.na(sql_name)) NULL else next_archive_sql_name(connection, definition$name[[1]])

  DBI::dbWithTransaction(connection, {
    if (!is.null(archive_name)) {
      rename_physical_column(connection, sql_name, archive_name)
    }
    update_column_archive_state(
      connection,
      column_id,
      name = definition$name[[1]],
      sql_name = archive_name,
      is_hidden = TRUE
    )
  })

  invisible(column_id)
}

next_restored_column_name <- function(connection, column_id, original_name) {
  # Garde le nom d'origine s'il est libre, sinon choisit le premier suffixe disponible.
  definitions <- list_column_definitions(connection)
  active_names <- c(protected_record_columns(), definitions$name)
  current_definition <- get_column_definition(connection, column_id)
  if (!is.na(current_definition$sql_name[[1]])) {
    active_names <- c(active_names, setdiff(list_record_columns(connection), current_definition$sql_name[[1]]))
  }

  if (!tolower(original_name) %in% tolower(active_names)) {
    return(original_name)
  }

  suffix <- 2L
  repeat {
    candidate <- paste0(original_name, "_", suffix)
    if (!tolower(candidate) %in% tolower(active_names)) {
      return(candidate)
    }
    suffix <- suffix + 1L
  }
}

restore_column <- function(connection, column_id, new_name = NULL) {
  definition <- get_column_definition(connection, column_id)
  if (!isTRUE(definition$is_hidden[[1]])) {
    stop("La colonne n'est pas masquée.")
  }

  restored_name <- if (is.null(new_name) || !nzchar(new_name)) {
    next_restored_column_name(connection, column_id, definition$name[[1]])
  } else {
    validate_record_column_name(new_name)
    current_definition <- get_column_definition(connection, column_id)
    active <- list_column_definitions(connection)
    physical_names <- setdiff(list_record_columns(connection), current_definition$sql_name)
    if (tolower(new_name) %in% tolower(c(protected_record_columns(), active$name, physical_names))) {
      stop("Ce nom de colonne est déjà utilisé. Choisis une autre entête.")
    }
    new_name
  }
  sql_name <- definition$sql_name[[1]]

  DBI::dbWithTransaction(connection, {
    if (!is.na(sql_name)) {
      rename_physical_column(connection, sql_name, restored_name)
    }
    update_column_archive_state(
      connection,
      column_id,
      name = restored_name,
      sql_name = if (is.na(sql_name)) NULL else restored_name,
      is_hidden = FALSE
    )
  })

  restored_name
}

rename_column_definition <- function(connection, column_id, new_name) {
  validate_record_column_name(new_name)
  definition <- get_column_definition(connection, column_id)
  if (isTRUE(definition$is_hidden[[1]])) {
    stop("Une colonne masquée doit être restaurée avant son renommage.")
  }

  definitions <- list_column_definitions(connection)
  other_ids <- definitions$column_id != column_id
  existing_names <- c(
    protected_record_columns(),
    definitions$name[other_ids],
    setdiff(list_record_columns(connection), definition$sql_name[[1]])
  )
  if (tolower(new_name) %in% tolower(existing_names)) {
    stop("Une colonne portant ce nom existe déjà.")
  }

  old_sql_name <- definition$sql_name[[1]]
  DBI::dbWithTransaction(connection, {
    if (!is.na(old_sql_name) && !identical(old_sql_name, new_name)) {
      rename_physical_column(connection, old_sql_name, new_name)
    }
    update_column_archive_state(
      connection,
      column_id,
      name = new_name,
      sql_name = if (is.na(old_sql_name)) NULL else new_name,
      is_hidden = FALSE
    )
  })

  invisible(new_name)
}
