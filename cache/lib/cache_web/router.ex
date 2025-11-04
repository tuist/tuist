defmodule CacheWeb.Router do
  use CacheWeb, :router

  pipeline :api_json do
    plug :accepts, ["json"]
  end

  pipeline :project_auth do
    plug CacheWeb.Plugs.AuthPlug
  end

  scope "/", CacheWeb do
    get "/up", UpController, :index
  end

  scope "/api/cache", CacheWeb do
    pipe_through [:api_json, :project_auth]

    get "/keyvalue/:cas_id", KeyValueController, :get_value
    put "/keyvalue/:cas_id", KeyValueController, :get_value
    put "/keyvalue", KeyValueController, :put_value
    post "/cas/:id", CASController, :save
  end

  scope "/auth", CacheWeb do
    pipe_through :project_auth
    get "/cas", CASController, :authorize
  end
end
