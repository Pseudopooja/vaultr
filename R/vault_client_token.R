##' Interact with vault's token methods.  This includes support for
##' querying, creating and deleting tokens.  Tokens are fundamental to
##' the way that vault works, so there are a lot of methods here.  The
##' \href{https://www.vaultproject.io/docs/concepts/tokens.html}{vault
##' documentation has a page devoted to token concepts} and
##' \href{https://www.vaultproject.io/docs/commands/token/index.html}{another
##' with commands} that have names very similar to the names used
##' here.
##'
##' @section Token Accessors:
##'
##' Many of the methods use "token accessors" - whenever a token is
##' created, an "accessor" is created at the same time.  This is
##' another token that can be used to perform limited actions with the
##' token such as
##'
##' \itemize{
##' \item Look up a token's properties (not including the actual token ID)
##' \item Look up a token's capabilities on a path
##' \item Revoke the token
##' }
##'
##' However, accessors cannot be used to login, nor to retrieve the
##' actual token itself.
##'
##' @template vault_client_token
##'
##' @title Vault Tokens
##' @name vault_client_token
##' @examples
##'
##' server <- vaultr::vault_test_server(if_disabled = message)
##' if (!is.null(server)) {
##'   client <- server$client()
##'
##'   # There are lots of token methods here:
##'   client$token
##'
##'   # To demonstrate, it will be useful to create a restricted
##'   # policy that can only read from the /secret path
##'   rules <- 'path "secret/*" {policy = "read"}'
##'   client$policy$write("read-secret", rules)
##'   client$write("/secret/path", list(key = "value"))
##'
##'   # Create a token that has this policy
##'   token <- client$auth$token$create(policies = "read-secret")
##'   alice <- vaultr::vault_client(addr = server$addr)
##'   alice$login(method = "token", token = token)
##'   alice$read("/secret/path")
##'
##'   client$token$lookup(token)
##'
##'   # We can query the capabilities of this token
##'   client$token$capabilities("secret/path", token)
##'
##'   # Tokens are not safe to pass around freely because they *are*
##'   # the ability to login, but the `token$create` command also
##'   # provides an accessor:
##'   accessor <- attr(token, "info")$accessor
##'
##'   # It is not possible to derive the token from the accessor, but
##'   # we can use the accessor to ask vault what it could do if it
##'   # did have the token (and do things like revoke the token)
##'   client$token$capabilities_accessor("secret/path", accessor)
##'
##'   client$token$revoke_accessor(accessor)
##'   try(client$token$capabilities_accessor("secret/path", accessor))
##'
##'   # cleanup
##'   server$kill()
##' }
NULL


vault_client_token <- R6::R6Class(
  "vault_client_token",
  inherit = vault_client_object,
  cloneable = FALSE,

  private = list(
    api_client = NULL
  ),

  public = list(
    initialize = function(api_client) {
      super$initialize("Interact and configure vault's token support")
      private$api_client <- api_client
    },

    list = function() {
      dat <- private$api_client$LIST("/auth/token/accessors")
      list_to_character(dat$data$keys)
    },

    capabilities = function(path, token) {
      body <- list(paths = I(assert_character(path)),
                   token = assert_scalar_character(token))
      data <- private$api_client$POST("/sys/capabilities", body = body)
      lapply(data$data[path], list_to_character)
    },

    capabilities_self = function(path) {
      body <- list(paths = I(assert_character(path)))
      data <- private$api_client$POST("/sys/capabilities-self", body = body)
      lapply(data$data[path], list_to_character)
    },

    capabilities_accessor = function(path, accessor) {
      body <- list(paths = I(assert_character(path)),
                   accessor = assert_scalar_character(accessor))
      data <- private$api_client$POST("/sys/capabilities-accessor", body = body)
      lapply(data$data[path], list_to_character)
    },

    client = function() {
      private$api_client$token
    },

    create = function(role_name = NULL, id = NULL, policies = NULL,
                      meta = NULL, orphan = FALSE, no_default_policy = FALSE,
                      max_ttl = NULL, display_name = NULL,
                      num_uses = 0L, period = NULL, ttl = NULL,
                      wrap_ttl = NULL) {
      body <- list(
        role_name = role_name %&&% assert_scalar_character(role_name),
        policies = policies %&&% I(assert_character(policies)),
        meta = meta,
        no_default_policy = assert_scalar_logical(no_default_policy),
        explicit_max_ttl = max_ttl %&&% assert_scalar_integer(max_ttl),
        display_name = display_name %&&% assert_scalar_character(display_name),
        num_uses = num_uses %&&% assert_scalar_integer(num_uses),
        ttl = ttl %&&% assert_is_duration(ttl),
        ## root only:
        id = role_name %&&% assert_scalar_character(id),
        period = period %&&% assert_is_duration(period),
        no_parent = assert_scalar_logical(orphan))
      body <- drop_null(body)
      res <- private$api_client$POST("/auth/token/create", body = body,
                                     wrap_ttl = wrap_ttl)
      if (is.null(wrap_ttl)) {
        info <- res$auth
        info$policies <- list_to_character(info$policies)
        token <- info$client_token
      } else {
        info <- res$wrap_info
        token <- info$token
      }
      attr(token, "info") <- info
      token
    },

    lookup = function(token = NULL) {
      body <- list(token = assert_scalar_character(token))
      res <- private$api_client$POST("/auth/token/lookup", body = body)
      data <- res$data
      data$policies <- list_to_character(data$policies)
      data
    },

    lookup_self = function() {
      res <- private$api_client$GET("/auth/token/lookup-self")
      data <- res$data
      data$policies <- list_to_character(data$policies)
      data
    },

    lookup_accessor = function(accessor) {
      body <- list(accessor = assert_scalar_character(accessor))
      res <- private$api_client$POST("/auth/token/lookup-accessor", body = body)
      data <- res$data
      data$policies <- list_to_character(data$policies)
      data
    },

    renew = function(token, increment = NULL) {
      body <- list(token = assert_scalar_character(token))
      if (!is.null(increment)) {
        body$increment <- assert_is_duration(increment)
      }
      res <- private$api_client$POST("/auth/token/renew", body = body)
      info <- res$auth
      info$policies <- list_to_character(info$policies)
      info
    },

    renew_self = function(increment = NULL) {
      body <- list(
        increment = increment %&&% assert_is_duration(increment))
      res <- private$api_client$POST("/auth/token/renew-self",
                                     body = drop_null(body))
      info <- res$auth
      info$policies <- list_to_character(info$policies)
      info
    },

    revoke = function(token) {
      body <- list(token = assert_scalar_character(token))
      private$api_client$POST("/auth/token/revoke", body = body)
      invisible(NULL)
    },

    revoke_self = function() {
      private$api_client$POST("/auth/token/revoke-self")
      invisible(NULL)
    },

    revoke_accessor = function(accessor) {
      body <- list(accessor = assert_scalar_character(accessor))
      private$api_client$POST("/auth/token/revoke-accessor", body = body)
      invisible(NULL)
    },

    revoke_and_orphan = function(token) {
      body <- list(token = assert_scalar_character(token))
      private$api_client$POST("/auth/token/revoke-orphan", body = body)
      invisible(NULL)
    },

    role_read = function(role_name) {
      path <- sprintf("/auth/token/roles/%s",
                      assert_scalar_character(role_name))
      data <- private$api_client$GET(path)$data
      data$allowed_policies <- list_to_character(data$allowed_policies)
      data$disallowed_policies <- list_to_character(data$disallowed_policies)
      data
    },

    role_list = function() {
      dat <- tryCatch(private$api_client$LIST("/auth/token/roles"),
                      vault_invalid_path = function(e) NULL)
      list_to_character(dat$data$keys)
    },

    role_write = function(role_name, allowed_policies = NULL,
                          disallowed_policies = NULL, orphan = NULL,
                          period = NULL, renewable = NULL,
                          explicit_max_ttl = NULL, path_suffix = NULL,
                          bound_cidrs = NULL, token_type = NULL) {
      path <- sprintf("/auth/token/roles/%s",
                      assert_scalar_character(role_name))
      body <- list(
        allowed_policies =
          allowed_policies %&&% assert_character(allowed_policies),
        disallowed_policies =
          disallowed_policies %&&% assert_character(disallowed_policies),
        orphan = orphan %&&% assert_scalar_logical(orphan),
        period = period %&&% assert_duration(period),
        renewable = orphan %&&% assert_scalar_logical(orphan),
        explicit_max_ttl =
          explicit_max_ttl %&&% assert_scalar_integer(explicit_max_ttl),
        path_suffix = path_suffix %&&% assert_scalar_character(path_suffix),
        bound_cidrs = bound_cidrs %&&% assert_character(bound_cidrs),
        token_type = token_type %&&% assert_scalar_character(token_type))
      private$api_client$POST(path, body = drop_null(body))
      invisible(NULL)
    },

    role_delete = function(role_name) {
      path <- sprintf("/auth/token/roles/%s",
                      assert_scalar_character(role_name))
      private$api_client$DELETE(path)
      invisible(NULL)
    },

    tidy = function() {
      private$api_client$POST("/auth/token/tidy")
      invisible(NULL)
    },

    ## Not really a *login* as such, but this is where we centralise
    ## the variable lookup information:
    login = function(token = NULL, quiet = FALSE) {
      token <- vault_auth_vault_token(token)
      res <- private$api_client$verify_token(token, quiet = quiet)
      if (!res$success) {
        stop(paste("Token login failed with error:", res$error$message),
             call. = FALSE)
      }
      res$token
    }
  ))


vault_auth_vault_token <- function(token) {
  if (is.null(token)) {
    token <- Sys_getenv("VAULT_TOKEN", NULL)
  }
  if (is.null(token)) {
    stop("Vault token was not found: perhaps set 'VAULT_TOKEN'",
         call. = FALSE)
  }
  assert_scalar_character(token)
  token
}
