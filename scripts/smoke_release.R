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

response_status <- function(port) {
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
  readLines(connection, n = 1L, warn = FALSE)
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
  http_status <- response_status(port)
  if (!is.null(http_status)) {
    break
  }
  Sys.sleep(0.25)
}

if (is.null(http_status) || !grepl("^HTTP/1[.]1 200", http_status)) {
  stop(
    "Le serveur n'a pas répondu HTTP 200 dans le délai imparti. Réponse : ",
    if (is.null(http_status)) "aucune" else http_status, "\n",
    server$read_all_output(), "\n",
    server$read_all_error()
  )
}

invisible(server$kill())
cat("Smoke test réussi : l'archive extraite démarre Shiny et répond HTTP 200.\n")