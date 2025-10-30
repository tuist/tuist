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
    post "/cas/:id", CASController, :save
  end

  scope "/auth", CacheWeb do
    head "/cas", CASController, :authorize
  end
end
