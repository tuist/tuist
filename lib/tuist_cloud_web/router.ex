defmodule TuistCloudWeb.Router do
  use TuistCloudWeb, :router

  import TuistCloudWeb.Authentication
  import TuistCloudWeb.Authorization
  import TuistCloudWeb.RateLimit

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
    plug Ueberauth
    plug :fetch_current_user
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

  pipeline :on_premise_api do
    plug TuistCloudWeb.OnPremiseLicensePlug, :api
    plug TuistCloudWeb.EnsureOnPremiseUsesRecentCLIVersionPlug
  end

  pipeline :analytics do
    plug TuistCloudWeb.AnalyticsPlug, :track_page_view
  end

  scope "/" do
    pipe_through [:open_api, :browser]

    get "/ready", TuistCloudWeb.PageController, :ready
    get "/api-docs", OpenApiSpex.Plug.SwaggerUI, path: "/api/openapi"
  end

  scope "/api", TuistCloudWeb.API do
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

    put "/projects/:account_name/:project_name/cache/clean", CacheController, :clean
    post "/projects", ProjectsController, :create
    get "/projects/:account_name/:project_name", ProjectsController, :show
    delete "/projects/:id", ProjectsController, :delete
    get "/projects", ProjectsController, :index
  end

  scope "/api" do
    pipe_through [:open_api, :non_authenticated_api]

    get "/openapi", OpenApiSpex.Plug.RenderSpec, []
  end

  scope "/api", TuistCloudWeb.API do
    pipe_through [:open_api, :non_authenticated_api]

    get "/auth/device_code/:device_code", AuthController, :device_code
  end

  # Enable LiveDashboard and Bamboo mailbox preview in development
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
      forward "/sent_emails", Bamboo.SentEmailViewerPlug
    end
  end

  ## Authentication routes

  scope "/", TuistCloudWeb do
    pipe_through [:browser, :redirect_if_user_is_authenticated]

    live_session :redirect_if_user_is_authenticated,
      on_mount: [{TuistCloudWeb.Authentication, :redirect_if_user_is_authenticated}] do
      live "/users/register", UserRegistrationLive, :new
      live "/users/log_in", UserLoginLive, :new
      live "/users/reset_password", UserForgotPasswordLive, :new
      live "/users/reset_password/:token", UserResetPasswordLive, :edit
    end

    post "/users/log_in", UserSessionController, :create
  end

  scope "/", TuistCloudWeb do
    pipe_through [:browser, :require_authenticated_user, :analytics]

    live_session :require_authenticated_user,
      on_mount: [{TuistCloudWeb.Authentication, :ensure_authenticated}] do
      live "/users/settings", UserSettingsLive, :edit
      live "/users/settings/confirm_email/:token", UserSettingsLive, :confirm_email
    end
  end

  scope "/", TuistCloudWeb do
    pipe_through [:browser]

    delete "/users/log_out", UserSessionController, :delete

    live_session :current_user,
      on_mount: [{TuistCloudWeb.Authentication, :mount_current_user}] do
      live "/users/confirm/:token", UserConfirmationLive, :edit
      live "/users/confirm", UserConfirmationInstructionsLive, :new
    end
  end

  scope "/users/auth", TuistCloudWeb do
    pipe_through :browser
    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
  end

  scope "/auth", TuistCloudWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :auth,
      on_mount: [{TuistCloudWeb.Authentication, :ensure_authenticated}] do
      live "/cli/success/:device_code", CLISuccessLive, :new
      live "/invitations/:token", AcceptInvitationLive, :new
    end

    get "/cli/:device_code", AuthController, :authenticate
  end

  # Project routes
  scope "/", TuistCloudWeb do
    pipe_through [
      :open_api,
      :browser,
      :rate_limit,
      :require_authenticated_user_for_private_projects,
      :analytics,
      :require_user_can_read_project
    ]

    live_session :project,
      on_mount: [
        {TuistCloudWeb.App, :mount_app},
        {TuistCloudWeb.Authentication, :mount_current_user}
      ] do
      live "/:owner/:project", HomeLive
      live "/:owner/:project/runs", RunsLive
      get "/:owner/:project/runs/:id/download", RunsController, :download
      live "/:owner/:project/runs/:id", RunDetailLive
      # Used in tuist analytics command
      live "/:owner/:project/analytics", HomeLive
    end
  end

  # Authenticated routes
  scope "/", TuistCloudWeb do
    pipe_through [
      :open_api,
      :browser,
      :require_authenticated_user,
      :analytics,
      TuistCloudWeb.AutoRedirectToProjectPlug
    ]

    live_session :authenticated,
      on_mount: [
        {TuistCloudWeb.Authentication, :mount_current_user}
      ] do
      live "/", HomeLive
      get "/organizations/:account_name/billing/plan", BillingController, :billing_plan
      get "/:account_name/billing", BillingController, :billing_plan
      live "/get-started", GetStartedLive
    end
  end
end
