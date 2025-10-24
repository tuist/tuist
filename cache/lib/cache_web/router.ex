defmodule CacheWeb.Router do
  use CacheWeb, :router

  pipeline :api do
    plug :accepts, ["json"]
    plug OpenApiSpex.Plug.PutApiSpec, module: CacheWeb.ApiSpec
  end

  scope "/api/cache", CacheWeb do
    pipe_through :api

    # Key-value endpoints
    # This should be GET, but the client now expects to be able to call PUT for what are really GET requests
    put "/keyvalue/:cas_id", KeyValueController, :get_value
    put "/keyvalue", KeyValueController, :put_value

    # CAS endpoints
    get "/cas/:id", CASController, :load
    post "/cas/:id", CASController, :save
  end
end
