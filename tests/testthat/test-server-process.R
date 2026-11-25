testthat::test_that("find_listening_pids parses lsof output", {
  system_runner <- function(...) c("1234", "5678", "")

  testthat::expect_equal(
    find_listening_pids(8000, system_runner),
    c(1234L, 5678L)
  )
})

testthat::test_that("wait_for_server returns when a process listens", {
  attempts <- 0L
  find_pids <- function(port) {
    attempts <<- attempts + 1L
    if (attempts >= 3L) 1234L else integer()
  }

  testthat::expect_true(
    wait_for_server(
      port = 8000,
      timeout = 10,
      interval = 0,
      find_pids = find_pids,
      sleep_fn = function(...) NULL,
      now_fn = function() attempts
    )
  )
})

testthat::test_that("wait_for_server times out when no process listens", {
  current_time <- 0
  now_fn <- function() {
    current_time <<- current_time + 1
    current_time
  }

  testthat::expect_false(
    wait_for_server(
      port = 8000,
      timeout = 2,
      interval = 0,
      find_pids = function(...) integer(),
      sleep_fn = function(...) NULL,
      now_fn = now_fn
    )
  )
})

testthat::test_that("start_server_process starts and returns the listening pid", {
  command <- NULL
  system_runner <- function(...) command <<- list(...)
  wait_fn <- function(...) TRUE
  find_pids <- function(...) 4321L
  config <- create_app_config("/tmp/project", port = 8123)

  pid <- start_server_process(config, system_runner, wait_fn, find_pids)

  testthat::expect_equal(pid, 4321L)
  testthat::expect_equal(command[[1]], config$rscript)
  testthat::expect_equal(command[[2]][[3]], "8123")
})

testthat::test_that("stop_server_process calls the injected killer", {
  killed_pid <- NULL
  kill_fn <- function(pid) killed_pid <<- pid

  stop_server_process(4321L, kill_fn = kill_fn)

  testthat::expect_equal(killed_pid, 4321L)
})

testthat::test_that("stop_server_process verifies the port and escalates", {
  terminated <- integer()
  forced <- integer()
  attempts <- 0L

  find_pids <- function(port) {
    attempts <<- attempts + 1L
    4321L
  }
  stop_server_process(
    4321L,
    port = 8000,
    kill_fn = function(pid) terminated <<- c(terminated, pid),
    force_kill_fn = function(pid, signal) forced <<- c(forced, pid),
    find_pids = find_pids,
    sleep_fn = function(...) NULL
  )

  testthat::expect_equal(terminated, 4321L)
  testthat::expect_true(4321L %in% forced)
})
