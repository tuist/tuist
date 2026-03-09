defmodule ProcessorWeb.Router do
  use Phoenix.Router, helpers: false

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/webhooks", ProcessorWeb do
    pipe_through :api

    post "/process-build", WebhookController, :process_build
  end

  get "/health", ProcessorWeb.HealthController, :check
end
