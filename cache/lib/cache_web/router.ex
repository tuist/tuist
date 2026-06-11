defmodule CacheWeb.Router do
  use CacheWeb, :router

  import Oban.Web.Router

  pipeline :api_json do
    plug :accepts, ["json"]
  end

  pipeline :api_registry_swift do
    plug :accepts, ["swift-registry-v1-json", "swift-registry-v1-zip", "swift-registry-v1-api"]
  end

  pipeline :project_auth do
    plug CacheWeb.Plugs.ObservabilityContextPlug
    plug CacheWeb.Plugs.AuthPlug
  end

  pipeline :open_api do
    plug OpenApiSpex.Plug.PutApiSpec, module: CacheWeb.API.Spec
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :put_root_layout, html: {ObanWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :oban_auth do
    plug CacheWeb.Plugs.ObanAuth
  end

  scope "/" do
    forward "/metrics", PromEx.Plug, prom_ex_module: Cache.PromEx
  end

  scope "/" do
    pipe_through [:browser, :oban_auth]

    oban_dashboard("/oban")
  end

  scope "/", CacheWeb do
    get "/up", UpController, :index
  end

  scope "/api" do
    pipe_through [:open_api]
    get "/spec", OpenApiSpex.Plug.RenderSpec, []
  end

  scope "/api/cache", CacheWeb do
    pipe_through [:api_json, :open_api, :project_auth]

    get "/keyvalue/:cas_id", KeyValueController, :get_value
    put "/keyvalue", KeyValueController, :put_value
    get "/cas/:id", XcodeController, :download
    post "/cas/:id", XcodeController, :save

    head "/module/:id", XcodeModuleController, :exists
    get "/module/:id", XcodeModuleController, :download

    post "/module/start", XcodeModuleController, :start_multipart
    post "/module/part", XcodeModuleController, :upload_part
    post "/module/complete", XcodeModuleController, :complete_multipart

    delete "/clean", CleanController, :clean

    get "/gradle/:cache_key", GradleController, :download
    put "/gradle/:cache_key", GradleController, :save
  end

  scope "/api/registry/swift", CacheWeb do
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
