defmodule TuistRegistryWeb.Router do
  use TuistRegistryWeb, :router

  import Oban.Web.Router

  pipeline :swift_api do
    plug :accepts, ["swift-v1-json", "swift-v1-zip", "swift-v1-api"]
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :put_root_layout, html: {ObanWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :oban_auth do
    plug TuistRegistryWeb.Plugs.ObanAuth
  end

  scope "/" do
    forward "/metrics", PromEx.Plug, prom_ex_module: TuistRegistry.PromEx
  end

  scope "/" do
    pipe_through [:browser, :oban_auth]

    oban_dashboard("/oban")
  end

  scope "/", TuistRegistryWeb do
    get "/up", UpController, :index
  end

  scope "/swift", TuistRegistryWeb.Swift do
    pipe_through [:swift_api]

    get "/", RegistryController, :availability
    head "/", RegistryController, :availability
    get "/availability", RegistryController, :availability
    head "/availability", RegistryController, :availability
    get "/identifiers", RegistryController, :identifiers
    head "/identifiers", RegistryController, :identifiers
    post "/login", RegistryController, :login
    get "/:scope/:name", RegistryController, :list_releases
    head "/:scope/:name", RegistryController, :list_releases
    get "/:scope/:name/:version", RegistryController, :show_release
    head "/:scope/:name/:version", RegistryController, :show_release
    get "/:scope/:name/:version/Package.swift", RegistryController, :show_manifest
    head "/:scope/:name/:version/Package.swift", RegistryController, :show_manifest
  end
end
