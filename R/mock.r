#' Mock functions in a package.
#'
#' Executes code after temporarily substituting implementations of package
#' functions.  This is useful for testing code that relies on functions that are
#' slow, have unintended side effects or access resources that may not be
#' available when testing.
#'
#' @param ... named parameters redefine mocked functions, unnamed parameters
#'   will be evaluated after mocking the functions
#' @param .env the environment in which to patch the functions,
#'   defaults to the top-level environment.  A character is interpreted as
#'   package name.
#' @return The result of the last unnamed parameter
#' @export
#' @examples
#' with_mock(
#'   `base::all.equal` = function(x, y, ...) TRUE,
#'   {
#'     expect_equal(3, 5)
#'   }
#' )
#' throws_error()(expect_equal(3, 5))
with_mock <- function(..., .env = topenv()) {
  new_values <- eval(substitute(alist(...)))
  mock_qual_names <- names(new_values)

  if (all(mock_qual_names == "")) {
    warning("Not mocking anything. Please use named parameters to specify the functions you want to mock.")
    code_pos <- TRUE
  } else {
    code_pos <- (mock_qual_names == "")
  }
  code <- new_values[code_pos]

  mocks <- extract_mocks(new_values = new_values[!code_pos], .env = .env)

  on.exit(lapply(mocks, reset_mock), add = TRUE)
  lapply(mocks, set_mock)

  # Evaluate the code
  ret <- invisible(NULL)
  for (expression in code) {
    ret <- eval(expression, parent.frame())
  }
  ret
}

pkg_rx <- ".*[^:]"
colons_rx <- "::(?:[:]?)"
name_rx <- ".*"
pkg_and_name_rx <- sprintf("^(?:(%s)%s)?(%s)$", pkg_rx, colons_rx, name_rx)

extract_mocks <- function(new_values, .env) {
  if (is.character(.env))
    .env <- asNamespace(.env)
  mock_qual_names <- names(new_values)

  lapply(
    setNames(nm = mock_qual_names),
    function(qual_name) {
      pkg_name <- gsub(pkg_and_name_rx, "\\1", qual_name)

      name <- gsub(pkg_and_name_rx, "\\2", qual_name)

      if (pkg_name == "")
        envs <- list(.env)
      else {
        envs <- list(asNamespace(pkg_name))

        # Only look in list of exported functions if package is really loaded
        pkg_env_name <- sprintf("package:%s", pkg_name)
        if (pkg_env_name %in% search()) {
          export_env <- as.environment(pkg_env_name)
          if (exists(name, envir = export_env, inherits = FALSE))
            envs <- c(envs, export_env)
        }
      }

      if (!exists(name, envs[[1]], mode = "function"))
        stop("Function ", name, " not found in environment ",
             environmentName(envs[[1]]), ".")
      orig_value <- get(name, envs[[1]], mode = "function")
      structure(list(envs = envs, name = name, orig_value = orig_value, new_value = eval(new_values[[qual_name]])),
                class = "mock")
    }
  )
}

set_mock <- function(mock) {
  for (env in mock$envs) {
    do.call("unlockBinding", list(mock$name, env))
    env[[mock$name]] <- mock$new_value
  }
  invisible(NULL)
}

reset_mock <- function(mock) {
  for (env in mock$envs) {
    if (!bindingIsLocked(mock$name, env)) {
      env[[mock$name]] <- mock$orig_value
      lockBinding(mock$name, env)
    }
  }
  invisible(NULL)
}
