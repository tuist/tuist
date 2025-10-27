defmodule CacheWeb.Router do
  use CacheWeb, :router

  pipeline :api_json do
    plug :accepts, ["json"]
  end

  scope "/", CacheWeb do
    get "/up", UpController, :index
  end

  scope "/api/cache", CacheWeb do
    pipe_through :api_json

    put "/keyvalue/:cas_id", KeyValueController, :get_value
    put "/keyvalue", KeyValueController, :put_value
  end

  scope "/api/cache", CacheWeb do
    get "/cas/:id", CASController, :load
    post "/cas/:id", CASController, :save
  end
end
