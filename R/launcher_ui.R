launcher_status_text <- function(server_pid, app_url) {
  if (is.null(server_pid)) {
    return("Le serveur Shiny est arrêté.")
  }

  paste("Serveur lancé :", app_url)
}

create_launcher_window <- function(
  config,
  start_fn,
  stop_fn,
  browse_fn = utils::browseURL,
  find_pids_fn = find_listening_pids
) {
  state <- new.env(parent = emptyenv())
  state$pid <- NULL

  window <- tcltk::tktoplevel()
  tcltk::tkwm.title(window, "Application de recueil")
  tcltk::tkgrid(
    tcltk::tklabel(window, text = "Application de recueil de données"),
    padx = 24,
    pady = 16
  )
  status_label <- tcltk::tklabel(window, text = launcher_status_text(NULL, config$app_url))
  tcltk::tkgrid(status_label, padx = 24, pady = 4)

  launch <- function() {
    if (!is.null(state$pid)) {
      return(invisible(NULL))
    }

    if (length(find_pids_fn(config$port)) > 0) {
      tcltk::tkconfigure(status_label, text = paste("Le port", config$port, "est déjà utilisé."))
      return(invisible(NULL))
    }

    state$pid <- start_fn(config)
    if (is.null(state$pid)) {
      tcltk::tkconfigure(status_label, text = "Le serveur n'a pas pu démarrer.")
      return(invisible(NULL))
    }

    browse_fn(config$app_url)
    tcltk::tkconfigure(status_label, text = launcher_status_text(state$pid, config$app_url))
  }

  tcltk::tkgrid(
    tcltk::tkbutton(window, text = "Lancer le serveur Shiny", command = launch),
    padx = 24,
    pady = 8
  )
  tcltk::tkgrid(
    tcltk::tkbutton(window, text = config$app_url, command = function() browse_fn(config$app_url)),
    padx = 24,
    pady = 4
  )
  tcltk::tkgrid(
    tcltk::tkbutton(window, text = "Tout quitter", command = function() {
      stop_fn(state$pid)
      tcltk::tkdestroy(window)
    }),
    padx = 24,
    pady = 16
  )

  tcltk::tkwait.window(window)
  stop_fn(state$pid)
}
