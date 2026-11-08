defmodule TuistLabelsWeb.Router do
  use Phoenix.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_root_layout, html: {TuistLabelsWeb.Layouts, :root}
  end

  scope "/" do
    pipe_through :browser
    live "/", TuistLabelsWeb.RelayLive, :relay
    live "/relay", TuistLabelsWeb.RelayLive, :relay
  end

  get "/health", TuistLabelsWeb.API, :health
  post "/api/sessions", TuistLabelsWeb.API, :create
  get "/api/sessions/:id", TuistLabelsWeb.API, :status
  post "/api/sessions/:id/jobs", TuistLabelsWeb.API, :submit
  get "/api/sessions/:id/jobs/:image", TuistLabelsWeb.API, :image
  post "/api/sessions/:id/relay", TuistLabelsWeb.API, :relay
  post "/api/sessions/:id/print", TuistLabelsWeb.API, :print
  post "/api/sessions/:id/cut", TuistLabelsWeb.API, :cut
  post "/api/sessions/:id/jobs/:jobId/claim", TuistLabelsWeb.API, :claim
  post "/api/sessions/:id/jobs/:jobId/result", TuistLabelsWeb.API, :result
end
