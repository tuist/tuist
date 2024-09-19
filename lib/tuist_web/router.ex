defmodule TuistWeb.Router do
  use TuistWeb, :router

  import TuistWeb.Authentication
  import TuistWeb.Authorization
  import TuistWeb.RateLimit
  import Phoenix.LiveDashboard.Router

  @include_marketing_routes Mix.env() == :dev

  pipeline :open_api do
    plug OpenApiSpex.Plug.PutApiSpec, module: TuistWeb.API.Spec
  end

  pipeline :browser_app do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TuistWeb.Layouts, :app}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug Ueberauth
    plug :fetch_current_user
  end

  pipeline :browser_marketing do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TuistWeb.Layouts, :marketing}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug Ueberauth
    plug :fetch_current_user
  end

  pipeline :non_authenticated_api do
    plug :accepts, ["json"]
  end

  pipeline :authenticated_api do
    plug :accepts, ["json"]

    plug TuistWeb.WarningsHeaderPlug
    plug TuistWeb.AuthenticationPlug, :load_authenticated_subject
    plug TuistWeb.AuthenticationPlug, {:require_authentication, response_type: :open_api}
  end

  pipeline :authenticated do
    plug TuistWeb.AuthenticationPlug, :load_authenticated_subject
  end

  pipeline :on_premise_api do
    plug TuistWeb.OnPremiseLicensePlug, :api
    plug TuistWeb.EnsureOnPremiseUsesRecentCLIVersionPlug
  end

  pipeline :analytics do
    plug TuistWeb.AnalyticsPlug, :track_page_view
  end

  # Marketing
  if @include_marketing_routes do
    scope "/" do
      pipe_through [:open_api, :browser_marketing]

      get "/", TuistWeb.MarketingController, :home
    end
  end

  scope "/" do
    pipe_through [:open_api, :browser_app]

    get "/ready", TuistWeb.PageController, :ready
    get "/api/docs", TuistWeb.APIController, :docs
  end

  scope "/api", TuistWeb.API do
    pipe_through [:open_api, :authenticated_api, :on_premise_api]

    post "/analytics", AnalyticsController, :create
    post "/runs/:run_id/start", AnalyticsController, :multipart_start

    post "/runs/:run_id/generate-url",
         AnalyticsController,
         :multipart_generate_url

    post "/runs/:run_id/complete",
         AnalyticsController,
         :multipart_complete

    put "/runs/:run_id/complete_artifacts_uploads",
        AnalyticsController,
        :complete_artifacts_uploads

    scope "/projects" do
      post "/", ProjectsController, :create
      get "/", ProjectsController, :index
      delete "/:id", ProjectsController, :delete

      scope "/:account_handle/:project_handle" do
        get "/", ProjectsController, :show
        put "/", ProjectsController, :update

        scope "/previews" do
          post "/start", PreviewsController, :multipart_start
          post "/generate-url", PreviewsController, :multipart_generate_url
          post "/complete", PreviewsController, :multipart_complete
          get "/:preview_id", PreviewsController, :download
        end

        scope "/tokens" do
          post "/", ProjectTokensController, :create
          get "/", ProjectTokensController, :index
          delete "/:id", ProjectTokensController, :delete
        end

        put "/cache/clean", CacheController, :clean
      end
    end

    get "/cache", CacheController, :download
    get "/cache/exists", CacheController, :exists
    post "/cache/multipart/start", CacheController, :multipart_start
    post "/cache/multipart/generate-url", CacheController, :multipart_generate_url
    post "/cache/multipart/complete", CacheController, :multipart_complete

    resources "/organizations", OrganizationsController,
      param: "organization_name",
      only: [:index, :create, :delete, :show, :update]

    get "/organizations/:organization_name/usage", OrganizationsController, :usage

    resources "/organizations/:organization_name/invitations", InvitationsController,
      only: [:create]

    delete "/organizations/:organization_name/invitations", InvitationsController, :delete

    delete "/organizations/:organization_name/members/:user_name",
           OrganizationsController,
           :remove_member

    put "/organizations/:organization_name/members/:user_name",
        OrganizationsController,
        :update_member
  end

  scope "/api" do
    pipe_through [:open_api, :non_authenticated_api]

    get "/spec", OpenApiSpex.Plug.RenderSpec, []
  end

  scope "/api", TuistWeb.API do
    pipe_through [:open_api, :non_authenticated_api]

    get "/auth/device_code/:device_code", AuthController, :device_code
    post "/auth/refresh_token", AuthController, :refresh_token
    post "/auth", AuthController, :authenticate
  end

  # LiveDashboard

  scope "/dev" do
    pipe_through [:browser_app, TuistWeb.SuperAdminOnlyPlug]

    live_dashboard "/dashboard", metrics: TuistWeb.Telemetry
    forward "/sent_emails", Bamboo.SentEmailViewerPlug
  end

  ## Authentication routes

  scope "/", TuistWeb do
    pipe_through [:browser_app, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{TuistWeb.Authentication, :redirect_if_user_is_authenticated}] do
      live "/users/register", UserRegistrationLive, :new
      live "/users/log_in", UserLoginLive, :new
      live "/users/reset_password", UserForgotPasswordLive, :new
      live "/users/reset_password/:token", UserResetPasswordLive, :edit
    end

    post "/users/log_in", UserSessionController, :create
  end

  scope "/", TuistWeb do
    pipe_through [:browser_app, :require_authenticated_user, :analytics]

    live_session :require_authenticated_user,
      on_mount: [{TuistWeb.Authentication, :ensure_authenticated}] do
      live "/users/settings", UserSettingsLive, :edit
      live "/users/settings/confirm_email/:token", UserSettingsLive, :confirm_email
    end
  end

  scope "/", TuistWeb do
    pipe_through [:browser_app]

    delete "/users/log_out", UserSessionController, :delete

    live_session :current_user,
      on_mount: [{TuistWeb.Authentication, :mount_current_user}] do
      live "/users/confirm/:token", UserConfirmationLive, :edit
      live "/users/confirm", UserConfirmationInstructionsLive, :new
    end
  end

  scope "/users/auth", TuistWeb do
    pipe_through :browser_app
    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
  end

  scope "/auth", TuistWeb do
    pipe_through [:browser_app, :require_authenticated_user]

    live_session :auth,
      on_mount: [{TuistWeb.Authentication, :ensure_authenticated}] do
      live "/cli/success/:device_code", CLISuccessLive, :new
      live "/invitations/:token", AcceptInvitationLive, :new
    end

    get "/cli/:device_code", AuthController, :authenticate
  end

  # Dashboard
  scope "/", TuistWeb do
    pipe_through [
      :open_api,
      :browser_app,
      :require_authenticated_user,
      :analytics,
      TuistWeb.AutoRedirectToProjectPlug
    ]

    get "/:account_handle/billing/manage", BillingController, :manage
    get "/:account_handle/:project_handle/previews/:id", PreviewController, :preview

    live_session :dashboard,
      layout: {TuistWeb.Layouts, :account},
      on_mount: [
        {TuistWeb.LayoutLive, :account},
        {TuistWeb.Authentication, :mount_current_user}
      ] do
      live "/", AccountProjectsLive
      live "/:account_handle/billing", AccountBillingLive
      live "/:account_handle/projects", AccountProjectsLive
    end
  end

  # Project routes
  scope "/:account_handle/:project_handle", TuistWeb do
    pipe_through [
      :open_api,
      :browser_app,
      :rate_limit,
      :require_authenticated_user_for_private_projects,
      :analytics,
      :require_user_can_read_project,
      TuistWeb.RedirectToRunsPlug
    ]

    live_session :project,
      layout: {TuistWeb.Layouts, :project},
      on_mount: [
        {TuistWeb.LayoutLive, :project},
        {TuistWeb.Authentication, :mount_current_user}
      ] do
      live "/", ProjectDashboardLive
      live "/runs", ProjectRunsLive
      get "/runs/:id/download", RunsController, :download
      live "/runs/:id", ProjectRunDetailLive
      live "/tests", ProjectTestsLive
      live "/tests/cases/:identifier", ProjectTestCaseDetailLive
      # Used in tuist analytics command
      live "/analytics", ProjectDashboardLive
    end
  end

  get "/download", TuistWeb.DownloadController, :download
end
