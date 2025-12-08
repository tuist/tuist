defmodule CacheWeb.Router do
  use CacheWeb, :router

  pipeline :api_json do
    plug :accepts, ["json"]
  end

  pipeline :project_auth do
    plug CacheWeb.Plugs.AuthPlug
  end

  pipeline :open_api do
    plug OpenApiSpex.Plug.PutApiSpec, module: CacheWeb.API.Spec
  end

  scope "/" do
    forward "/metrics", PromEx.Plug, prom_ex_module: Cache.PromEx
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
  end
end
