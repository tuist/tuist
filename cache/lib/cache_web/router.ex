defmodule CacheWeb.Router do
  use CacheWeb, :router

  pipeline :api_json do
    plug :accepts, ["json"]
  end

  pipeline :project_auth do
    plug CacheWeb.Plugs.AuthPlug
  end

  scope "/" do
    forward "/metrics", PromEx.Plug, prom_ex_module: Cache.PromEx
  end

  scope "/", CacheWeb do
    get "/up", UpController, :index
  end

  scope "/api/cache", CacheWeb do
    pipe_through [:api_json, :project_auth]

    get "/keyvalue/:cas_id", KeyValueController, :get_value
    put "/keyvalue/:cas_id", KeyValueController, :get_value
    put "/keyvalue", KeyValueController, :put_value

    get "/cas/:id", CASController, :download
    post "/cas/:id", CASController, :save

    # Module cache routes matching server API paths
    get "/", ModuleCacheController, :download
    get "/exists", ModuleCacheController, :exists

    scope "/multipart" do
      post "/start", ModuleCacheController, :multipart_start
      post "/generate-url", ModuleCacheController, :multipart_generate_url
      post "/complete", ModuleCacheController, :multipart_complete
    end
  end
end
