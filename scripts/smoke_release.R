args <- commandArgs(trailingOnly = TRUE)
if (length(args) != 1L) {
  stop("Usage: Rscript scripts/smoke_release.R path/to/release.zip-or-directory")
}

archive_input <- path.expand(args[[1]])
if (dir.exists(archive_input)) {
  archives <- list.files(archive_input, pattern = "[.]zip$", full.names = TRUE, ignore.case = TRUE)
  if (length(archives) != 1L) {
    stop("Le dossier doit contenir exactement une archive ZIP de release.")
  }
  archive_input <- archives[[1]]
}
archive_path <- normalizePath(archive_input, mustWork = TRUE)
if (!requireNamespace("processx", quietly = TRUE)) {
  stop("Le smoke test requiert le package processx du profil development.")
}

smoke_root <- tempfile("appreccueil-smoke-")
dir.create(smoke_root)
on.exit(unlink(smoke_root, recursive = TRUE), add = TRUE)
invisible(utils::unzip(archive_path, exdir = smoke_root))

release_dir <- file.path(smoke_root, "AppReccueil")
runner_path <- file.path(release_dir, "shiny", "run_app.R")
if (!file.exists(runner_path)) {
  stop("L'archive ne contient pas le lanceur Shiny attendu.")
}

port <- sample(20000:60000, 1L)
rscript <- file.path(R.home("bin"), if (.Platform$OS.type == "windows") "Rscript.exe" else "Rscript")
server <- processx::process$new(
  command = rscript,
  args = c("--vanilla", runner_path, as.character(port)),
  wd = release_dir,
  stdout = "|",
  stderr = "|",
  cleanup_tree = TRUE
)
on.exit(if (server$is_alive()) server$kill(), add = TRUE)

read_app_response <- function(port) {
  connection <- tryCatch(
    suppressWarnings(
      socketConnection(
        host = "127.0.0.1",
        port = port,
        open = "r+",
        blocking = TRUE,
        timeout = 1
      )
    ),
    error = function(error) NULL
  )
  if (is.null(connection)) {
    return(NULL)
  }
  on.exit(close(connection), add = TRUE)

  writeLines(
    c("GET / HTTP/1.1", "Host: 127.0.0.1", "Connection: close", ""),
    connection
  )
  response_lines <- readLines(connection, warn = FALSE)
  if (length(response_lines) == 0L) {
    return(NULL)
  }

  header_end <- which(!nzchar(response_lines))
  if (length(header_end) == 0L) {
    return(list(status = response_lines[[1]], body = ""))
  }

  list(
    status = response_lines[[1]],
    body = paste(response_lines[seq.int(header_end[[1]] + 1L, length(response_lines))], collapse = "\n")
  )
}

deadline <- Sys.time() + 30
http_status <- NULL
while (Sys.time() < deadline) {
  if (!server$is_alive()) {
    stop(
      "Le serveur Shiny s'est arrêté avant de répondre. Sortie : ",
      server$get_exit_status(), "\n",
      server$read_all_output(), "\n",
      server$read_all_error()
    )
  }
  http_response <- read_app_response(port)
  if (!is.null(http_response)) {
    break
  }
  Sys.sleep(0.25)
}

if (is.null(http_response) || !grepl("^HTTP/1[.]1 200", http_response$status)) {
  stop(
    "Le serveur n'a pas répondu HTTP 200 dans le délai imparti. Réponse : ",
    if (is.null(http_response)) "aucune" else http_response$status, "\n",
    server$read_all_output(), "\n",
    server$read_all_error()
  )
}

visible_home_content <- c("Application de recueil", "Votre espace de données", "Importer des données")
missing_content <- visible_home_content[!vapply(
  visible_home_content,
  grepl,
  logical(1),
  x = http_response$body,
  fixed = TRUE
)]
if (length(missing_content) > 0L) {
  stop(
    "La page HTTP répond, mais son contenu d'accueil est incomplet. Éléments absents : ",
    paste(missing_content, collapse = ", ")
  )
}

invisible(server$kill())
cat("Smoke test réussi : Shiny démarre, répond HTTP 200 et affiche les contrôles d'accueil.\n")