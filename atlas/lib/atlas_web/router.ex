defmodule AtlasWeb.Router do
  use AtlasWeb, :router

  import Oban.Web.Router
  import Phoenix.LiveDashboard.Router

  alias Atlas.MCP.Server
  alias Atlas.MCP.Transport.StreamableHTTP
  alias AtlasWeb.Plugs.AdminAuth
  alias AtlasWeb.Plugs.AllowSupportChatEmbedding
  alias AtlasWeb.Plugs.FetchCurrentUser
  alias AtlasWeb.Plugs.MCPAuth
  alias AtlasWeb.Plugs.RequireAuth
  alias Plug.Swoosh.MailboxPreview

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {AtlasWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug FetchCurrentUser
  end

  pipeline :require_auth do
    plug RequireAuth
  end

  pipeline :support_chat do
    plug AllowSupportChatEmbedding
  end

  # This script is requested cross-origin by the Tuist marketing site. It must
  # not run the browser pipeline because its request-forgery protection rejects
  # JavaScript responses to cross-origin requests.
  pipeline :support_chat_embed do
    plug :accepts, ["js"]
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :mcp do
    plug MCPAuth
  end

  scope "/", AtlasWeb do
    get "/ready", HealthController, :ready
  end

  scope "/.well-known", AtlasWeb do
    pipe_through [:api]

    get "/oauth-authorization-server", WellKnownController, :oauth_authorization_server
    get "/oauth-protected-resource", WellKnownController, :oauth_protected_resource
    get "/oauth-protected-resource/*resource_path", WellKnownController, :oauth_protected_resource
  end

  scope "/oauth2", AtlasWeb.Oauth do
    pipe_through [:browser]

    get "/authorize", AuthorizeController, :authorize
  end

  scope "/oauth2", AtlasWeb.Oauth do
    pipe_through [:api]

    post "/token", TokenController, :token
    post "/register", RegistrationController, :register
  end

  scope "/" do
    pipe_through [:mcp]

    forward "/mcp", StreamableHTTP, server: Server
  end

  scope "/api", AtlasWeb do
    pipe_through [:api]

    post "/slack/events", SlackEventsController, :handle
    post "/slack/interactions", SlackEventsController, :interactions
    post "/github/events", GitHubEventsController, :handle
    post "/inbox/emails", InboxEmailsController, :create
    post "/postal/events", PostalEventsController, :handle
    post "/email/subscriptions", GTMSubscriptionController, :create

    # Loops-compatible contact endpoint for the PostHog signup destination.
    # Loops uses PUT to upsert and POST to create; both land here.
    post "/email/contacts/update", GTMContactController, :update
    put "/email/contacts/update", GTMContactController, :update

    # Loops-compatible transactional send, used by the Tuist marketing site for
    # the newsletter confirmation email.
    post "/email/transactional", GTMTransactionalController, :create
    post "/licenses/actions/validate-key", LicenseValidationController, :create

    # Direct-to-storage document upload used by the `Local` storage backend in
    # dev and test. Production uses S3-compatible presigned URLs instead.
    put "/documents/uploads/local/:token", DocumentUploadController, :put
  end

  scope "/api", AtlasWeb do
    pipe_through [:api, :mcp]

    get "/notes", NotesController, :index
    post "/notes", NotesController, :create
    get "/notes/search", NotesController, :search
    get "/notes/:id", NotesController, :show
    patch "/notes/:id", NotesController, :update

    get "/feature-interests", FeatureInterestsController, :index
    post "/feature-interests", FeatureInterestsController, :create
    get "/feature-interests/:id", FeatureInterestsController, :show
    get "/accounts/:account_id/feature-interests", FeatureInterestsController, :list_for_account

    post "/accounts/:account_id/timeline-events/:event_id/feature-interests",
         FeatureInterestsController,
         :record_from_event

    patch "/feature-interest-accounts/:id", FeatureInterestsController, :update_account_context
  end

  scope "/", AtlasWeb do
    pipe_through [:api]

    post "/email/subscriptions/unsubscribe/:token", GTMSubscriptionController, :unsubscribe_one_click
  end

  scope "/", AtlasWeb do
    pipe_through [:browser]

    live "/login", LoginLive, :login
    post "/dev/login", AuthController, :dev_login
    get "/email/subscriptions/confirm/:token", GTMSubscriptionController, :confirm
    get "/email/subscriptions/unsubscribe/:token", GTMSubscriptionController, :unsubscribe
    get "/support/chat/verify/:token", SupportChatVerificationController, :confirm
  end

  scope "/", AtlasWeb do
    pipe_through :support_chat_embed

    get "/support/chat.js", SupportChatEmbedController, :show
  end

  scope "/", AtlasWeb do
    pipe_through [:browser, :support_chat]

    live_session :support_chat, layout: false do
      live "/support/chat", SupportChatLive, :show
    end
  end

  scope "/auth", AtlasWeb do
    pipe_through [:browser]

    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
  end

  scope "/", AtlasWeb do
    pipe_through [:browser]

    get "/contracts/templates/:template_set/:filename",
        ContractTemplateDownloadController,
        :show
  end

  scope "/", AtlasWeb do
    pipe_through [:browser, :require_auth]

    live_session :authenticated_dashboard,
      on_mount: [{AtlasWeb.LayoutLive, :default}],
      layout: {AtlasWeb.Layouts, :dashboard} do
      live "/sales", SalesLive, :index
      live "/sales/accounts", AccountsLive, :index
      live "/sales/accounts/:id", AccountLive, :show
      live "/sales/feature-interests", FeatureInterestsLive, :index
      live "/sales/feature-interests/:id", FeatureInterestsLive, :show
      live "/gtm/content", GTMLive, :content
      live "/gtm/content/:id", GTMLive, :idea
      live "/gtm/social", GTMLive, :social
      live "/gtm/social/:id", GTMLive, :social_idea
      live "/gtm/outreach", OutreachContactsLive, :index
      live "/gtm/outreach/:id", OutreachContactsLive, :show
      live "/support", SupportLive, :index
      live "/support/:id", SupportLive, :show
      live "/email", GTMEmailLive, :index
      live "/email/audiences/:id", GTMEmailLive, :audience
      live "/mcps", MCPLive, :index
      live "/memory", Admin.MemoryLive, :index
      live "/memory/:id", Admin.MemoryLive, :show
      live "/admin/memory", Admin.MemoryLive, :index
      live "/admin/memory/:id", Admin.MemoryLive, :show
      live "/sessions", SessionsLive, :index
      live "/sessions/:id", SessionLive, :show
      live "/notes", NotesLive, :index
      live "/notes/new", NotesLive, :new
      live "/notes/:id", NotesLive, :show
    end

    live_session :executive_dashboard,
      on_mount: [{AtlasWeb.LayoutLive, :executive}],
      layout: {AtlasWeb.Layouts, :dashboard} do
      live "/finance", FinanceLive, :index
      live "/finance/vendors", FinanceVendorLive, :index
      live "/documents", DocumentsLive, :index
      live "/documents/:id", DocumentLive, :show
      live "/postal", PostalLive, :index
      live "/sales/licenses", LicensesLive, :index
      live "/hardware", HardwareLive, :index
      live "/hardware/financings", FinancingsLive, :index
      live "/hardware/financings/:id", FinancingShowLive, :show
      live "/hardware/data-centers", DataCentersLive, :index
      live "/hardware/data-centers/:id", DataCenterShowLive, :show
      live "/hardware/insurance", InsuranceLive, :index
      live "/hardware/insurance/:id", InsuranceShowLive, :show
      live "/hardware/:id", HardwareShowLive, :show
    end

    live_session :admin_dashboard,
      on_mount: [{AtlasWeb.LayoutLive, :admin}],
      layout: {AtlasWeb.Layouts, :dashboard} do
      scope "/admin", Admin do
        live "/audit", AuditLive, :index
        live "/identities", IdentitiesLive, :index
        live "/users", UsersLive, :index
      end
    end

    get "/", PageController, :root
    get "/documents/:id/download", DocumentDownloadController, :show
    # Optional trailing filename so browser file viewers show a meaningful
    # name instead of "download"; bare or stale names redirect here.
    get "/documents/:id/download/:filename", DocumentDownloadController, :show
    get "/support/messages/:message_id/original", SupportMessageController, :original
    get "/support/messages/:message_id/attachments", SupportMessageController, :attachment
    get "/support/messages/:message_id/download", SupportMessageController, :download
    get "/support/messages/:message_id/download/:filename", SupportMessageController, :download
    get "/sales/licenses/:id/air-gapped", LicenseCheckoutController, :show
    get "/mcps/:server_name/authorize", MCPOAuthController, :authorize
    get "/mcps/:server_name/callback", MCPOAuthController, :callback
    get "/mcps/:server_name/operator-grant", MCPOAuthController, :operator_grant
    get "/slack/install", SlackInstallController, :new
    get "/slack/install/callback", SlackInstallController, :callback
    delete "/logout", AuthController, :delete
  end

  # Admin dashboards (Oban, LiveDashboard) - protected by basic auth
  pipeline :admin_auth do
    plug AdminAuth
  end

  scope "/admin" do
    pipe_through [:browser, :admin_auth]

    live_dashboard "/dashboard", metrics: AtlasWeb.Telemetry
    oban_dashboard("/oban")
  end

  # Enable Swoosh mailbox preview in development
  if Application.compile_env(:atlas, :dev_routes) do
    scope "/dev" do
      pipe_through :browser

      forward "/mailbox", MailboxPreview
    end
  end
end
