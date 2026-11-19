defmodule LuftServerWeb.Router do
  use LuftServerWeb, :router

  alias LuftServerWeb.Plugs

  pipeline :browser_auth do
    plug :fetch_session
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug Plugs.RequireSameOriginWrites
    plug Plugs.Authenticate
  end

  get "/healthz", LuftServerWeb.HealthController, :show

  scope "/auth", LuftServerWeb do
    pipe_through :browser_auth

    get "/login", AuthController, :login
    get "/callback", AuthController, :callback
  end

  scope "/auth", LuftServerWeb do
    pipe_through [:api]

    post "/logout", AuthController, :logout
  end

  scope "/api", LuftServerWeb do
    pipe_through :api

    get "/me", MeController, :show
    get "/organizations", OrganizationsController, :index
    post "/organizations", OrganizationsController, :create
  end

  # Everything else is the Luft web app; keep this route last.
  get "/*path", LuftServerWeb.WebController, :show
end
