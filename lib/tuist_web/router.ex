defmodule TuistWeb.Router do
  use TuistWeb, :router

  import TuistWeb.Authentication
  import TuistWeb.Authorization
  import TuistWeb.RateLimit
  import Phoenix.LiveDashboard.Router
  import PhoenixStorybook.Router
  import Oban.Web.Router
  import Redirect

  use ErrorTracker.Web, :router

  pipeline :open_api do
    plug OpenApiSpex.Plug.PutApiSpec, module: TuistWeb.API.Spec
  end

  pipeline :content_security_policy do
    plug :put_content_security_policy,
      img_src:
        "'self' data: https://github.com https://*.githubusercontent.com https://*.gravatar.com",
      media_src: "'self' https://*.mastodon.social https://hachyderm.io https://fosstodon.org",
      style_src:
        "'self' 'unsafe-inline' https://fonts.googleapis.com https://*.chatwoot.com https://cdn.jsdelivr.net",
      # 'unsafe-inline' is needed for Chatwoot, which doesn't support nonce:
      # https://github.com/chatwoot/chatwoot/issues/8892
      style_src_attr: "'unsafe-inline'",
      style_src_elem:
        "'self' 'unsafe-inline' https://fonts.googleapis.com https://*.chatwoot.com https://cdn.jsdelivr.net",
      # wasm-unsafe-eval is necssary for the Shiki code highlighting
      script_src: "'self' 'nonce' 'wasm-unsafe-eval'",
      script_src_elem:
        "'self' 'nonce' https://cdn.jsdelivr.net https://esm.sh https://*.chatwoot.com https://*.getkoala.com https://*.posthog.com",
      font_src: "'self' https://fonts.gstatic.com data: https://fonts.scalar.com",
      frame_src:
        "'self' https://app.chatwoot.com https://*.tuist.dev https://newassets.hcaptcha.com",
      connect_src:
        "'self' wss://*.getkoala.com https://*.getkoala.com https://*.chatwoot.com https://*.posthog.com",
      connect_src: "'self' 'nonce' https://*.posthog.com"
  end

  pipeline :browser_app do
    plug :accepts, ["html"]
    plug :disable_robot_indexing
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TuistWeb.Layouts, :app}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug Ueberauth
    plug :fetch_current_user
    plug :content_security_policy
  end

  pipeline :browser_marketing do
    plug :accepts, ["html"]
    plug :enable_robot_indexing
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TuistWeb.Marketing.Layouts, :marketing}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug Ueberauth
    plug :fetch_current_user
    plug :assign_current_path
    plug :content_security_policy
    plug TuistWeb.OnPremisePlug, :forward_marketing_to_dashboard
    plug TuistWeb.Marketing.Localization, :redirect_to_localized_route
    plug TuistWeb.Marketing.Localization, :put_locale
  end

  pipeline :browser_marketing_feed do
    plug :accepts, ["xml"]
    plug TuistWeb.OnPremisePlug, :forward_marketing_to_dashboard
  end

  pipeline :non_authenticated_api do
    plug :accepts, ["json"]
  end

  pipeline :api_registry_swift do
    plug :accepts, ["swift-registry-v1-json", "swift-registry-v1-zip", "swift-registry-v1-api"]
    plug TuistWeb.AuthenticationPlug, :load_authenticated_subject
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
    plug TuistWeb.OnPremisePlug, :api_license_validation
    plug TuistWeb.OnPremisePlug, :warn_on_outdated_cli
  end

  pipeline :analytics do
    plug TuistWeb.AnalyticsPlug, :track_page_view
  end

  pipeline :noora do
    plug :check_noora_enabled
  end

  def check_noora_enabled(conn, _opts) do
    if FunWithFlags.enabled?(:noora) do
      conn
    else
      raise TuistWeb.Errors.NotFoundError,
            "The page you are looking for doesn't exist or has been moved."
    end
  end

  defp redirect_to_noora_when_enabled(conn, _opts) do
    if FunWithFlags.enabled?(:noora) do
      conn
      |> redirect(to: "/noora#{current_path(conn)}")
      |> halt()
    else
      conn
    end
  end

  scope "/" do
    storybook_assets()
  end

  # Marketing

  scope "/" do
    pipe_through [:browser_marketing_feed]

    redirect("/rss.xml", "/blog/rss.xml", :permanent, preserve_query_string: true)

    get "/blog/rss.xml", TuistWeb.Marketing.MarketingController, :blog_rss,
      metadata: %{type: :marketing}

    get "/blog/atom.xml", TuistWeb.Marketing.MarketingController, :blog_atom,
      metadata: %{type: :marketing}

    get "/changelog/rss.xml", TuistWeb.Marketing.MarketingController, :changelog_rss,
      metadata: %{type: :marketing}

    get "/changelog/atom.xml", TuistWeb.Marketing.MarketingController, :changelog_atom,
      metadata: %{type: :marketing}

    get "/newsletter/rss.xml", TuistWeb.Marketing.MarketingController, :newsletter_rss,
      metadata: %{type: :marketing}

    get "/newsletter/atom.xml", TuistWeb.Marketing.MarketingController, :newsletter_atom,
      metadata: %{type: :marketing}

    get "/sitemap.xml", TuistWeb.Marketing.MarketingController, :sitemap,
      metadata: %{type: :marketing}
  end

  scope "/" do
    pipe_through [
      :open_api,
      :browser_marketing,
      :assign_current_path
    ]

    for locale <- ["en"] ++ TuistWeb.Marketing.Localization.additional_locales() do
      locale_path_prefix = TuistWeb.Marketing.Localization.locale_path_prefix(locale)

      private = %{locale: locale}

      live_session String.to_atom("marketing_#{locale}"),
        on_mount: TuistWeb.Marketing.Localization do
        live Path.join(locale_path_prefix, "/blog"), TuistWeb.Marketing.MarketingBlogLive,
          metadata: %{type: :marketing},
          private: private

        live Path.join(locale_path_prefix, "/changelog"),
             TuistWeb.Marketing.MarketingChangelogLive,
             metadata: %{type: :marketing},
             private: private
      end

      get locale_path_prefix, TuistWeb.Marketing.MarketingController, :home,
        metadata: %{type: :marketing},
        private: private

      get Path.join(locale_path_prefix, "/pricing"),
          TuistWeb.Marketing.MarketingController,
          :pricing,
          metadata: %{type: :marketing},
          private: private

      for %{slug: blog_post_slug} <- Tuist.Marketing.Blog.get_posts() do
        get Path.join(locale_path_prefix, blog_post_slug),
            TuistWeb.Marketing.MarketingController,
            :blog_post,
            metadata: %{type: :marketing},
            private: private
      end

      for %{slug: page_slug} <- Tuist.Marketing.Pages.get_pages() do
        get Path.join(locale_path_prefix, page_slug),
            TuistWeb.Marketing.MarketingController,
            :page,
            metadata: %{type: :marketing},
            private: private
      end

      get Path.join(locale_path_prefix, "/about"), TuistWeb.Marketing.MarketingController, :about,
        metadata: %{type: :marketing},
        private: private

      get Path.join(locale_path_prefix, "/newsletter"),
          TuistWeb.Marketing.MarketingController,
          :newsletter,
          metadata: %{type: :marketing},
          private: private

      get Path.join(locale_path_prefix, "/newsletter/issues/:issue_number"),
          TuistWeb.Marketing.MarketingController,
          :newsletter_issue,
          metadata: %{type: :marketing},
          private: private
    end
  end

  scope "/" do
    pipe_through [:open_api, :browser_app]

    get "/ready", TuistWeb.PageController, :ready
    get "/api/docs", TuistWeb.APIController, :docs
  end

  scope path: "/api",
        alias: TuistWeb.API,
        assigns: %{caching: not Tuist.Environment.test?(), cache_ttl: :timer.minutes(1)} do
    pipe_through [:open_api, :authenticated_api, :on_premise_api]

    scope "/accounts/:account_handle" do
      patch "/", AccountController, :update_account

      scope "/tokens" do
        post "/", AccountTokensController, :create
      end
    end

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

        scope "/runs" do
          get "/", RunsController, :index
          post "/", RunsController, :create
        end

        scope "/previews" do
          post "/start", PreviewsController, :multipart_start
          post "/generate-url", PreviewsController, :multipart_generate_url
          post "/complete", PreviewsController, :multipart_complete
          post "/:preview_id/icons", PreviewsController, :upload_icon
          get "/:preview_id", PreviewsController, :show
          get "/", PreviewsController, :index
        end

        scope "/tokens" do
          post "/", ProjectTokensController, :create
          get "/", ProjectTokensController, :index
          delete "/:id", ProjectTokensController, :delete
        end

        scope "/cache" do
          put "/clean", CacheController, :clean

          scope "/ac" do
            post "/", CacheController, :upload_cache_action_item
            get "/:hash", CacheController, :get_cache_action_item
          end
        end
      end
    end

    scope "/cache" do
      get "/", CacheController, :download
      get "/exists", CacheController, :exists

      scope "/multipart" do
        post "/start", CacheController, :multipart_start
        post "/generate-url", CacheController, :multipart_generate_url
        post "/complete", CacheController, :multipart_complete
      end
    end

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

  scope "/api", TuistWeb.API do
    scope "/accounts/:account_handle/registry", Registry do
      scope "/swift" do
        pipe_through [:api_registry_swift]

        get "/identifiers", SwiftController, :identifiers
        get "/:scope/:name", SwiftController, :list_releases
        get "/:scope/:name/:version", SwiftController, :show_release
        get "/:scope/:name/:version/Package.swift", SwiftController, :show_package_swift
        get "/availability", SwiftController, :availability
        post "/login", SwiftController, :login
      end
    end
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

  # Ops Routes
  pipeline :ops do
    plug TuistWeb.Authorization, [:current_user, :read, :ops]
  end

  scope "/" do
    pipe_through [:browser_app, :ops]

    live_storybook "/ops/storybook", backend_module: TuistWeb.Storybook
  end

  scope "/ops" do
    pipe_through [:browser_app, :ops]

    oban_dashboard("/oban", csp_nonce_assign_key: :csp_nonce)

    forward "/flags", FunWithFlags.UI.Router, namespace: "ops/flags"

    live_dashboard "/dashboard",
      metrics: TuistWeb.Telemetry,
      ecto_repos: [Tuist.Repo],
      ecto_psql_extras_options: [long_running_queries: [threshold: "200 milliseconds"]],
      on_mount: [
        {TuistWeb.Authentication, :ensure_authenticated},
        {TuistWeb.Authorization, [:current_user, :read, :ops]}
      ],
      additional_pages: [
        route_name: TuistWeb.OpsConfigurationLive,
        broadway: {BroadwayDashboard, pipelines: [Tuist.API.Pipeline]}
      ]

    error_tracker_dashboard("/errors",
      on_mount: [
        {TuistWeb.Authentication, :ensure_authenticated},
        {TuistWeb.Authorization, [:current_user, :read, :ops]}
      ]
    )
  end

  if Tuist.Environment.dev?() do
    scope "/ops" do
      pipe_through [:browser_app]

      forward "/sent_emails", Bamboo.SentEmailViewerPlug
    end
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
      live "/organizations/new", CreateOrganizationLive, :new
      live "/projects/new", CreateProjectLive, :new
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
      live "/device_codes/:device_code/success", DeviceCodesSuccessLive, :new
      live "/invitations/:token", AcceptInvitationLive, :new
    end

    # This route is deprecated and will be removed in future versions.
    get "/cli/:device_code", AuthController, :authenticate_cli_deprecated
    get "/device_codes/:device_code", AuthController, :authenticate_device_code
  end

  # Dashboard

  scope "/:account_handle/:project_handle/previews", TuistWeb do
    pipe_through [
      :open_api,
      :browser_app,
      :analytics
    ]

    get "/latest", PreviewController, :latest
    get "/latest/badge.svg", PreviewController, :latest_badge
    get "/:id/icon.png", PreviewController, :download_icon
  end

  scope "/:account_handle/:project_handle/previews/:id", TuistWeb do
    pipe_through [
      :open_api,
      :browser_app,
      :require_authenticated_user_for_previews,
      :analytics
    ]

    get "/manifest.plist", PreviewController, :manifest
    get "/app.ipa", PreviewController, :download_archive
    get "/qr-code.svg", PreviewController, :download_qr_code_svg
    get "/qr-code.png", PreviewController, :download_qr_code_png
    get "/download", PreviewController, :download_preview
  end

  # TODO: Remove when Noora becomes the default
  scope "/:account_handle/:project_handle/previews/:id", TuistWeb do
    pipe_through [
      :redirect_to_noora_when_enabled,
      :open_api,
      :browser_app,
      :require_authenticated_user_for_previews,
      :analytics
    ]

    live_session :preview_detail,
      on_mount: [
        {TuistWeb.Authentication, :mount_current_user},
        {TuistWeb.LayoutLive, :optional_project}
      ] do
      live "/", PreviewLive
    end
  end

  scope "/noora/:account_handle/:project_handle/previews/:id", TuistWeb do
    pipe_through [
      :check_noora_enabled,
      :open_api,
      :browser_app,
      :require_authenticated_user_for_previews,
      :analytics
    ]

    live_session :overriden_preview_detail,
      on_mount: [
        {TuistWeb.Authentication, :mount_current_user},
        {TuistWeb.LayoutLive, :optional_project}
      ] do
      live "/", NooraPreviewLive
    end
  end

  scope "/", TuistWeb do
    pipe_through [
      :open_api,
      :browser_app,
      :require_authenticated_user,
      :analytics
    ]

    get "/:account_handle/billing/manage", BillingController, :manage
    get "/:account_handle/billing/upgrade", BillingController, :upgrade

    live_session :dashboard,
      layout: {TuistWeb.Layouts, :account},
      on_mount: [
        {TuistWeb.LayoutLive, :account},
        {TuistWeb.Authentication, :mount_current_user}
      ] do
      live "/:account_handle/billing", AccountBillingLive
      live "/:account_handle/projects", AccountProjectsLive
    end
  end

  # Old project noora routes
  scope "/noora/:account_handle/:project_handle", TuistWeb do
    pipe_through [
      :check_noora_enabled,
      :open_api,
      :browser_app,
      :rate_limit,
      :require_authenticated_user_for_private_projects,
      :analytics,
      :require_user_can_read_project,
      TuistWeb.RedirectToRunsPlug
    ]

    live_session :override_noora_project,
      layout: {TuistWeb.Layouts, :project},
      on_mount: [
        {TuistWeb.LayoutLive, :project},
        {TuistWeb.Authentication, :mount_current_user}
      ] do
      live "/connect", ConnectLive
      live "/", OverviewLive
      live "/analytics", OverviewLive
      live "/previews", NooraPreviewsLive
      live "/runs/:run_id", RunDetailLive
    end
  end

  # New project noora routes
  scope "/:account_handle/:project_handle", TuistWeb do
    pipe_through [
      :check_noora_enabled,
      :open_api,
      :browser_app,
      :rate_limit,
      :require_authenticated_user_for_private_projects,
      :analytics,
      :require_user_can_read_project,
      TuistWeb.RedirectToRunsPlug
    ]

    live_session :noora_project,
      layout: {TuistWeb.Layouts, :project},
      on_mount: [
        {TuistWeb.LayoutLive, :project},
        {TuistWeb.Authentication, :mount_current_user}
      ] do
      live "/tests/test-runs", TestRunsLive
      live "/binary-cache/cache-runs", CacheRunsLive
      live "/binary-cache/generate-runs", GenerateRunsLive
    end
  end

  # Project routes
  scope "/:account_handle/:project_handle", TuistWeb do
    pipe_through [
      :redirect_to_noora_when_enabled,
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
      # Temporarily disabled due to performance issues
      # live "/tests", ProjectTestsLive
      # live "/tests/cases/:identifier", ProjectTestCaseDetailLive
      live "/previews", PreviewsLive
      # Used in tuist analytics command
      live "/analytics", ProjectDashboardLive
    end
  end

  get "/download", TuistWeb.DownloadController, :download

  def assign_current_path(conn, _params) do
    conn |> assign(:current_path, conn.request_path)
  end

  def disable_robot_indexing(conn, _params) do
    conn |> put_resp_header("x-robots-tag", "noindex, nofollow")
  end

  defp enable_robot_indexing(conn, params) do
    if Tuist.Environment.prod?() and not Tuist.Environment.on_premise?() do
      # Once we iterate on the open-graph tags of the dashboard pages for public projects
      # we should iterate on this to enable indexing for public projects
      conn |> put_resp_header("x-robots-tag", "index, follow")
    else
      conn |> disable_robot_indexing(params)
    end
  end
end
