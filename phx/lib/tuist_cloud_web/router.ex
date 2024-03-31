defmodule TuistCloudWeb.Router do
  use TuistCloudWeb, :router

  pipeline :open_api do
    plug OpenApiSpex.Plug.PutApiSpec, module: TuistCloudWeb.API.Spec
  end

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TuistCloudWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :non_authenticated_api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated_api do
    plug :accepts, ["json"]

    plug TuistCloudWeb.WarningsHeaderPlug
    plug TuistCloudWeb.AuthenticationPlug, :load_authenticated_subject
    plug TuistCloudWeb.AuthenticationPlug, {:require_authentication, response_type: :open_api}
  end

  pipeline :authenticated do
    plug TuistCloudWeb.AuthenticationPlug, :load_authenticated_subject
  end

  scope "/" do
    pipe_through [:open_api, :browser]

    get "/", TuistCloudWeb.PageController, :home
    get "/ready", TuistCloudWeb.PageController, :ready
    get "/api-docs", OpenApiSpex.Plug.SwaggerUI, path: "/api/openapi"
  end

  scope "/api", TuistCloudWeb.API do
    pipe_through [:open_api, :authenticated_api]

    get "/cache", CacheController, :download
    get "/cache/exists", CacheController, :exists
    post "/cache/multipart/start", CacheController, :multipart_start
    post "/cache/multipart/generate-url", CacheController, :multipart_generate_url
    post "/cache/multipart/complete", CacheController, :multipart_complete
  end

  scope "/api" do
    pipe_through [:open_api, :non_authenticated_api]

    get "/openapi", OpenApiSpex.Plug.RenderSpec, []
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:tuist_cloud, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: TuistCloudWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  # Authenticated routes
  scope "/v2", TuistCloudWeb do
    pipe_through [:open_api, :browser, :authenticated]

    live_session :authenticated do
      live "/:owner/:project", HomeLive
    end
  end
end
