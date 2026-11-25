# Point de lecture commun : les formules sont recalculées depuis les valeurs sources
# et les colonnes masquées sont retirées du résultat destiné à l'application.
read_collection_records <- function(connection, include_deleted = FALSE) {
  records <- DBI::dbReadTable(connection, record_table_name())
  if ("is_deleted" %in% names(records)) {
    if (!isTRUE(include_deleted)) {
      records <- records[!as.logical(records$is_deleted), , drop = FALSE]
    }
    records$is_deleted <- NULL
  }
  definitions <- list_column_definitions(connection, include_hidden = TRUE)
  date_definitions <- definitions[
    definitions$data_type == "date" & !is.na(definitions$sql_name),
    ,
    drop = FALSE
  ]
  for (row_index in seq_len(nrow(date_definitions))) {
    sql_name <- date_definitions$sql_name[[row_index]]
    if (!sql_name %in% names(records) || inherits(records[[sql_name]], "Date")) {
      next
    }
    values <- records[[sql_name]]
    records[[sql_name]] <- if (is.numeric(values)) {
      as.Date(values, origin = "1970-01-01")
    } else {
      as.Date(as.character(values), format = "%Y-%m-%d")
    }
  }
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

validate_collection_record_id <- function(record_id) {
  if (length(record_id) != 1L || is.na(record_id) ||
    !grepl("^[A-Za-z0-9][A-Za-z0-9_-]{0,35}$", record_id)) {
    stop("L'ID doit contenir 1 à 36 lettres, chiffres, tirets ou underscores, et commencer par une lettre ou un chiffre.")
  }
  invisible(record_id)
}

collection_record_exists <- function(connection, record_id) {
  DBI::dbGetQuery(
    connection,
    paste(
      "SELECT 1 AS found FROM", record_table_name(),
      "WHERE id =", quote_sql_value(connection, record_id), "LIMIT 1"
    )
  ) |> nrow() > 0L
}

new_collection_record_id <- function(connection) {
  repeat {
    candidate <- sub("^col_", "row_", generate_column_id())
    if (!collection_record_exists(connection, candidate)) {
      return(candidate)
    }
  }
}

active_record_field_definitions <- function(connection) {
  definitions <- list_column_definitions(connection)
  definitions[
    !definitions$is_hidden & !is.na(definitions$sql_name) &
      (is.na(definitions$formula) | !nzchar(definitions$formula)),
    ,
    drop = FALSE
  ]
}

validate_record_category_value <- function(connection, definition, value) {
  if (!identical(definition$data_type[[1]], "categorical") ||
    length(value) == 0L || is.na(value) || !nzchar(value)) {
    return(invisible(TRUE))
  }
  categories <- list_category_entries(connection, definition$column_id[[1]])
  if (!value %in% categories$code) {
    stop("La valeur choisie pour ", definition$name[[1]], " ne figure pas dans son dictionnaire.")
  }
  invisible(TRUE)
}

normalize_collection_record_values <- function(connection, values) {
  definitions <- active_record_field_definitions(connection)
  required_names <- definitions$name
  if (is.null(names(values)) || anyDuplicated(names(values)) ||
    !setequal(names(values), required_names)) {
    stop("Les champs du questionnaire ne correspondent plus à la structure active de la base.")
  }

  normalized <- stats::setNames(vector("list", length(required_names)), required_names)
  for (field_name in required_names) {
    definition <- definitions[definitions$name == field_name, , drop = FALSE]
    converted <- convert_import_column(values[[field_name]], definition$data_type[[1]], field_name)
    if (length(converted) != 1L) {
      stop("Chaque réponse doit contenir une seule valeur par champ.")
    }
    validate_record_category_value(connection, definition, converted)
    normalized[[field_name]] <- converted
  }
  normalized
}

record_sql_value <- function(connection, value) {
  if (length(value) == 0L || is.na(value)) {
    return("NULL")
  }
  if (inherits(value, "Date")) {
    value <- as.numeric(value)
  }
  as.character(DBI::dbQuoteLiteral(connection, value))
}

insert_collection_record <- function(connection, values, record_id = NULL) {
  record_id <- if (is.null(record_id) || !nzchar(record_id)) {
    new_collection_record_id(connection)
  } else {
    record_id
  }
  validate_collection_record_id(record_id)
  if (collection_record_exists(connection, record_id)) {
    stop("Cet ID existe déjà. Choisis un autre ID avant d'enregistrer la ligne.")
  }
  normalized <- normalize_collection_record_values(connection, values)
  record <- data.frame(
    id = record_id,
    created_at = format(Sys.time(), "%Y-%m-%d %H:%M:%OS", tz = "UTC"),
    payload = "{}",
    is_deleted = 0L,
    stringsAsFactors = FALSE
  )
  for (field_name in names(normalized)) {
    record[[field_name]] <- normalized[[field_name]]
  }
  DBI::dbWithTransaction(connection, {
    if (collection_record_exists(connection, record_id)) {
      stop("Cet ID existe déjà. Choisis un autre ID avant d'enregistrer la ligne.")
    }
    DBI::dbAppendTable(connection, record_table_name(), record)
  })
  invisible(record_id)
}

update_collection_record <- function(connection, original_id, new_id, values) {
  validate_collection_record_id(original_id)
  if (!collection_record_exists(connection, original_id)) {
    stop("La ligne à modifier n'existe plus.")
  }
  record_state <- DBI::dbGetQuery(
    connection,
    paste(
      "SELECT is_deleted FROM", record_table_name(),
      "WHERE id =", quote_sql_value(connection, original_id)
    )
  )
  if (nrow(record_state) != 1L || isTRUE(as.logical(record_state$is_deleted[[1]]))) {
    stop("Une ligne masquée ne peut pas être modifiée ; restaure-la d'abord.")
  }

  validate_collection_record_id(new_id)
  if (!identical(original_id, new_id) && collection_record_exists(connection, new_id)) {
    stop("Cet ID existe déjà. Choisis un autre ID avant d'enregistrer la ligne.")
  }
  normalized <- normalize_collection_record_values(connection, values)
  definitions <- active_record_field_definitions(connection)
  table_sql <- as.character(DBI::dbQuoteIdentifier(connection, record_table_name()))
  id_sql <- as.character(DBI::dbQuoteIdentifier(connection, "id"))

  assignments <- vapply(names(normalized), function(field_name) {
    definition <- definitions[definitions$name == field_name, , drop = FALSE]
    column_sql <- as.character(DBI::dbQuoteIdentifier(connection, definition$sql_name[[1]]))
    paste(column_sql, "=", record_sql_value(connection, normalized[[field_name]]))
  }, character(1))

  DBI::dbWithTransaction(connection, {
    if (!identical(original_id, new_id) && collection_record_exists(connection, new_id)) {
      stop("Cet ID existe déjà. Choisis un autre ID avant d'enregistrer la ligne.")
    }
    DBI::dbExecute(
      connection,
      paste(
        "UPDATE", table_sql,
        "SET id =", quote_sql_value(connection, new_id), ",", paste(assignments, collapse = ", "),
        "WHERE", id_sql, "=", quote_sql_value(connection, original_id),
        "AND is_deleted = 0"
      )
    )
  })
  invisible(new_id)
}

mask_collection_record <- function(connection, record_id) {
  validate_collection_record_id(record_id)
  updated <- DBI::dbExecute(
    connection,
    paste(
      "UPDATE", record_table_name(), "SET is_deleted = 1 WHERE id =",
      quote_sql_value(connection, record_id), "AND is_deleted = 0"
    )
  )
  if (updated != 1L) {
    stop("La ligne n'existe pas ou est déjà masquée.")
  }
  invisible(record_id)
}

list_deleted_collection_records <- function(connection) {
  records <- DBI::dbReadTable(connection, record_table_name())
  records <- records[as.logical(records$is_deleted), , drop = FALSE]
  records$is_deleted <- NULL
  definitions <- list_column_definitions(connection, include_hidden = TRUE)
  records <- calculate_derived_columns(records, definitions)
  hidden_sql_names <- definitions$sql_name[definitions$is_hidden & !is.na(definitions$sql_name)]
  records[, setdiff(names(records), hidden_sql_names), drop = FALSE]
}

restore_collection_record <- function(connection, record_id, new_id = NULL) {
  validate_collection_record_id(record_id)
  new_id <- if (is.null(new_id) || !nzchar(new_id)) record_id else new_id
  validate_collection_record_id(new_id)

  DBI::dbWithTransaction(connection, {
    current <- DBI::dbGetQuery(
      connection,
      paste(
        "SELECT is_deleted FROM", record_table_name(),
        "WHERE id =", quote_sql_value(connection, record_id)
      )
    )
    if (nrow(current) != 1L || !isTRUE(as.logical(current$is_deleted[[1]]))) {
      stop("La ligne n'existe pas dans les éléments supprimés.")
    }
    if (!identical(record_id, new_id) && collection_record_exists(connection, new_id)) {
      stop("Cet ID existe déjà. Choisis un autre ID pour restaurer la ligne.")
    }
    restored <- DBI::dbExecute(
      connection,
      paste(
        "UPDATE", record_table_name(), "SET id =", quote_sql_value(connection, new_id),
        ", is_deleted = 0 WHERE id =", quote_sql_value(connection, record_id), "AND is_deleted = 1"
      )
    )
    if (restored != 1L) {
      stop("La ligne a changé avant sa restauration ; recharge la liste puis réessaie.")
    }
  })
  invisible(new_id)
}
