# Transforme l'état technique du serveur en texte compréhensible dans la fenêtre.
launcher_status_text <- function(server_pid, app_url) {
  if (is.null(server_pid)) {
    return("Le serveur Shiny est arrêté.")
  }

  paste("Serveur lancé :", app_url)
}

# Construit la boîte de dialogue locale. Les fonctions de démarrage, d'arrêt,
# de navigation et de détection du port sont injectées pour isoler l'interface.
create_launcher_window <- function(
  config,
  start_fn,
  stop_fn,
  browse_fn = utils::browseURL,
  find_pids_fn = find_listening_pids
) {
  state <- new.env(parent = emptyenv())
  state$pid <- NULL

  # Le PID est conservé dans un environnement partagé par les callbacks
  # des boutons et par le nettoyage effectué à la fermeture de la fenêtre.
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

    # Le navigateur n'est ouvert qu'après confirmation que le serveur écoute.
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
      stop_fn(state$pid, config$port)
      tcltk::tkdestroy(window)
    }),
    padx = 24,
    pady = 16
  )

  # Attend les événements Tcl/Tk. La fonction reprend lorsque la fenêtre
  # est fermée, puis garantit un dernier arrêt du serveur.
  tcltk::tkwait.window(window)
  stop_fn(state$pid, config$port)
}
