defmodule ProcessorWeb.Router do
  use Phoenix.Router, helpers: false

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :webhook_auth do
    plug ProcessorWeb.Plugs.WebhookAuthPlug
  end

  scope "/webhooks", ProcessorWeb do
    pipe_through [:api, :webhook_auth]

    post "/process-build", WebhookController, :process_build
  end

  get "/health", ProcessorWeb.HealthController, :check

  forward "/metrics", PromEx.Plug, prom_ex_module: Processor.PromEx
end
