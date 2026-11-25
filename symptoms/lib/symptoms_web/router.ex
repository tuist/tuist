defmodule SymptomsWeb.Router do
  use Phoenix.Router, helpers: false

  pipeline :health do
    plug :accepts, ["json"]
  end

  # Tailnet-only by deployment; the bearer token is the second gate.
  pipeline :api do
    plug :accepts, ["json"]
    plug SymptomsWeb.BearerAuth
  end

  scope "/", SymptomsWeb do
    pipe_through :health

    get "/healthz", HealthController, :show
  end

  scope "/api/v1/symptoms", SymptomsWeb do
    pipe_through :api

    get "/log", SymptomsController, :log
    get "/board", SymptomsController, :board
    get "/:id", SymptomsController, :show
  end
end
