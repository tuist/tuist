defmodule TuistOpsWeb.Router do
  use TuistOpsWeb, :router

  pipeline :slack_webhook do
    plug :accepts, ["json"]
    plug TuistOpsWeb.Plugs.SlackWebhookPlug
  end

  pipeline :pomerium_authz do
    # Called by each env's kube-impersonator sidecar from inside
    # the workload cluster, over the tailnet. No Accept header
    # constraint — accept whatever the Go client sends. Network
    # boundary is the auth (tailnet-only egress); if we ever
    # expose this endpoint more broadly, add mTLS or a shared
    # secret.
    plug :accepts, ["json", "text", "*/*"]
  end

  pipeline :health do
    plug :accepts, ["json"]
  end

  pipeline :browser do
    # The operator HTML surface (reason form + audit trail). Fronted by
    # Pomerium (Google Workspace OIDC); identity comes from the verified
    # `X-Pomerium-Jwt-Assertion` (see `TuistOps.Pomerium`). The session
    # exists only to carry the CSRF token: read grants mint on POST, so
    # `protect_from_forgery` keeps a cross-site form from minting one.
    plug :accepts, ["html", "json"]
    plug :fetch_session
    plug :fetch_query_params
    plug :protect_from_forgery
    plug :put_root_layout, html: {TuistOpsWeb.Layouts, :root}
  end

  scope "/", TuistOpsWeb do
    pipe_through :browser

    get "/", AuditController, :root
    get "/audit", AuditController, :index
  end

  scope "/grants", TuistOpsWeb do
    pipe_through :browser

    get "/new", GrantController, :new
    post "/", GrantController, :create
    get "/:id/pending", GrantController, :pending
  end

  scope "/webhooks/slack", TuistOpsWeb do
    pipe_through :slack_webhook

    post "/slash", SlackController, :slash
    post "/interactive", SlackController, :interactive
  end

  scope "/api/v1", TuistOpsWeb do
    pipe_through :pomerium_authz

    # The sidecar issues a plain HTTP GET per kubectl call. Sub-
    # paths exist as an escape hatch in case we later switch to a
    # request shape where the original kubectl path lands as a
    # suffix — the controller's decision depends only on the Host
    # header and x-pomerium-claim-email, so the path is ignored.
    match :*, "/policy", PolicyController, :evaluate
    match :*, "/policy/*_path", PolicyController, :evaluate
  end

  scope "/api/v1", TuistOpsWeb do
    pipe_through :health

    get "/healthz", HealthController, :show
    get "/readyz", HealthController, :ready
  end
end
