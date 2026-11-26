testthat::test_that("find_listening_pids parses lsof output", {
  system_runner <- function(command, ...) {
    if (identical(command, "netstat")) {
      return(c(
        "  TCP    127.0.0.1:8000        0.0.0.0:0              LISTENING       1234",
        "  TCP    127.0.0.1:8000        0.0.0.0:0              LISTENING       5678"
      ))
    }
    c("1234", "5678", "")
  }
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

testthat::test_that("start_server_process returns its owned process handle", {
  process <- new.env(parent = emptyenv())
  process$get_pid <- function() 4321L
  process$is_alive <- function() TRUE
  process$kill <- function(...) NULL
  process$wait <- function(...) NULL
  command <- NULL
  arguments <- NULL
  ready_pid <- NULL
  config <- create_app_config("/tmp/project", port = 8123)

  started <- start_server_process(
    config,
    process_factory = function(command_arg, args_arg) {
      command <<- command_arg
      arguments <<- args_arg
      process
    },
    wait_fn = function(port, expected_pid, alive_fn, find_pids) {
      ready_pid <<- expected_pid
      TRUE
    },
    find_pids = function(...) 4321L
  )

  testthat::expect_identical(started, process)
  testthat::expect_equal(ready_pid, 4321L)
  testthat::expect_equal(command, config$rscript)
  testthat::expect_equal(arguments[[3]], "8123")
})

testthat::test_that("a foreign listener is not treated as the server or stopped", {
  process <- new.env(parent = emptyenv())
  process$alive <- TRUE
  process$killed <- FALSE
  process$get_pid <- function() 4321L
  process$is_alive <- function() process$alive
  process$kill <- function(grace) {
    process$killed <- TRUE
    process$alive <- FALSE
  }
  process$wait <- function(timeout) NULL
  config <- create_app_config("/tmp/project", port = 8123)
  current_time <- 0

  started <- start_server_process(
    config,
    process_factory = function(command_arg, args_arg) process,
    wait_fn = function(port, expected_pid, alive_fn, find_pids) {
      wait_for_server(
        port,
        timeout = 0,
        interval = 0,
        find_pids = function(...) 9876L,
        sleep_fn = function(...) NULL,
        now_fn = function() {
          current_time <<- current_time + 1
          current_time
        },
        expected_pid = expected_pid,
        alive_fn = alive_fn
      )
    },
    find_pids = function(...) 9876L
  )

  testthat::expect_null(started)
  testthat::expect_true(process$killed)
  testthat::expect_false(process$alive)
})

testthat::test_that("stop_server_process acts only on its process handle", {
  process <- new.env(parent = emptyenv())
  process$alive <- TRUE
  process$killed <- FALSE
  process$waited <- FALSE
  process$is_alive <- function() process$alive
  process$kill <- function(grace) {
    process$killed <- TRUE
    process$alive <- FALSE
  }
  process$wait <- function(timeout) process$waited <- TRUE

  stop_server_process(process)

  testthat::expect_true(process$killed)
  testthat::expect_true(process$waited)
  testthat::expect_no_error(stop_server_process(NULL))
})

testthat::test_that("parse_windows_listening_pids extracts listening TCP PIDs", {
  lines <- c(
    "  TCP    127.0.0.1:8000        0.0.0.0:0              LISTENING       4321",
    "  TCP    127.0.0.1:8001        0.0.0.0:0              LISTENING       4322"
  )

  testthat::expect_equal(parse_windows_listening_pids(lines, 8000), 4321L)
})
