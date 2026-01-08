defmodule TuistWeb.Router do
  use TuistWeb, :router

  import Oban.Web.Router
  import Phoenix.LiveDashboard.Router
  import Redirect
  import TuistWeb.Authentication
  import TuistWeb.Authorization
  import TuistWeb.RateLimit.InMemory

  alias TuistWeb.Marketing.Localization
  alias TuistWeb.Marketing.MarketingController
  alias TuistWeb.Plugs.AppsignalAttributionPlug
  alias TuistWeb.Plugs.UeberauthHostPlug

  pipeline :open_api do
    plug OpenApiSpex.Plug.PutApiSpec, module: TuistWeb.API.Spec
  end

  pipeline :content_security_policy do
    plug :put_content_security_policy,
      frame_ancestors: "'self'",
      img_src:
        "'self' data: https://github.com https://*.githubusercontent.com https://*.gravatar.com https://*.s3.amazonaws.com",
      media_src:
        "'self' https://*.mastodon.social https://hachyderm.io https://fosstodon.org http://localhost:9095 https://t3.storage.dev",
      style_src:
        "'self' 'unsafe-inline' https://fonts.googleapis.com https://chat.cdn-plain.com https://cdn.jsdelivr.net https://rsms.me",
      style_src_attr: "'unsafe-inline'",
      style_src_elem:
        "'self' 'unsafe-inline' https://fonts.googleapis.com https://chat.cdn-plain.com https://cdn.jsdelivr.net https://rsms.me https://marketing.tuist.dev",
      # wasm-unsafe-eval is necssary for the Shiki code highlighting
      script_src: "'self' 'nonce' 'wasm-unsafe-eval'",
      script_src_elem:
        "'self' 'nonce' https://d3js.org https://cdn.jsdelivr.net https://esm.sh https://chat.cdn-plain.com https://*.posthog.com https://marketing.tuist.dev",
      font_src: "'self' https://fonts.gstatic.com data: https://fonts.scalar.com https://rsms.me",
      frame_src: "'self' https://chat.cdn-plain.com https://*.tuist.dev https://newassets.hcaptcha.com",
      connect_src: "'self' https://chat.cdn-plain.com  https://chat.uk.plain.com https://*.posthog.com"
  end

  pipeline :browser_app do
    plug :accepts, ["html"]
    plug :disable_robot_indexing
    plug :fetch_session
    plug TuistWeb.Plugs.TimezonePlug
    plug :fetch_live_flash
    plug :put_root_layout, html: {TuistWeb.Layouts, :app}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug UeberauthHostPlug
    plug :fetch_current_user
    plug AppsignalAttributionPlug
    plug :content_security_policy
  end

  pipeline :browser_app_image do
    plug :accepts, ["svg", "png"]
    plug :disable_robot_indexing
    plug :fetch_session
    plug :fetch_live_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
    plug AppsignalAttributionPlug
    plug :content_security_policy
  end

  pipeline :ueberauth do
    plug :accepts, ["html"]
    plug :disable_robot_indexing
    plug :fetch_session
    plug :fetch_live_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug UeberauthHostPlug
    plug Ueberauth
  end

  # Some endpoints must be accessible without the :protect_from_forgery plug.
  # For example, the POST request Apple makes as part of OAuth 2.0 is not compatible with the CSRF protection.
  pipeline :unprotected_browser_app do
    plug :accepts, ["html"]
    plug :disable_robot_indexing
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TuistWeb.Layouts, :app}
    plug :put_secure_browser_headers
    plug UeberauthHostPlug
    plug Ueberauth
    plug :fetch_current_user
    plug AppsignalAttributionPlug
    plug :content_security_policy
  end

  pipeline :browser_marketing do
    plug :accepts, ["html"]
    plug :enable_robot_indexing
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TuistWeb.Marketing.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug UeberauthHostPlug
    plug Ueberauth
    plug :fetch_current_user
    plug AppsignalAttributionPlug
    plug :assign_current_path
    plug :content_security_policy
    plug TuistWeb.OnPremisePlug, :forward_marketing_to_dashboard
    plug Localization, :redirect_to_localized_route
    plug Localization, :put_locale
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
    plug AppsignalAttributionPlug
    plug TuistWeb.RateLimit.Registry
  end

  pipeline :authenticated_api do
    plug :accepts, ["json", "application/octet-stream"]

    plug TuistWeb.WarningsHeaderPlug
    plug TuistWeb.AuthenticationPlug, :load_authenticated_subject
    plug TuistWeb.AuthenticationPlug, {:require_authentication, response_type: :open_api}
    plug AppsignalAttributionPlug
  end

  pipeline :authenticated do
    plug TuistWeb.AuthenticationPlug, :load_authenticated_subject
    plug AppsignalAttributionPlug
  end

  pipeline :on_premise_api do
    plug TuistWeb.OnPremisePlug, :api_license_validation
  end

  pipeline :analytics do
    plug TuistWeb.AnalyticsPlug, :track_page_view
  end

  # Marketing

  scope "/" do
    pipe_through [:browser_marketing_feed]

    redirect("/rss.xml", "/blog/rss.xml", :permanent, preserve_query_string: true)
    redirect("/case-studies", "/customers", :permanent, preserve_query_string: true)
    redirect("/case-studies/:slug", "/customers/:slug", :permanent, preserve_query_string: true)

    get "/blog/rss.xml", MarketingController, :blog_rss, metadata: %{type: :marketing}

    get "/blog/atom.xml", MarketingController, :blog_atom, metadata: %{type: :marketing}

    get "/changelog/rss.xml", MarketingController, :changelog_rss, metadata: %{type: :marketing}

    get "/changelog/atom.xml", MarketingController, :changelog_atom, metadata: %{type: :marketing}

    get "/sitemap.xml", MarketingController, :sitemap, metadata: %{type: :marketing}
  end

  scope "/" do
    pipe_through [
      :open_api,
      :browser_marketing,
      :assign_current_path
    ]

    for locale <- ["en"] ++ Localization.additional_locales() do
      locale_path_prefix = Localization.locale_path_prefix(locale)

      private = %{locale: locale}

      live_session String.to_atom("marketing_#{locale}"),
        on_mount: Localization do
        live Path.join(locale_path_prefix, "/blog"), TuistWeb.Marketing.MarketingBlogLive,
          metadata: %{type: :marketing},
          private: private

        live Path.join(locale_path_prefix, "/changelog"),
             TuistWeb.Marketing.MarketingChangelogLive,
             metadata: %{type: :marketing},
             private: private

        live Path.join(locale_path_prefix, "/customers"),
             TuistWeb.Marketing.MarketingCustomersLive,
             metadata: %{type: :marketing},
             private: private

        live Path.join(locale_path_prefix, "/qa"),
             TuistWeb.Marketing.MarketingQALive,
             metadata: %{type: :marketing},
             private: private
      end

      get locale_path_prefix, MarketingController, :home,
        metadata: %{type: :marketing},
        private: private

      get Path.join(locale_path_prefix, "/pricing"),
          MarketingController,
          :pricing,
          metadata: %{type: :marketing},
          private: private

      for %{slug: blog_post_slug} <- Tuist.Marketing.Blog.get_posts() do
        get Path.join(locale_path_prefix, blog_post_slug),
            MarketingController,
            :blog_post,
            metadata: %{type: :marketing},
            private: private

        # Add iframe route for each blog post
        iframe_path = Path.join([locale_path_prefix, blog_post_slug, "iframe.html"])

        get iframe_path,
            TuistWeb.Marketing.MarketingBlogIframeController,
            :show,
            metadata: %{type: :marketing},
            private: private
      end

      for %{slug: case_study_slug} <- Tuist.Marketing.Customers.get_case_studies() do
        get Path.join(locale_path_prefix, case_study_slug),
            MarketingController,
            :case_study,
            metadata: %{type: :marketing},
            private: private
      end

      for %{slug: page_slug} <- Tuist.Marketing.Pages.get_pages() do
        get Path.join(locale_path_prefix, page_slug),
            MarketingController,
            :page,
            metadata: %{type: :marketing},
            private: private
      end

      get Path.join(locale_path_prefix, "/about"), MarketingController, :about,
        metadata: %{type: :marketing},
        private: private

      get Path.join(locale_path_prefix, "/support"), MarketingController, :support,
        metadata: %{type: :marketing},
        private: private

      get Path.join(locale_path_prefix, "/newsletter"),
          MarketingController,
          :newsletter,
          metadata: %{type: :marketing},
          private: private

      post Path.join(locale_path_prefix, "/newsletter"),
           MarketingController,
           :newsletter_signup,
           metadata: %{type: :marketing},
           private: private

      get Path.join(locale_path_prefix, "/newsletter/verify"),
          MarketingController,
          :newsletter_verify,
          metadata: %{type: :marketing},
          private: private

      get Path.join(locale_path_prefix, "/newsletter/issues/:issue_number"),
          MarketingController,
          :newsletter_issue,
          metadata: %{type: :marketing},
          private: private
    end
  end

  scope "/", TuistWeb do
    pipe_through [:open_api, :browser_app]

    get "/ready", PageController, :ready
    get "/api/docs", APIController, :docs
  end

  scope "/integrations", TuistWeb do
    pipe_through [:open_api, :browser_app]

    get "/github/setup", GitHubAppSetupController, :setup
    get "/slack/callback", SlackOAuthController, :callback
  end

  scope "/.well-known", TuistWeb do
    pipe_through [:open_api, :non_authenticated_api]

    get "/openid-configuration", WellKnownController, :openid_configuration
    get "/jwks.json", WellKnownController, :jwks
    get "/apple-app-site-association", WellKnownController, :apple_app_site_association
  end

  scope path: "/api",
        alias: TuistWeb.API,
        assigns: %{caching: not Tuist.Environment.test?(), cache_ttl: to_timeout(minute: 1)} do
    pipe_through [:open_api, :authenticated_api, :on_premise_api]

    scope "/accounts/:account_handle" do
      patch "/", AccountController, :update_account
      delete "/", AccountController, :delete_account

      scope "/tokens" do
        post "/", AccountTokensController, :create
        get "/", AccountTokensController, :index
        delete "/:token_name", AccountTokensController, :delete
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

        scope "/bundles" do
          get "/", BundlesController, :index
          get "/:bundle_id", BundlesController, :show
          post "/", BundlesController, :create
        end

        scope "/runs" do
          get "/", RunsController, :index
          post "/", RunsController, :create
          post "/:run_id/start", AnalyticsController, :multipart_start_project
          post "/:run_id/generate-url", AnalyticsController, :multipart_generate_url_project
          post "/:run_id/complete", AnalyticsController, :multipart_complete_project

          put "/:run_id/complete_artifacts_uploads",
              AnalyticsController,
              :complete_artifacts_uploads_project
        end

        scope "/previews" do
          post "/start", PreviewsController, :multipart_start
          post "/generate-url", PreviewsController, :multipart_generate_url
          post "/complete", PreviewsController, :multipart_complete
          post "/:preview_id/icons", PreviewsController, :upload_icon
          get "/latest", PreviewsController, :latest
          get "/:preview_id", PreviewsController, :show
          get "/", PreviewsController, :index
          delete "/:preview_id", PreviewsController, :delete
        end

        scope "/qa" do
          post "/runs/:qa_run_id/steps", QAController, :create_step
          patch "/runs/:qa_run_id/steps/:step_id", QAController, :update_step
          patch "/runs/:qa_run_id", QAController, :update_run

          post "/runs/:qa_run_id/screenshots", QAController, :create_screenshot

          post "/runs/:qa_run_id/recordings/upload/start", QAController, :start_recording_upload

          post "/runs/:qa_run_id/recordings/upload/generate-url",
               QAController,
               :generate_recording_upload_url

          post "/runs/:qa_run_id/recordings/upload/complete",
               QAController,
               :complete_recording_upload
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
      scope "/keyvalue" do
        put "/", Cache.KeyValueController, :put_value
        get "/:cas_id", Cache.KeyValueController, :get_value
      end

      scope "/cas" do
        get "/:id", CASController, :load
        post "/:id", CASController, :save
      end

      get "/endpoints", CacheController, :endpoints
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

    resources "/organizations/:organization_name/invitations", InvitationsController, only: [:create]

    delete "/organizations/:organization_name/invitations", InvitationsController, :delete

    delete "/organizations/:organization_name/members/:user_name",
           OrganizationsController,
           :remove_member

    put "/organizations/:organization_name/members/:user_name",
        OrganizationsController,
        :update_member
  end

  scope "/api", TuistWeb.API do
    # Deprecated Swift package registry endpoints
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

    # Swift package registry endpoints
    scope "/registry/swift", Registry do
      pipe_through [:api_registry_swift]

      get "/identifiers", SwiftController, :identifiers
      get "/:scope/:name", SwiftController, :list_releases
      get "/:scope/:name/:version", SwiftController, :show_release
      get "/:scope/:name/:version/Package.swift", SwiftController, :show_package_swift
      get "/availability", SwiftController, :availability
      post "/login", SwiftController, :login
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
    post "/auth/apple", AuthController, :authenticate_apple

    get "/registry/swift", Registry.SwiftController, :availability

    post "/auth/oidc/token", OIDCController, :exchange_token
  end

  scope "/oauth2", TuistWeb.Oauth do
    pipe_through [:browser_app, :fetch_current_user]

    get "/authorize", AuthorizeController, :authorize
    get "/github", AuthorizeController, :authorize_with_github
    get "/google", AuthorizeController, :authorize_with_google
  end

  scope "/oauth2", TuistWeb.Oauth do
    pipe_through :non_authenticated_api

    post "/token", TokenController, :token
  end

  # Ops Routes
  pipeline :ops do
    plug TuistWeb.Authorization, [:current_user, :read, :ops]
    plug :assign_current_path
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
      ],
      csp_nonce_assign_key: %{
        style: :csp_nonce,
        script: :csp_nonce
      }

    live_session :ops_qa,
      layout: {TuistWeb.Layouts, :ops},
      on_mount: [
        {TuistWeb.Authentication, :ensure_authenticated},
        {TuistWeb.Authorization, [:current_user, :read, :ops]},
        {TuistWeb.LayoutLive, :ops}
      ] do
      live "/qa", TuistWeb.OpsQALive
      live "/qa/:qa_run_id/logs", TuistWeb.OpsQALogsLive
    end
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
      live "/users/log_in/okta", UserOktaLoginLive, :new
      live "/users/log_in/sso", SSOLoginLive, :new
      live "/users/reset_password", UserForgotPasswordLive, :new
      live "/users/reset_password/:token", UserResetPasswordLive, :edit
      live "/users/choose-username", ChooseUsernameLive, :new
    end

    post "/users/log_in", UserSessionController, :create
  end

  scope "/", TuistWeb do
    pipe_through [:browser_app, :require_authenticated_user, :analytics]

    live_session :require_authenticated_user,
      on_mount: [{TuistWeb.Authentication, :ensure_authenticated}] do
      get "/dashboard", DashboardController, :dashboard
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
    end
  end

  scope "/auth", TuistWeb do
    pipe_through [:browser_app]
    get "/complete-signup", AuthController, :complete_signup
  end

  scope "/users/auth", TuistWeb do
    pipe_through :browser_app
    get "/okta", AuthController, :okta_request
    get "/okta/callback", AuthController, :okta_callback
  end

  scope "/users/auth", TuistWeb do
    pipe_through :ueberauth
    get "/:provider", AuthController, :request
    get "/:provider/callback", AuthController, :callback
  end

  scope "/users/auth", TuistWeb do
    pipe_through :unprotected_browser_app
    post "/:provider/callback", AuthController, :callback
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
  end

  scope "/:account_handle/:project_handle/previews", TuistWeb do
    pipe_through [
      :open_api,
      :browser_app_image,
      :analytics
    ]

    get "/latest/badge.svg", PreviewController, :latest_badge
    get "/:id/icon.png", PreviewController, :download_icon
  end

  scope "/:account_handle/:project_handle/qa/runs/:qa_run_id/screenshots", TuistWeb do
    pipe_through [
      :open_api,
      :browser_app_image,
      :analytics
    ]

    get "/:screenshot_id", QAController, :download_screenshot
  end

  scope "/:account_handle/:project_handle/previews/:id", TuistWeb do
    pipe_through [
      :open_api,
      :browser_app,
      :analytics
    ]

    get "/manifest.plist", PreviewController, :manifest
    get "/app.ipa", PreviewController, :download_archive
  end

  scope "/:account_handle/:project_handle/previews/:id", TuistWeb do
    pipe_through [
      :open_api,
      :browser_app_image,
      :analytics
    ]

    get "/qr-code.svg", PreviewController, :download_qr_code_svg
    get "/qr-code.png", PreviewController, :download_qr_code_png
  end

  scope "/:account_handle/:project_handle/previews/:id", TuistWeb do
    pipe_through [
      :open_api,
      :browser_app,
      :require_authenticated_user_for_previews,
      :analytics
    ]

    get "/download", PreviewController, :download_preview

    live_session :preview_detail,
      layout: {TuistWeb.Layouts, :project},
      on_mount: [
        {TuistWeb.Authentication, :mount_current_user},
        {TuistWeb.LayoutLive, :optional_project}
      ] do
      live "/", PreviewLive
    end
  end

  get "/download", TuistWeb.DownloadController, :download

  scope "/:account_handle", TuistWeb do
    pipe_through [
      :open_api,
      :browser_app,
      :require_authenticated_user,
      :analytics
    ]

    get "/billing/manage", BillingController, :manage
    get "/billing/upgrade", BillingController, :upgrade

    live_session :account,
      layout: {TuistWeb.Layouts, :account},
      on_mount: [{TuistWeb.Authentication, :ensure_authenticated}, {TuistWeb.LayoutLive, :account}] do
      live "/", ProjectsLive
      live "/projects", ProjectsLive
      live "/members", MembersLive
      live "/billing", BillingLive
      live "/integrations", IntegrationsLive
      live "/settings", AccountSettingsLive
    end
  end

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
      live "/tests", TestsLive
      live "/tests/test-runs", TestRunsLive
      live "/tests/test-runs/:test_run_id", TestRunLive
      live "/tests/test-cases", TestCasesLive
      live "/tests/test-cases/:test_case_id", TestCaseLive
      live "/module-cache", ModuleCacheLive
      live "/module-cache/cache-runs", CacheRunsLive
      live "/module-cache/generate-runs", GenerateRunsLive
      live "/xcode-cache", XcodeCacheLive
      live "/connect", ConnectLive
      live "/", OverviewLive
      live "/analytics", OverviewLive
      live "/bundles", BundlesLive
      live "/bundles/:bundle_id", BundleLive
      live "/builds", BuildsLive
      live "/builds/build-runs", BuildRunsLive
      live "/builds/build-runs/:build_run_id", BuildRunLive
      live "/previews", PreviewsLive
      live "/qa", QALive
      live "/qa/:qa_run_id", QARunLive, :overview
      live "/qa/:qa_run_id/logs", QARunLive, :logs
      live "/runs/:run_id", RunDetailLive
      get "/runs/:run_id/download", RunsController, :download
      live "/settings", ProjectSettingsLive
      live "/settings/qa", QASettingsLive
    end

    # Redirects for renamed routes
    get "/binary-cache/cache-runs", RedirectPlug, to: "/module-cache/cache-runs"
    get "/binary-cache/generate-runs", RedirectPlug, to: "/module-cache/generate-runs"
  end

  def assign_current_path(conn, _params) do
    assign(conn, :current_path, conn.request_path)
  end

  def disable_robot_indexing(conn, _params) do
    put_resp_header(conn, "x-robots-tag", "noindex, nofollow")
  end

  defp enable_robot_indexing(conn, params) do
    if Tuist.Environment.prod?() and Tuist.Environment.tuist_hosted?() do
      # Once we iterate on the open-graph tags of the dashboard pages for public projects
      # we should iterate on this to enable indexing for public projects
      put_resp_header(conn, "x-robots-tag", "index, follow")
    else
      disable_robot_indexing(conn, params)
    end
  end
end
