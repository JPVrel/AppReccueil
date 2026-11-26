# Lit le YAML de configuration et transforme les chemins locaux en chemins absolus.
database_value_or <- function(value, fallback) {
  if (is.null(value)) fallback else value
}

is_absolute_local_path <- function(path) {
  grepl("^(?:/|[A-Za-z]:[/\\\\]|\\\\\\\\)", path, perl = TRUE)
}

read_database_config <- function(config_path) {
  raw_config <- yaml::read_yaml(config_path)
  database_config <- raw_config$database

  if (is.null(database_config)) {
    stop("La configuration doit contenir une section 'database'.")
  }

  mode <- database_value_or(database_config$mode, "local")
  if (!mode %in% c("local", "remote")) {
    stop("Le mode de base de données doit être 'local' ou 'remote'.")
  }

  project_dir <- dirname(dirname(normalizePath(
    config_path,
    winslash = "/",
    mustWork = FALSE
  )))
  database_config$mode <- mode
  database_config$project_dir <- project_dir

  if (identical(mode, "local")) {
    local_path <- database_value_or(
      database_config$local$path,
      file.path("data", "recueil.sqlite")
    )
    if (!is_absolute_local_path(local_path)) {
      local_path <- file.path(project_dir, local_path)
    }
    database_config$local$path <- normalizePath(
      local_path,
      winslash = "/",
      mustWork = FALSE
    )
  }

  database_config
}
