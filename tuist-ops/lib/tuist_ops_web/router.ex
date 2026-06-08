defmodule TuistOpsWeb.Router do
  use TuistOpsWeb, :router

  pipeline :slack_webhook do
    plug :accepts, ["json"]
    plug TuistOpsWeb.Plugs.SlackWebhookPlug
  end

  pipeline :pomerium_authz do
    plug :accepts, ["json"]
    # Pomerium dials this endpoint from inside the cluster only; the
    # network boundary is the auth here. If we ever expose it more
    # broadly, add a mTLS or shared-secret check.
  end

  scope "/webhooks/slack", TuistOpsWeb do
    pipe_through :slack_webhook

    post "/slash", SlackController, :slash
    post "/interactive", SlackController, :interactive
  end

  scope "/api/v1", TuistOpsWeb do
    pipe_through :pomerium_authz

    post "/policy", PolicyController, :evaluate
  end
end
