defmodule TuistOpsWeb.Router do
  use TuistOpsWeb, :router

  pipeline :slack_webhook do
    plug :accepts, ["json"]
    plug TuistOpsWeb.Plugs.SlackWebhookPlug
  end

  pipeline :pomerium_authz do
    # Envoy's HTTP ext_authz filter dials this endpoint with no
    # Accept header constraints — accept whatever it sends.
    # Network boundary is the auth (tailnet-only egress); if we
    # ever expose it more broadly, add mTLS or a shared secret.
    plug :accepts, ["json", "text", "*/*"]
  end

  pipeline :health do
    plug :accepts, ["json"]
  end

  scope "/webhooks/slack", TuistOpsWeb do
    pipe_through :slack_webhook

    post "/slash", SlackController, :slash
    post "/interactive", SlackController, :interactive
  end

  scope "/api/v1", TuistOpsWeb do
    pipe_through :pomerium_authz

    # Envoy ext_authz HTTP filter sends a request with the same
    # method as the original (GET for kubectl reads, POST for
    # creates, etc.) when `with_request_body` is unset, plus an
    # optional `path_prefix` that lands as a sub-path. We don't
    # care about the method or sub-path — only Host header and
    # x-pomerium-claim-email — so accept all methods under
    # /policy/*.
    match :*, "/policy", PolicyController, :evaluate
    match :*, "/policy/*_path", PolicyController, :evaluate
  end

  scope "/api/v1", TuistOpsWeb do
    pipe_through :health

    get "/healthz", HealthController, :show
  end
end
