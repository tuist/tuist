defmodule AtlasWeb.Router do
  use AtlasWeb, :router

  import Oban.Web.Router
  import Phoenix.LiveDashboard.Router

  alias Atlas.MCP.Server
  alias Atlas.MCP.Transport.StreamableHTTP
  alias AtlasWeb.Plugs.AdminAuth
  alias AtlasWeb.Plugs.AllowSupportChatEmbedding
  alias AtlasWeb.Plugs.FetchCurrentUser
  alias AtlasWeb.Plugs.InferenceAuthentication
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

  pipeline :inference do
    plug :accepts, ["json", "event-stream"]
    plug InferenceAuthentication
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

  scope "/inference/v1", AtlasWeb do
    pipe_through :inference

    get "/models", InferenceController, :models
    post "/chat/completions", InferenceController, :chat_completions
    post "/embeddings", InferenceController, :embeddings
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

  scope "/api", AtlasWeb.ErrorsAPI do
    pipe_through [:api]

    post "/:project_id/envelope/", EnvelopeController, :create
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

    live_session :public_postmortem, layout: false do
      live "/p/postmortems/:share_token", PostmortemLive.Public
    end
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
      live "/", OverviewLive, :index
      live "/commercial/sales", SalesLive, :index
      live "/commercial/sales/accounts", AccountsLive, :index
      live "/commercial/sales/accounts/:id", AccountLive, :show
      live "/commercial/sales/feature-interests", FeatureInterestsLive, :index
      live "/commercial/sales/feature-interests/:id", FeatureInterestsLive, :show
      live "/commercial/gtm/content", GTMLive, :content
      live "/commercial/gtm/content/:id", GTMLive, :idea
      live "/commercial/gtm/social", GTMLive, :social
      live "/commercial/gtm/social/:id", GTMLive, :social_idea
      live "/commercial/gtm/outreach", OutreachContactsLive, :index
      live "/commercial/gtm/outreach/:id", OutreachContactsLive, :show
      live "/commercial/support", SupportLive, :index
      live "/commercial/support/:id", SupportLive, :show
      live "/outbound/email", GTMEmailLive, :index
      live "/outbound/email/audiences/:id", GTMEmailLive, :audience
      live "/library/notes", NotesLive, :index
      live "/library/notes/new", NotesLive, :new
      live "/library/notes/:id", NotesLive, :show
      live "/engineering/projects", ProjectLive.Index, :index
      live "/engineering/projects/:id", ProjectLive.Show, :show
      live "/engineering/domains", DomainLive.Index, :index
      live "/engineering/domains/:id", DomainLive.Show, :show
      live "/engineering/errors", ErrorsLive.Index, :index
      live "/engineering/errors/:id", ErrorsLive.Show, :show
      live "/engineering/errors/:id/events/:event_id", ErrorsLive.Event, :event
      live "/engineering/postmortems", PostmortemLive.Index
      live "/engineering/postmortems/new", PostmortemLive.Form, :new
      live "/engineering/postmortems/:number", PostmortemLive.Show
      live "/engineering/postmortems/:number/edit", PostmortemLive.Form, :edit
      live "/engineering/specs", SpecLive.Index
      live "/engineering/specs/new", SpecLive.Form, :new
      live "/engineering/specs/:number", SpecLive.Show
      live "/engineering/specs/:number/edit", SpecLive.Form, :edit
      live "/engineering/pages", PagesLive.Index, :index
      live "/engineering/pages/:id", PagesLive.Show, :show
    end

    live_session :executive_dashboard,
      on_mount: [{AtlasWeb.LayoutLive, :executive}],
      layout: {AtlasWeb.Layouts, :dashboard} do
      live "/commercial/finance", FinanceLive, :index
      live "/commercial/finance/vendors", FinanceVendorLive, :index
      live "/library/documents", DocumentsLive, :index
      live "/library/documents/:id", DocumentLive, :show
      live "/outbound/postal", PostalLive, :index
      live "/commercial/sales/licenses", LicensesLive, :index
      live "/operations/hardware", HardwareLive, :index
      live "/operations/hardware/financings", FinancingsLive, :index
      live "/operations/hardware/financings/:id", FinancingShowLive, :show
      live "/operations/hardware/data-centers", DataCentersLive, :index
      live "/operations/hardware/data-centers/:id", DataCenterShowLive, :show
      live "/operations/hardware/insurance", InsuranceLive, :index
      live "/operations/hardware/insurance/:id", InsuranceShowLive, :show
      live "/operations/hardware/:id", HardwareShowLive, :show
      live "/admin/mcps", MCPLive, :index
      live "/admin/memory", Admin.MemoryLive, :index
      live "/admin/memory/:id", Admin.MemoryLive, :show
      live "/admin/sessions", SessionsLive, :index
      live "/admin/sessions/:id", SessionLive, :show
    end

    live_session :admin_dashboard,
      on_mount: [{AtlasWeb.LayoutLive, :admin}],
      layout: {AtlasWeb.Layouts, :dashboard} do
      scope "/admin", Admin do
        live "/audit", AuditLive, :index
        live "/identities", IdentitiesLive, :index
        live "/users", UsersLive, :index
        live "/inference", InferenceLive, :index
        live "/inference/profiles", InferenceLive, :index
        live "/inference/profiles/:id", InferenceProfileLive, :show
        live "/inference/providers", InferenceProvidersLive, :index
        live "/inference/tokens/:id", InferenceTokenLive, :show
      end
    end

    # Document download URLs are stable public paths (email attachments, share
    # links). Keep them at /documents/... even though the dashboard view lives
    # under /library/documents.
    get "/documents/:id/download", DocumentDownloadController, :show
    get "/documents/:id/download/:filename", DocumentDownloadController, :show
    # Support message attachment URLs are referenced from delivered emails.
    get "/support/messages/:message_id/original", SupportMessageController, :original
    get "/support/messages/:message_id/attachments", SupportMessageController, :attachment
    get "/support/messages/:message_id/download", SupportMessageController, :download
    get "/support/messages/:message_id/download/:filename", SupportMessageController, :download
    get "/commercial/sales/licenses/:id/air-gapped", LicenseCheckoutController, :show
    # MCP OAuth callback URLs are registered with external providers; do not
    # move.
    get "/mcps/:server_name/authorize", MCPOAuthController, :authorize
    get "/mcps/:server_name/callback", MCPOAuthController, :callback
    get "/mcps/:server_name/operator-grant", MCPOAuthController, :operator_grant
    get "/slack/install", SlackInstallController, :new
    get "/slack/install/callback", SlackInstallController, :callback
    delete "/logout", AuthController, :delete
  end

  # Legacy redirects — keep executives' muscle memory working after the
  # sidebar/routes reshuffle. These preserve the old top-level entries by
  # bouncing to their new group-qualified home.
  scope "/", AtlasWeb do
    pipe_through [:browser, :require_auth]

    get "/sales", LegacyRedirectController, :sales_index
    get "/sales/*rest", LegacyRedirectController, :sales
    get "/finance", LegacyRedirectController, :finance_index
    get "/finance/*rest", LegacyRedirectController, :finance
    get "/gtm/*rest", LegacyRedirectController, :gtm
    get "/support", LegacyRedirectController, :support_index
    get "/email", LegacyRedirectController, :email_index
    get "/email/audiences/:id", LegacyRedirectController, :email_audience
    get "/postal", LegacyRedirectController, :postal_index
    get "/hardware", LegacyRedirectController, :hardware_index
    get "/hardware/*rest", LegacyRedirectController, :hardware
    get "/documents", LegacyRedirectController, :documents_index
    get "/documents/:id", LegacyRedirectController, :documents_show
    get "/notes", LegacyRedirectController, :notes_index
    get "/notes/new", LegacyRedirectController, :notes_new
    get "/notes/:id", LegacyRedirectController, :notes_show
    get "/mcps", LegacyRedirectController, :mcps_index
    get "/sessions", LegacyRedirectController, :sessions_index
    get "/sessions/:id", LegacyRedirectController, :sessions_show
    get "/memory", LegacyRedirectController, :memory_index
    get "/memory/:id", LegacyRedirectController, :memory_show
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
