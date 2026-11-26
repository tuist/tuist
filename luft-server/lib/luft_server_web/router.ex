defmodule LuftServerWeb.Router do
  use LuftServerWeb, :router

  alias LuftServerWeb.Plugs

  pipeline :browser_auth do
    plug :fetch_session
  end

  pipeline :api do
    plug :accepts, ["json"]
    plug Plugs.RequireSameOriginWrites
    plug Plugs.Authenticate
  end

  get "/healthz", LuftServerWeb.HealthController, :show
  get "/.well-known/luft.json", LuftServerWeb.NativeAuthController, :discovery

  # The GPUI web edge's page, for /app and every client-side path under it.
  get "/app", LuftServerWeb.WebController, :app
  get "/app/*path", LuftServerWeb.WebController, :app

  scope "/oauth2", LuftServerWeb do
    pipe_through :browser_auth

    get "/authorize", NativeAuthController, :authorize
    get "/apple", NativeAuthController, :apple
    get "/google", NativeAuthController, :google
    get "/github", NativeAuthController, :github
    post "/token", NativeAuthController, :token
  end

  get "/:account/:project/previews/:id/:asset", LuftServerWeb.PreviewAssetsController, :show

  scope "/auth", LuftServerWeb do
    pipe_through :browser_auth

    get "/login", AuthController, :login
    get "/callback", AuthController, :callback
  end

  scope "/auth", LuftServerWeb do
    pipe_through [:api]

    post "/logout", AuthController, :logout
  end

  scope "/api", LuftServerWeb do
    pipe_through :api

    get "/me", MeController, :show
    put "/me/thread-live-activities/:id", NotificationsController, :update, log: false
    delete "/me/thread-live-activities/:id", NotificationsController, :delete, log: false
    put "/me/thread-live-activity-starter", NotificationsController, :update_starter, log: false

    delete "/me/thread-live-activity-starter", NotificationsController, :delete_starter,
      log: false

    get "/me/ai-subscriptions", AISubscriptionsController, :index
    # The body carries a subscription token: never log it.
    put "/me/ai-subscriptions/claude", AISubscriptionsController, :connect_claude, log: false
    post "/me/ai-subscriptions/chatgpt/login", AISubscriptionsController, :start_chatgpt_login
    post "/me/ai-subscriptions/chatgpt/login/poll", AISubscriptionsController, :poll_chatgpt_login
    delete "/me/ai-subscriptions/chatgpt/login", AISubscriptionsController, :cancel_chatgpt_login
    delete "/me/ai-subscriptions/:provider", AISubscriptionsController, :delete

    get "/organizations", OrganizationsController, :index
    post "/organizations", OrganizationsController, :create

    scope "/accounts/:account_handle/threads" do
      get "/", ThreadsController, :index, log: false
      post "/", ThreadsController, :create, log: false
      get "/repositories", ThreadsController, :repositories, log: false
      get "/models", ThreadsController, :models, log: false
      get "/:id", ThreadsController, :show, log: false
      post "/:id/messages", ThreadsController, :message, log: false
      post "/:id/reauthorize", ThreadsController, :reauthorize, log: false
      patch "/:id", ThreadsController, :update, log: false
      post "/:id/ship-preview", ThreadsController, :ship_preview, log: false
      post "/:id/ship", ThreadsController, :ship, log: false
      post "/:id/ship-reconcile", ThreadsController, :reconcile_ship, log: false
    end

    get "/me/thread-runners", ThreadRunnersController, :index, log: false
    post "/me/thread-runners", ThreadRunnersController, :create, log: false
    delete "/me/thread-runners/:id", ThreadRunnersController, :delete, log: false
    post "/thread-runner/poll", ThreadRunnerConnectionController, :poll, log: false

    post "/thread-runner/requests/:id/response", ThreadRunnerConnectionController, :respond,
      log: false

    scope "/accounts/:account_handle/lounges" do
      get "/", LoungesController, :index, log: false
      post "/", LoungesController, :create, log: false
      get "/people", LoungesController, :people, log: false
      post "/directs", LoungesController, :direct, log: false
      get "/:id", LoungesController, :show, log: false
      post "/:id/messages", LoungesController, :message, log: false
      post "/:id/read", LoungesController, :read, log: false
      post "/:id/members", LoungesController, :invite, log: false
    end

    match :*, "/*path", APIController, :forward
  end

  match :*, "/*path", LuftServerWeb.WebController, :show
end
