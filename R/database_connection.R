connect_database <- function(database_config) {
  if (identical(database_config$mode, "local")) {
    database_path <- database_config$local$path
    dir.create(dirname(database_path), recursive = TRUE, showWarnings = FALSE)

    return(DBI::dbConnect(
      RSQLite::SQLite(),
      dbname = database_path
    ))
  }

  remote_config <- database_config$remote
  driver_package <- remote_config$driver_package
  driver_class <- remote_config$driver_class

  if (!requireNamespace(driver_package, quietly = TRUE)) {
    stop("Le driver distant manquant : ", driver_package)
  }

  driver_factory <- getExportedValue(driver_package, driver_class)
  connection_arguments <- database_value_or(remote_config$connection, list())
  credentials <- database_value_or(remote_config$credentials, list())

  if (!is.null(credentials$user_env)) {
    connection_arguments$user <- Sys.getenv(credentials$user_env)
  }
  if (!is.null(credentials$password_env)) {
    connection_arguments$password <- Sys.getenv(credentials$password_env)
  }

  do.call(
    DBI::dbConnect,
    c(list(drv = driver_factory()), connection_arguments)
  )
}

disconnect_database <- function(connection) {
  if (!is.null(connection) && DBI::dbIsValid(connection)) {
    DBI::dbDisconnect(connection)
  }

  invisible(NULL)
}
