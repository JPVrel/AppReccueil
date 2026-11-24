# macOS fournit lsof, qui permet de retrouver le PID du serveur qui écoute
# sur le port choisi. L'absence de résultat signifie simplement « pas encore prêt ».
find_listening_pids <- function(port, system_runner = system2) {
  pids <- suppressWarnings(system_runner(
    "lsof",
    c(sprintf("-tiTCP:%d", port), "-sTCP:LISTEN"),
    stdout = TRUE,
    stderr = FALSE
  ))

  as.integer(pids[nzchar(pids)])
}

# Attend que le serveur commence à écouter, avec une limite pour éviter
# que la boîte de dialogue reste bloquée indéfiniment.
wait_for_server <- function(
  port,
  timeout = 10,
  interval = 0.1,
  find_pids = find_listening_pids,
  sleep_fn = Sys.sleep,
  now_fn = Sys.time
) {
  deadline <- now_fn() + timeout

  repeat {
    if (length(find_pids(port)) > 0) {
      return(TRUE)
    }

    if (now_fn() >= deadline) {
      return(FALSE)
    }

    sleep_fn(interval)
  }
}

# Démarre un nouveau processus R indépendant. Cette approche évite le fork
# de la session Positron, qui n'est pas autorisé dans cet environnement.
start_server_process <- function(
  config,
  system_runner = system2,
  wait_fn = wait_for_server,
  find_pids = find_listening_pids
) {
  system_runner(
    config$rscript,
    c("--vanilla", config$shiny_runner, as.character(config$port)),
    wait = FALSE,
    stdout = FALSE,
    stderr = FALSE
  )

  if (!wait_fn(config$port)) {
    return(NULL)
  }

  tail(find_pids(config$port), 1)
}

# Arrête uniquement le processus dont le PID a été mémorisé par le lanceur.
stop_server_process <- function(pid, kill_fn = tools::pskill) {
  if (!is.null(pid)) {
    kill_fn(pid)
  }

  invisible(NULL)
}
