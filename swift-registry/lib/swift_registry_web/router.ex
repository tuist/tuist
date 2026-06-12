defmodule SwiftRegistryWeb.Router do
  use SwiftRegistryWeb, :router

  import Oban.Web.Router

  pipeline :api_registry_swift do
    plug :accepts, ["swift-registry-v1-json", "swift-registry-v1-zip", "swift-registry-v1-api"]
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :put_root_layout, html: {ObanWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :oban_auth do
    plug SwiftRegistryWeb.Plugs.ObanAuth
  end

  scope "/" do
    forward "/metrics", PromEx.Plug, prom_ex_module: SwiftRegistry.PromEx
  end

  scope "/" do
    pipe_through [:browser, :oban_auth]

    oban_dashboard("/oban")
  end

  scope "/", SwiftRegistryWeb do
    get "/up", UpController, :index
  end

  scope "/", SwiftRegistryWeb do
    pipe_through [:api_registry_swift]

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
