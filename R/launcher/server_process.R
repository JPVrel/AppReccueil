# macOS fournit lsof, qui permet de retrouver le PID du serveur qui écoute
# sur le port choisi. L'absence de résultat signifie simplement « pas encore prêt ».
parse_windows_listening_pids <- function(lines, port) {
  matching <- grepl(sprintf("127\\.0\\.0\\.1:%d", port), lines, fixed = FALSE)
  matching_lines <- lines[matching & grepl("\\bLISTENING\\b", lines)]
  fields <- strsplit(trimws(matching_lines), "\\s+")
  pids <- vapply(fields, function(parts) {
    if (length(parts) == 0L) NA_integer_ else suppressWarnings(as.integer(tail(parts, 1L)))
  }, integer(1))
  unique(pids[!is.na(pids) & pids > 0L])
}

find_listening_pids <- function(port, system_runner = system2) {
  platform <- Sys.info()[["sysname"]]

  if (identical(platform, "Windows")) {
    lines <- suppressWarnings(system_runner(
      "netstat",
      c("-ano", "-p", "tcp"),
      stdout = TRUE,
      stderr = FALSE
    ))
    pids <- parse_windows_listening_pids(lines, port)
    return(unique(pids[!is.na(pids) & pids > 0L]))
  }

  if (nzchar(Sys.which("lsof"))) {
    pids <- suppressWarnings(system_runner(
      "lsof",
      c(sprintf("-tiTCP:%d", port), "-sTCP:LISTEN"),
      stdout = TRUE,
      stderr = FALSE
    ))
  } else if (nzchar(Sys.which("ss"))) {
    lines <- suppressWarnings(system_runner(
      "ss",
      c("-ltnp", sprintf("sport = :%d", port)),
      stdout = TRUE,
      stderr = FALSE
    ))
    pids <- as.character(regmatches(lines, gregexpr("pid=[0-9]+", lines)))
    pids <- unlist(pids)
    pids <- sub("^pid=", "", pids)
  } else {
    return(integer())
  }

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
  now_fn = Sys.time,
  expected_pid = NULL,
  alive_fn = NULL
) {
  deadline <- now_fn() + timeout

  repeat {
    listening_pids <- find_pids(port)
    if (is.null(expected_pid) && length(listening_pids) > 0L) {
      return(TRUE)
    }
    if (!is.null(expected_pid) && expected_pid %in% listening_pids) {
      return(TRUE)
    }
    if (!is.null(alive_fn) && !isTRUE(alive_fn())) {
      return(FALSE)
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
  process_factory = function(command, args) {
    processx::process$new(
      command,
      args,
      stdin = "null",
      stdout = "null",
      stderr = "null",
      windows_hide_window = TRUE
    )
  },
  wait_fn = wait_for_server,
  find_pids = find_listening_pids
) {
  process <- process_factory(
    config$rscript,
    c("--vanilla", config$shiny_runner, as.character(config$port))
  )

  ready <- wait_fn(
    config$port,
    expected_pid = process$get_pid(),
    alive_fn = process$is_alive,
    find_pids = find_pids
  )
  if (!ready) {
    stop_server_process(process)
    return(NULL)
  }

  process
}

# Arrête uniquement le processus détenu par le handle retourné au démarrage.
stop_server_process <- function(
  process,
  grace = 1000,
  wait_timeout = 2000
) {
  if (is.null(process) || !process$is_alive()) {
    return(invisible(NULL))
  }

  process$kill(grace = grace)
  process$wait(timeout = wait_timeout)

  invisible(NULL)
}
