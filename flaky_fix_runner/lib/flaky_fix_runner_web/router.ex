defmodule FlakyFixRunnerWeb.Router do
  use Phoenix.Router, helpers: false

  pipeline :api do
    plug(:accepts, ["json"])
  end

  pipeline :webhook_auth do
    plug(FlakyFixRunnerWeb.Plugs.WebhookAuthPlug)
  end

  scope "/webhooks", FlakyFixRunnerWeb do
    pipe_through([:api, :webhook_auth])

    post("/fix-flaky-test", WebhookController, :fix_flaky_test)
  end

  get("/health", FlakyFixRunnerWeb.HealthController, :check)
  get("/up", FlakyFixRunnerWeb.HealthController, :check)
end
