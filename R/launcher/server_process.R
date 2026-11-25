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
stop_server_process <- function(
  pid,
  port = NULL,
  kill_fn = tools::pskill,
  force_kill_fn = tools::pskill,
  find_pids = find_listening_pids,
  sleep_fn = Sys.sleep
) {
  target_pids <- if (is.null(pid)) integer() else as.integer(pid)
  if (!is.null(port)) {
    target_pids <- unique(c(target_pids, as.integer(find_pids(port))))
  }
  target_pids <- target_pids[!is.na(target_pids) & target_pids > 0L]

  if (length(target_pids) == 0L) {
    return(invisible(NULL))
  }

  for (target_pid in target_pids) {
    kill_fn(target_pid)
  }

  if (!is.null(port)) {
    for (attempt in seq_len(20L)) {
      remaining <- as.integer(find_pids(port))
      if (length(remaining) == 0L) {
        break
      }
      sleep_fn(0.05)
    }

    remaining <- as.integer(find_pids(port))
    if (length(remaining) > 0L) {
      for (target_pid in unique(c(target_pids, remaining))) {
        force_kill_fn(target_pid, tools::SIGKILL)
      }
    }
  }

  invisible(NULL)
}
