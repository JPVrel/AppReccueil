database_import_types <- function() {
  c(
    "Texte" = "text",
    "Entier" = "integer",
    "Décimal" = "real",
    "Numérique" = "numeric",
    "Date" = "date",
    "Booléen" = "boolean",
    "Catégorielle" = "categorical"
  )
}

normalize_import_field_names <- function(source_names) {
  if (length(source_names) == 0L || anyNA(source_names) || any(!nzchar(trimws(source_names)))) {
    stop("Chaque colonne importée doit avoir un en-tête non vide.")
  }
  if (anyDuplicated(tolower(source_names))) {
    stop("Les en-têtes importés doivent être uniques, sans distinction de casse.")
  }

  field_names <- trimws(source_names)
  field_names <- gsub("[^A-Za-z0-9_]", "_", field_names)
  field_names <- gsub("_+", "_", field_names)
  field_names[!grepl("^[A-Za-z]", field_names)] <- paste0(
    "field_",
    field_names[!grepl("^[A-Za-z]", field_names)]
  )
  reserved <- tolower(field_names) %in% c("id", "created_at", "payload")
  field_names[reserved] <- paste0("source_", field_names[reserved])
  field_names <- make.unique(field_names, sep = "_")
  field_names <- gsub("\\.", "_", field_names)

  mapping <- data.frame(
    source_name = source_names,
    field_name = field_names,
    stringsAsFactors = FALSE
  )
  if (anyDuplicated(tolower(mapping$field_name))) {
    stop("Les noms des colonnes importées ne peuvent pas être rendus uniques automatiquement.")
  }
  mapping
}

database_import_limits <- function() {
  list(
    file_bytes = 25 * 1024^2,
    xlsx_expanded_bytes = 100 * 1024^2,
    rows = 50000L,
    columns = 500L,
    cells = 1000000
  )
}

validate_database_import_file <- function(path, extension) {
  limits <- database_import_limits()
  info <- file.info(path)
  if (nrow(info) != 1L || is.na(info$size) || info$size > limits$file_bytes) {
    stop("Le fichier dépasse la limite de taille autorisée de 25 Mio.")
  }

  if (identical(extension, "xlsx")) {
    archive <- tryCatch(utils::unzip(path, list = TRUE), error = function(error) NULL)
    if (is.null(archive) || !"Length" %in% names(archive) ||
      anyNA(archive$Length) || sum(archive$Length) > limits$xlsx_expanded_bytes) {
      stop("Le classeur Excel est invalide ou dépasse la limite de décompression autorisée.")
    }
  }

  invisible(TRUE)
}

import_row_limit <- function(column_count, limits = database_import_limits()) {
  if (length(column_count) != 1L || is.na(column_count) || column_count < 1L) {
    stop("Le fichier doit contenir au moins une colonne.")
  }
  if (column_count > limits$columns) {
    stop("Le tableau dépasse les limites autorisées (500 colonnes maximum).")
  }
  min(limits$rows, floor(limits$cells / column_count))
}

read_database_import_file <- function(path, file_name = path) {
  extension <- tolower(tools::file_ext(file_name))
  if (!extension %in% c("csv", "xlsx", "rds")) {
    stop("Le fichier doit être au format CSV, XLSX ou RDS.")
  }
  validate_database_import_file(path, extension)
  limits <- database_import_limits()
  header <- switch(
    extension,
    csv = utils::read.csv(
      path,
      check.names = FALSE,
      colClasses = "character",
      na.strings = "",
      stringsAsFactors = FALSE,
      nrows = 0L
    ),
    xlsx = as.data.frame(
      readxl::read_excel(path, col_types = "text", n_max = 0L, .name_repair = "minimal"),
      check.names = FALSE,
      stringsAsFactors = FALSE
    ),
    rds = NULL
  )
  row_limit <- if (extension == "rds") NULL else import_row_limit(ncol(header), limits)
  imported <- switch(
    extension,
    csv = utils::read.csv(
      path,
      check.names = FALSE,
      colClasses = "character",
      na.strings = "",
      stringsAsFactors = FALSE,
      nrows = row_limit + 1L
    ),
    xlsx = as.data.frame(
      readxl::read_excel(
        path,
        col_types = "text",
        n_max = row_limit + 1L,
        .name_repair = "minimal"
      ),
      check.names = FALSE,
      stringsAsFactors = FALSE
    ),
    rds = tryCatch(
      readRDS(path),
      error = function(error) stop("Le fichier RDS est invalide ou incompatible.", call. = FALSE)
    ),
    stop("Le fichier doit être au format CSV, XLSX ou RDS.")
  )
  if (!is.data.frame(imported) || ncol(imported) == 0L) {
    stop("Le fichier doit contenir au moins une colonne de données.")
  }
  if (nrow(imported) > limits$rows || ncol(imported) > limits$columns ||
    as.double(nrow(imported)) * as.double(ncol(imported)) > limits$cells) {
    stop("Le tableau dépasse les limites autorisées (50 000 lignes, 500 colonnes, 1 million de cellules).")
  }
  if (!is.null(row_limit) && nrow(imported) > row_limit) {
    stop("Le tableau dépasse les limites autorisées (50 000 lignes, 500 colonnes, 1 million de cellules).")
  }
  if (any(vapply(imported, is.list, logical(1)))) {
    stop("Les colonnes contenant des listes ne peuvent pas être importées.")
  }

  mapping <- normalize_import_field_names(names(imported))
  names(imported) <- mapping$field_name
  attr(imported, "source_headers") <- mapping$source_name
  imported
}

read_database_import_upload <- function(path, file_name, password = NULL) {
  if (!grepl("[.]enc$", tolower(file_name))) {
    return(read_database_import_file(path, file_name))
  }
  encrypted_size <- file.info(path)$size
  if (is.na(encrypted_size) || encrypted_size > database_import_limits()$file_bytes + vault_envelope_header_bytes()) {
    stop("L'export chiffré dépasse la limite d'import de 25 Mio.")
  }
  if (is.null(password) || !nzchar(password)) {
    stop("Saisis le mot de passe de ce fichier chiffré.")
  }

  decrypted_name <- sub("[.]enc$", "", basename(file_name), ignore.case = TRUE)
  extension <- tools::file_ext(decrypted_name)
  workspace <- new_private_database_workspace()
  on.exit(unlink(workspace$directory, recursive = TRUE), add = TRUE)
  decrypted_path <- file.path(workspace$directory, paste0("import.", extension))
  decrypt_file_with_password(path, decrypted_path, password)
  read_database_import_file(decrypted_path, decrypted_name)
}

clean_import_values <- function(values) {
  if (is.factor(values)) {
    values <- as.character(values)
  }
  if (is.character(values)) {
    values[!is.na(values) & !nzchar(trimws(values))] <- NA_character_
  }
  values
}

parse_integer_import_value <- function(value) {
  value <- trimws(value)
  match <- regmatches(
    value,
    regexec("^([+-]?)([0-9]+)(?:[.]([0-9]*))?(?:[eE]([+-]?[0-9]+))?$", value, perl = TRUE)
  )[[1]]
  if (length(match) == 0L) {
    return(list(valid = FALSE, in_range = TRUE, value = NA_integer_))
  }

  sign <- match[[2]]
  whole <- match[[3]]
  fraction <- match[[4]]
  if (is.na(fraction)) fraction <- ""
  digits <- paste0(whole, fraction)
  significant <- sub("^0+", "", digits)
  if (!nzchar(significant)) {
    return(list(valid = TRUE, in_range = TRUE, value = 0L))
  }

  exponent <- if (length(match) >= 5L && !is.na(match[[5]]) && nzchar(match[[5]])) {
    suppressWarnings(as.numeric(match[[5]]))
  } else {
    0
  }
  if (!is.finite(exponent) || abs(exponent) > 10000) {
    return(list(valid = TRUE, in_range = FALSE, value = NA_integer_))
  }

  decimal_position <- nchar(whole) + exponent
  if (decimal_position <= 0) {
    return(list(valid = FALSE, in_range = TRUE, value = NA_integer_))
  }
  if (decimal_position < nchar(digits)) {
    trailing <- substr(digits, decimal_position + 1, nchar(digits))
    if (grepl("[1-9]", trailing)) {
      return(list(valid = FALSE, in_range = TRUE, value = NA_integer_))
    }
    digits <- substr(digits, 1, decimal_position)
  } else if (decimal_position > nchar(digits)) {
    if (decimal_position > 10) {
      return(list(valid = TRUE, in_range = FALSE, value = NA_integer_))
    }
    digits <- paste0(digits, strrep("0", decimal_position - nchar(digits)))
  }

  magnitude <- sub("^0+", "", digits)
  if (!nzchar(magnitude)) magnitude <- "0"
  limit <- as.character(.Machine$integer.max)
  in_range <- nchar(magnitude) < nchar(limit) ||
    (nchar(magnitude) == nchar(limit) && magnitude <= limit)
  if (!in_range) {
    return(list(valid = TRUE, in_range = FALSE, value = NA_integer_))
  }

  numeric_value <- as.numeric(magnitude)
  if (identical(sign, "-")) numeric_value <- -numeric_value
  list(valid = TRUE, in_range = TRUE, value = as.integer(numeric_value))
}

convert_import_column <- function(values, data_type, field_name = "colonne") {
  if (length(data_type) != 1L || is.na(data_type) || !data_type %in% column_definition_types()) {
    stop("Type non pris en charge pour ", field_name, ".")
  }
  values <- clean_import_values(values)
  missing <- is.na(values)
  text <- as.character(values)
  text[missing] <- NA_character_

  if (data_type %in% c("text", "categorical")) {
    return(text)
  }
  if (identical(data_type, "date")) {
    if (inherits(values, "Date")) {
      return(values)
    }
    parsed <- as.Date(text, format = "%Y-%m-%d")
    if (any(!missing & is.na(parsed))) {
      stop("La colonne ", field_name, " contient une date qui n'est pas au format AAAA-MM-JJ.")
    }
    return(parsed)
  }
  if (identical(data_type, "boolean")) {
    normalized <- tolower(trimws(text))
    true_values <- c("true", "t", "1", "yes", "oui")
    false_values <- c("false", "f", "0", "no", "non")
    invalid <- !missing & !normalized %in% c(true_values, false_values)
    if (any(invalid)) {
      stop("La colonne ", field_name, " contient une valeur booléenne invalide.")
    }
    return(ifelse(missing, NA, normalized %in% true_values))
  }

  if (identical(data_type, "integer") && is.character(values)) {
    parsed <- lapply(text[!missing], parse_integer_import_value)
    if (any(!vapply(parsed, `[[`, logical(1), "valid"))) {
      stop("La colonne ", field_name, " contient une valeur qui n'est pas entière.")
    }
    if (any(!vapply(parsed, `[[`, logical(1), "in_range"))) {
      stop("La colonne ", field_name, " contient une valeur hors de la plage des entiers pris en charge.")
    }

    result <- rep(NA_integer_, length(values))
    result[!missing] <- vapply(parsed, `[[`, integer(1), "value")
    return(result)
  }

  numeric_values <- suppressWarnings(as.numeric(text))
  invalid <- !missing & (is.na(numeric_values) | !is.finite(numeric_values))
  if (any(invalid)) {
    stop("La colonne ", field_name, " contient une valeur numérique invalide.")
  }
  if (identical(data_type, "integer")) {
    if (any(!missing & numeric_values != trunc(numeric_values))) {
      stop("La colonne ", field_name, " contient une valeur qui n'est pas entière.")
    }
    out_of_range <- !missing & (
      numeric_values <= -2147483648 | numeric_values > .Machine$integer.max
    )
    if (any(out_of_range)) {
      stop("La colonne ", field_name, " contient une valeur hors de la plage des entiers pris en charge.")
    }
    return(as.integer(numeric_values))
  }
  numeric_values
}

convert_database_import <- function(imported, types) {
  if (!is.data.frame(imported) || is.null(names(types)) ||
    !setequal(names(imported), names(types))) {
    stop("Un type doit être choisi pour chaque colonne importée.")
  }

  converted <- imported
  for (field_name in names(imported)) {
    converted[[field_name]] <- convert_import_column(
      imported[[field_name]],
      types[[field_name]],
      field_name
    )
  }
  converted
}

insert_imported_observations <- function(connection, imported) {
  if (nrow(imported) == 0L) {
    return(invisible(0L))
  }

  definitions <- list_column_definitions(connection)
  allowed_names <- definitions$name[!is.na(definitions$sql_name)]
  if (any(!names(imported) %in% allowed_names)) {
    stop("L'import contient des colonnes qui ne sont pas définies dans cette base.")
  }

  records <- data.frame(
    id = vapply(seq_len(nrow(imported)), function(index) generate_column_id(), character(1)),
    created_at = rep(format(Sys.time(), "%Y-%m-%d %H:%M:%OS", tz = "UTC"), nrow(imported)),
    payload = rep("{}", nrow(imported)),
    stringsAsFactors = FALSE,
    check.names = FALSE
  )
  records <- cbind(records, imported)
  DBI::dbAppendTable(connection, record_table_name(), records)
  invisible(nrow(imported))
}

add_import_categories <- function(connection, imported, definitions = list_column_definitions(connection)) {
  for (field_name in names(imported)) {
    definition <- definitions[definitions$name == field_name & definitions$data_type == "categorical", , drop = FALSE]
    if (nrow(definition) == 0L) {
      next
    }

    existing <- list_category_entries(connection, definition$column_id[[1]])
    values <- unique(imported[[field_name]][!is.na(imported[[field_name]])])
    for (value in values[!values %in% existing$code]) {
      add_category_entry(connection, definition$column_id[[1]], value, value)
    }
  }
}

create_imported_database <- function(connection, imported, types) {
  converted <- convert_database_import(imported, types)
  if (any(tolower(names(converted)) %in% c("id", "created_at", "payload"))) {
    stop("Les noms des champs importés ne peuvent pas être des colonnes système.")
  }

  DBI::dbWithTransaction(connection, {
    for (field_name in names(converted)) {
      data_type <- types[[field_name]]
      sql_type <- unname(field_sql_types()[[data_type]])
      column_id <- create_record_column(connection, field_name, sql_type)
      DBI::dbExecute(
        connection,
        paste(
          "UPDATE column_definitions SET data_type =",
          quote_sql_value(connection, data_type),
          "WHERE column_id =",
          quote_sql_value(connection, column_id)
        )
      )
    }
    add_import_categories(connection, converted)
    insert_imported_observations(connection, converted)
  })

  invisible(connection)
}

import_value_is_missing <- function(value) {
  length(value) == 0L || is.na(value) || (is.character(value) && !nzchar(trimws(value)))
}

import_values_equal <- function(left, right) {
  isTRUE(all.equal(left, right, check.attributes = FALSE))
}

prepare_import_merge <- function(connection, imported, key_field) {
  if (!is.data.frame(imported) || length(key_field) != 1L || is.na(key_field)) {
    stop("Sélectionne une colonne identifiante pour rapprocher les observations.")
  }
  definitions <- list_column_definitions(connection)
  physical <- definitions[!is.na(definitions$sql_name), , drop = FALSE]
  common <- physical$name[physical$name %in% names(imported)]
  if (!key_field %in% common) {
    stop("La clé choisie doit être présente dans le fichier et dans la base.")
  }

  common_definitions <- physical[match(common, physical$name), , drop = FALSE]
  converted <- imported[, common, drop = FALSE]
  for (field_name in common) {
    converted[[field_name]] <- convert_import_column(
      converted[[field_name]],
      common_definitions$data_type[match(field_name, common_definitions$name)],
      field_name
    )
  }
  if (anyNA(converted[[key_field]]) || anyDuplicated(converted[[key_field]])) {
    stop("La clé importée doit être renseignée et unique dans chaque ligne.")
  }

  current <- read_collection_records(connection)
  current_key <- current[[key_field]]
  if (anyNA(current_key) || anyDuplicated(current_key)) {
    stop("La clé choisie n'est pas renseignée et unique dans la base actuelle.")
  }
  matches <- match(converted[[key_field]], current_key)
  new_indices <- which(is.na(matches))
  fills <- list()
  conflicts <- list()

  for (import_index in which(!is.na(matches))) {
    current_index <- matches[[import_index]]
    for (field_name in setdiff(common, key_field)) {
      incoming_value <- converted[[field_name]][import_index]
      current_value <- current[[field_name]][current_index]
      if (import_value_is_missing(incoming_value)) {
        next
      }

      entry <- list(
        record_id = current$id[[current_index]],
        key_value = converted[[key_field]][[import_index]],
        field = field_name,
        current_value = current_value,
        incoming_value = incoming_value
      )
      if (import_value_is_missing(current_value)) {
        fills[[length(fills) + 1L]] <- entry
      } else if (!import_values_equal(current_value, incoming_value)) {
        conflicts[[length(conflicts) + 1L]] <- entry
      }
    }
  }

  list(
    key_field = key_field,
    definitions = common_definitions,
    imported = converted,
    new_rows = converted[new_indices, , drop = FALSE],
    fills = fills,
    conflicts = conflicts
  )
}

update_imported_value <- function(connection, record_id, field_name, value, definitions) {
  definition <- definitions[definitions$name == field_name, , drop = FALSE]
  if (nrow(definition) != 1L || is.na(definition$sql_name[[1]])) {
    stop("Le champ à mettre à jour n'existe plus dans la base.")
  }

  if (inherits(value, "Date")) {
    value <- format(value, "%Y-%m-%d")
  }
  table_sql <- as.character(DBI::dbQuoteIdentifier(connection, record_table_name()))
  field_sql <- as.character(DBI::dbQuoteIdentifier(connection, definition$sql_name[[1]]))
  id_sql <- as.character(DBI::dbQuoteIdentifier(connection, "id"))
  DBI::dbExecute(
    connection,
    paste(
      "UPDATE", table_sql, "SET", field_sql, "=", as.character(DBI::dbQuoteLiteral(connection, value)),
      "WHERE", id_sql, "=", quote_sql_value(connection, record_id)
    )
  )
}

apply_import_merge <- function(connection, plan, conflict_choices = character()) {
  if (length(conflict_choices) != length(plan$conflicts) ||
    any(!conflict_choices %in% c("existing", "imported"))) {
    stop("Arbitre chaque conflit avant d'appliquer l'import.")
  }

  definitions <- list_column_definitions(connection)
  current_plan <- NULL
  DBI::dbWithTransaction(connection, {
    current_plan <- prepare_import_merge(connection, plan$imported, plan$key_field)
    planned_parts <- c("definitions", "imported", "new_rows", "fills", "conflicts")
    plan_is_current <- all(vapply(planned_parts, function(part) {
      isTRUE(all.equal(plan[[part]], current_plan[[part]], check.attributes = FALSE))
    }, logical(1)))
    if (!plan_is_current) {
      stop("La base a changé depuis la comparaison ; relance l'analyse du fichier avant de valider.")
    }

    add_import_categories(connection, current_plan$new_rows, definitions)
    selected_values <- c(current_plan$fills, current_plan$conflicts[
      which(conflict_choices == "imported")
    ])
    for (entry in selected_values) {
      field_data <- data.frame(value = entry$incoming_value, stringsAsFactors = FALSE)
      names(field_data) <- entry$field
      add_import_categories(connection, field_data, definitions)
    }
    for (fill in current_plan$fills) {
      update_imported_value(connection, fill$record_id, fill$field, fill$incoming_value, definitions)
    }
    for (index in seq_along(current_plan$conflicts)) {
      if (identical(conflict_choices[[index]], "imported")) {
        conflict <- current_plan$conflicts[[index]]
        update_imported_value(connection, conflict$record_id, conflict$field, conflict$incoming_value, definitions)
      }
    }
    insert_imported_observations(connection, current_plan$new_rows)
  })

  invisible(list(
    inserted = nrow(current_plan$new_rows),
    filled = length(current_plan$fills),
    conflicts = length(current_plan$conflicts)
  ))
}