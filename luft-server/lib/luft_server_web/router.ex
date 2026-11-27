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

  # Server-rendered marketing pages.
  get "/", LuftServerWeb.HomeController, :show

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

  get "/mcp-servers/callback", LuftServerWeb.MCPServersController, :callback, log: false

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

    for prefix <- ["/me", "/accounts/:account_handle"] do
      get prefix <> "/mcp-servers", MCPServersController, :index
      post prefix <> "/mcp-servers", MCPServersController, :create
      post prefix <> "/mcp-servers/complete", MCPServersController, :complete, log: false
      post prefix <> "/mcp-servers/:id/authorize", MCPServersController, :authorize
      delete prefix <> "/mcp-servers/:id", MCPServersController, :delete
    end

    get "/organizations", OrganizationsController, :index
    post "/organizations", OrganizationsController, :create

    get "/accounts/:account_handle/prompts", PromptsController, :index, log: false
    get "/accounts/:account_handle/prompts/:name", PromptsController, :show, log: false
    put "/accounts/:account_handle/prompts/:name", PromptsController, :update, log: false
    delete "/accounts/:account_handle/prompts/:name", PromptsController, :delete, log: false

    get "/accounts/:account_handle/collections", CollectionsController, :index, log: false

    post "/accounts/:account_handle/collections/:collection/query", CollectionsController, :query,
      log: false

    get "/accounts/:account_handle/collections/:collection/records/:record_id",
        CollectionsController,
        :show, log: false

    post "/accounts/:account_handle/methods/:method", CollectionsController, :invoke, log: false
    get "/accounts/:account_handle/behaviors", CollectionsController, :authoring, log: false

    post "/accounts/:account_handle/releases/validate", CollectionsController, :validate,
      log: false

    get "/accounts/:account_handle/releases", CollectionsController, :releases, log: false
    post "/accounts/:account_handle/releases", CollectionsController, :propose, log: false
    get "/accounts/:account_handle/releases/:hash", CollectionsController, :release, log: false

    post "/accounts/:account_handle/releases/:hash/approve", CollectionsController, :approve,
      log: false

    post "/accounts/:account_handle/releases/:hash/activate", CollectionsController, :activate,
      log: false

    post "/accounts/:account_handle/releases/:hash/merge", CollectionsController, :merge,
      log: false

    scope "/accounts/:account_handle/threads" do
      get "/", ThreadsController, :index, log: false
      post "/", ThreadsController, :create, log: false
      get "/repositories", ThreadsController, :repositories, log: false
      get "/models", ThreadsController, :models, log: false
      get "/:id", ThreadsController, :show, log: false
      get "/:id/records/:message_id", RecordsController, :show, log: false
      get "/:id/resources/:message_id", CollectionsController, :reference, log: false
      post "/:id/records/:message_id/query", RecordsController, :query, log: false
      post "/:id/records/:message_id/action", RecordsController, :execute, log: false
      post "/:id/messages", ThreadsController, :message, log: false
      post "/:id/reauthorize", ThreadsController, :reauthorize, log: false
      post "/:id/retry-workspace", ThreadsController, :retry_workspace, log: false
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
