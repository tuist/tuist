defmodule XcodeProcessorWeb.Router do
  use Phoenix.Router, helpers: false

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :webhook_auth do
    plug XcodeProcessorWeb.Plugs.WebhookAuthPlug
  end

  scope "/webhooks", XcodeProcessorWeb do
    pipe_through [:api, :webhook_auth]

    post "/process-xcresult", WebhookController, :process_xcresult
  end

  get "/health", XcodeProcessorWeb.HealthController, :check

  forward "/metrics", PromEx.Plug, prom_ex_module: XcodeProcessor.PromEx
end
