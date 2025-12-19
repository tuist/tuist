defmodule CacheWeb.Router do
  use CacheWeb, :router

  import Oban.Web.Router

  pipeline :api_json do
    plug :accepts, ["json"]
  end

  pipeline :project_auth do
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
    get "/cas/:id", CASController, :download
    post "/cas/:id", CASController, :save

    head "/module/:id", ModuleCacheController, :exists
    get "/module/:id", ModuleCacheController, :download

    post "/module/start", ModuleCacheController, :start_multipart
    post "/module/part", ModuleCacheController, :upload_part
    post "/module/complete", ModuleCacheController, :complete_multipart
  end
end
