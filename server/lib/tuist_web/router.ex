defmodule TuistWeb.Router do
  use TuistWeb, :router

  import Oban.Web.Router
  import Phoenix.LiveDashboard.Router
  import Redirect
  import TuistWeb.Authentication
  import TuistWeb.Authorization
  import TuistWeb.OperatorGrant
  import TuistWeb.Plugs.PublicPageHeaderPlug
  import TuistWeb.RateLimit

  alias TuistWeb.GoogleOneTap
  alias TuistWeb.LiveHooks.PublicPageChallenge
  alias TuistWeb.Marketing.Localization
  alias TuistWeb.Marketing.MarketingController
  alias TuistWeb.Plugs.AtlasRateLimitPlug
  alias TuistWeb.Plugs.LegacyRedirectsPlug
  alias TuistWeb.Plugs.LocalePlug
  alias TuistWeb.Plugs.MarkdownNegotiationPlug
  alias TuistWeb.Plugs.MCPRateLimitPlug
  alias TuistWeb.Plugs.OAuthReturnToPlug
  alias TuistWeb.Plugs.ObservabilityContextPlug
  alias TuistWeb.Plugs.PublicPageChallengePlug
  alias TuistWeb.Plugs.SameOriginCSRFExemptionPlug
  alias TuistWeb.Plugs.SentryContextPlug
  alias TuistWeb.Plugs.UeberauthHostPlug

  @public_robots_txt [train_ai: true, search: true, ai_input: true]
  @marketing_route_metadata %{type: :marketing, robots_txt: @public_robots_txt}
  @docs_route_metadata %{type: :docs, robots_txt: @public_robots_txt}
  @public_project_route_metadata %{robots_txt: false}

  pipeline :open_api do
    plug OpenApiSpex.Plug.PutApiSpec, module: TuistWeb.API.Spec
  end

  pipeline :oidc_exchange_rate_limit do
    plug :rate_limit, limit: 300
  end

  pipeline :device_authorization_rate_limit do
    plug :rate_limit, limit: 30
  end

  pipeline :open_graph_image do
    plug :put_request_kind, "open_graph_image"
    plug :rate_limit, limit: 60
    # Open Graph images belong to the marketing and docs sites, which are not served
    # on-premise. Forward these requests away there instead of spinning up a
    # headless browser render the deployment does not need.
    plug TuistWeb.OnPremisePlug, :forward_marketing_to_dashboard
  end

  pipeline :content_security_policy do
    plug :put_content_security_policy, &__MODULE__.csp_opts/1
  end

  def csp_opts(_conn) do
    s3_endpoint = Tuist.Environment.s3_endpoint()

    # Deliberately reads the env-var toggles directly rather than the
    # flag-aware wrappers. This plug feeds the
    # `:content_security_policy` pipeline, which the app, marketing, docs,
    # image and ueberauth pipelines all use, so a per-request
    # `FunWithFlags.enabled?(...)` would fire on every page load
    # site-wide for a widget only a handful of routes ever render — and
    # the underlying store `raise`s on a cold cache during a Postgres blip,
    # which would 500 pages that previously had no DB dependency here.
    # Flipping either kill switch still turns off the widget and the
    # verify path everywhere immediately; the only thing left behind is
    # a CSP source pointing at a host nothing loads from.
    turnstile_source =
      if Tuist.Environment.turnstile_required?() or
           Tuist.Environment.public_page_challenge_required?(),
         do: " https://challenges.cloudflare.com",
         else: ""

    [
      frame_ancestors: "'self'",
      img_src:
        "'self' data: https://github.com https://*.githubusercontent.com https://*.gravatar.com https://*.s3.amazonaws.com https://videos.tuist.dev https://developer.apple.com https://tuist.dev https://*.tuist.dev #{s3_endpoint}",
      media_src: "'self' https://*.mastodon.social https://hachyderm.io https://fosstodon.org #{s3_endpoint}",
      style_src: "'self' 'unsafe-inline' https://fonts.googleapis.com https://cdn.jsdelivr.net https://rsms.me",
      style_src_attr: "'unsafe-inline'",
      style_src_elem:
        "'self' 'unsafe-inline' https://fonts.googleapis.com https://cdn.jsdelivr.net https://rsms.me https://marketing.tuist.dev",
      script_src: "'self' 'nonce' 'wasm-unsafe-eval'",
      script_src_elem:
        "'self' 'nonce' https://d3js.org https://cdn.jsdelivr.net https://esm.sh https://glossia.ai https://atlas.tuist.dev https://marketing.tuist.dev#{turnstile_source}",
      font_src: "'self' https://fonts.gstatic.com data: https://fonts.scalar.com https://rsms.me",
      frame_src:
        "'self' https://atlas.tuist.dev https://*.tuist.dev https://www.youtube-nocookie.com https://newassets.hcaptcha.com#{turnstile_source}",
      connect_src: "'self' https://glossia.ai https://search.tuist.dev #{s3_endpoint}#{turnstile_source}"
    ]
  end

  # Preview pages can be embedded in iframes on other sites (a pull request
  # description, a wiki, a design tool). Framing is governed by the content
  # security policy's frame-ancestors, which :browser_app sets to 'self'; this
  # pipeline re-issues the policy with it open, so it has to run after
  # :browser_app. Session cookies are SameSite=Lax, so an embedded page renders
  # signed out: only previews the visitor could open anyway show, and nothing
  # in the frame acts with the visitor's session.
  pipeline :embeddable do
    plug :allow_embedding
  end

  def allow_embedding(conn, _opts) do
    put_content_security_policy(conn, Keyword.put(csp_opts(conn), :frame_ancestors, "*"))
  end

  def google_one_tap_content_security_policy(conn, _opts) do
    if GoogleOneTap.enabled?(conn.assigns[:current_user]) do
      sources = [
        script_src_elem: "https://accounts.google.com/gsi/client",
        style_src_elem: "https://accounts.google.com/gsi/style",
        frame_src: "https://accounts.google.com/gsi/",
        connect_src: "https://accounts.google.com/gsi/"
      ]

      policy =
        Enum.reduce(sources, csp_opts(conn), fn {directive, source}, opts ->
          Keyword.update!(opts, directive, &(&1 <> " " <> source))
        end)

      put_content_security_policy(conn, policy)
    else
      conn
    end
  end

  pipeline :browser_app do
    plug :put_request_kind, "page_load"
    plug :accepts, ["html"]
    plug :disable_robot_indexing
    plug :fetch_session
    plug :prune_operator_grants
    plug LocalePlug
    plug TuistWeb.Plugs.TimezonePlug
    plug :fetch_live_flash
    plug :put_root_layout, html: {TuistWeb.Layouts, :app}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug UeberauthHostPlug
    plug :fetch_current_user
    # Before Sentry/Observability log the query string: take a
    # `?operator_grant=` token off the redirect-back, stash it in the
    # session, and redirect to strip it from the URL.
    plug :accept_operator_grant
    plug SentryContextPlug
    plug ObservabilityContextPlug
    plug :content_security_policy
  end

  pipeline :google_one_tap do
    plug :google_one_tap_content_security_policy
  end

  # Marketing pages are stored by shared caches without Set-Cookie, so the
  # CSRF token embedded in the HTML belongs to whichever session produced the
  # cached copy and never validates for the visitors it is served to. Requests
  # posted from those pages prove same-origin through browser-set headers
  # instead. Pipe it ahead of a pipeline that plugs :protect_from_forgery, and
  # only through scopes that hold nothing but the routes meant to be exempt.
  pipeline :same_origin_csrf_exemption do
    plug SameOriginCSRFExemptionPlug
  end

  pipeline :browser_app_image do
    plug :put_request_kind, "page_image"
    plug :accepts, ["svg", "png"]
    plug :disable_robot_indexing
    plug :fetch_session
    plug :fetch_live_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
    plug SentryContextPlug
    plug ObservabilityContextPlug
    plug :content_security_policy
  end

  # Project-owned raw image (logo) endpoint. Skips `:accepts` because the URL
  # has no format suffix and Open Graph crawlers vary in the Accept headers
  # they send; the controller sets the content-type from the stored object.
  pipeline :project_asset do
    plug :put_request_kind, "project_asset"
    plug :disable_robot_indexing
    plug :fetch_session
    plug :put_secure_browser_headers
    plug SentryContextPlug
    plug ObservabilityContextPlug
    plug :content_security_policy
  end

  pipeline :ueberauth do
    plug :put_request_kind, "auth"
    plug :accepts, ["html"]
    plug :disable_robot_indexing
    plug :fetch_session
    plug :prune_operator_grants
    plug LocalePlug
    plug :fetch_live_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug UeberauthHostPlug
    plug OAuthReturnToPlug
    plug Ueberauth
  end

  # Some endpoints must be accessible without the :protect_from_forgery plug.
  # For example, the POST request Apple makes as part of OAuth 2.0 is not compatible with the CSRF protection.
  pipeline :unprotected_browser_app do
    plug :put_request_kind, "auth"
    plug :accepts, ["html"]
    plug :disable_robot_indexing
    plug :fetch_session
    plug :prune_operator_grants
    plug LocalePlug
    plug :fetch_live_flash
    plug :put_root_layout, html: {TuistWeb.Layouts, :app}
    plug :put_secure_browser_headers
    plug UeberauthHostPlug
    plug OAuthReturnToPlug
    plug Ueberauth
    plug :fetch_current_user
    plug SentryContextPlug
    plug ObservabilityContextPlug
    plug :content_security_policy
  end

  pipeline :browser_marketing_page do
    plug :put_request_kind, "marketing"
    plug MarkdownNegotiationPlug
    plug :accepts, ["html"]
  end

  # The newsletter signup form submits with `Accept: application/json`.
  pipeline :browser_marketing_form do
    plug :put_request_kind, "marketing"
    plug :accepts, ["html", "json"]
  end

  pipeline :browser_marketing do
    plug :enable_robot_indexing
    plug :mark_public_marketing_page
    plug LegacyRedirectsPlug
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TuistWeb.Marketing.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug UeberauthHostPlug
    plug Ueberauth
    plug :fetch_current_user
    plug SentryContextPlug
    plug ObservabilityContextPlug
    plug :assign_current_path
    plug :content_security_policy
    plug :google_one_tap_content_security_policy
    plug TuistWeb.OnPremisePlug, :forward_marketing_to_dashboard
    plug Localization, :negotiate_locale
    plug Localization, :put_locale
    plug TuistWeb.Marketing.Preferences
  end

  pipeline :browser_docs do
    plug :put_request_kind, "docs"
    plug MarkdownNegotiationPlug
    plug :accepts, ["html"]
    plug :enable_robot_indexing
    plug LegacyRedirectsPlug
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {TuistWeb.Docs.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :content_security_policy
    plug TuistWeb.OnPremisePlug, :forward_marketing_to_dashboard
    plug Localization, :put_locale
    plug :fetch_current_user
    plug SentryContextPlug
    plug ObservabilityContextPlug
  end

  pipeline :marketing_markdown do
    plug :put_request_kind, "marketing"
    plug :enable_robot_indexing
    plug :mark_public_marketing_page
    plug TuistWeb.OnPremisePlug, :forward_marketing_to_dashboard
  end

  pipeline :browser_marketing_feed do
    plug :put_request_kind, "marketing_feed"
    plug :accepts, ["xml"]
    # Feeds and project sitemaps skip Cloudflare's bot challenge, so the
    # public-pages rate limit has to count them through this header.
    plug :mark_public_marketing_page
    plug TuistWeb.OnPremisePlug, :forward_marketing_to_dashboard
  end

  pipeline :non_authenticated_api do
    plug :put_request_kind, "api"
    plug :accepts, ["json"]

    plug TuistWeb.WarningsHeaderPlug
  end

  pipeline :atlas_internal_api do
    plug :put_request_kind, "atlas_internal_api"
    plug :accepts, ["json"]
    plug TuistWeb.WarningsHeaderPlug
    plug AtlasRateLimitPlug
    plug TuistWeb.Plugs.InternalAtlasAuthPlug
    plug SentryContextPlug
    plug ObservabilityContextPlug
  end

  pipeline :environment_provider_api do
    plug :put_request_kind, "environment_provider_api"
    plug :accepts, ["json"]
    plug AtlasRateLimitPlug
  end

  pipeline :api_catalog do
    plug :put_request_kind, "api_catalog"
    plug :accepts, ["linkset"]
  end

  pipeline :mcp do
    plug :put_request_kind, "mcp"
    plug TuistWeb.AuthenticationPlug, :load_authenticated_subject
    plug TuistWeb.AuthenticationPlug, :load_agent_identity
    plug TuistWeb.AuthenticationPlug, {:require_authentication, response_type: :mcp}
    # Operators are not members of customer accounts, so without this an
    # operator's MCP session sees only their own projects. Runs after
    # authentication because the elevation belongs to the operator behind the
    # token.
    plug :accept_atlas_identity_header
    plug SentryContextPlug
    plug ObservabilityContextPlug
    plug MCPRateLimitPlug
  end

  # WebMCP tools the dashboard registers in the browser run as the signed-in
  # user, scoped to the account in the path, so the session cookie authenticates
  # them, CSRF protection applies, and that account's SSO enforcement applies
  # as it does on its dashboard. Bearer tokens, operator grants and Atlas
  # identities are not accepted.
  pipeline :webmcp do
    plug :put_request_kind, "webmcp"
    plug :accepts, ["json"]
    plug :fetch_session
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_user
    plug TuistWeb.AuthenticationPlug, {:require_authentication, response_type: :open_api}
    plug :require_sso_authentication_for_account_api
    plug SentryContextPlug
    plug ObservabilityContextPlug
    plug MCPRateLimitPlug
  end

  # The documentation tools every website page registers with WebMCP need no
  # identity, so no session or CSRF token is involved, and callers are rate
  # limited by address.
  pipeline :public_webmcp do
    plug :put_request_kind, "webmcp"
    plug :accepts, ["json"]
    plug MCPRateLimitPlug
  end

  # Pages that issue credentials acting for the user everywhere, which must not
  # become a way around an organization's SSO enforcement.
  pipeline :require_sso_for_credentials do
    plug :require_sso_authentication_for_credentials
  end

  pipeline :authenticated_api do
    plug :put_request_kind, "api"
    plug :accepts, ["json", "application/octet-stream"]

    plug TuistWeb.WarningsHeaderPlug
    plug TuistWeb.AuthenticationPlug, :load_authenticated_subject
    plug TuistWeb.AuthenticationPlug, {:require_authentication, response_type: :open_api}
    plug SentryContextPlug
    plug ObservabilityContextPlug
  end

  pipeline :threads_no_store do
    plug :put_threads_no_store
  end

  pipeline :report_publishing_api do
    plug :put_request_kind, "api"
    plug :accepts, ["json"]
    plug TuistWeb.WarningsHeaderPlug
    plug TuistWeb.Plugs.ReportPublishingAuthPlug
    plug SentryContextPlug
    plug ObservabilityContextPlug
  end

  pipeline :cache_endpoint_api do
    plug :put_request_kind, "api"
    plug :accepts, ["json"]
    plug TuistWeb.WarningsHeaderPlug
    plug TuistWeb.Plugs.CacheEndpointAuthPlug
    plug SentryContextPlug
    plug ObservabilityContextPlug
  end

  pipeline :ops_api do
    plug TuistWeb.Authorization, [:current_user, :read, :ops]
  end

  pipeline :scim_api do
    plug :put_request_kind, "scim"
    plug :accepts, ["scim+json", "json"]
    plug TuistWeb.Plugs.SCIMAuthPlug
    plug TuistWeb.Plugs.SCIMRateLimitPlug
    plug SentryContextPlug
    plug ObservabilityContextPlug
  end

  pipeline :authenticated do
    plug TuistWeb.AuthenticationPlug, :load_authenticated_subject
    plug SentryContextPlug
    plug ObservabilityContextPlug
  end

  pipeline :on_premise_api do
    plug TuistWeb.OnPremisePlug, :api_license_validation
  end

  pipeline :analytics do
    plug TuistWeb.AnalyticsPlug, :track_page_view
  end

  scope "/", TuistWeb do
    get "/robots.txt", RobotsTxtController, :show, metadata: %{robots_txt: false}

    get "/llms.txt", LlmsTxtController, :show, metadata: @marketing_route_metadata
    get "/llms-full.txt", LlmsTxtController, :full, metadata: @docs_route_metadata
  end

  scope "/", TuistWeb do
    pipe_through [:open_api, :open_graph_image]

    get "/open-graph-images/:key", OpenGraphImageController, :show, metadata: %{type: :marketing, robots_txt: false}
  end

  # Marketing

  scope "/", TuistWeb do
    pipe_through [:marketing_markdown]

    get "/marketing-markdown", MarketingMarkdownController, :show, metadata: @marketing_route_metadata
    get "/marketing-markdown/source/*path", MarketingMarkdownController, :source, metadata: @marketing_route_metadata
    get "/marketing-markdown/*path", MarketingMarkdownController, :show, metadata: @marketing_route_metadata
  end

  scope "/" do
    pipe_through [:browser_marketing_feed]

    redirect("/rss.xml", "/blog/rss.xml", :permanent, preserve_query_string: true)
    redirect("/case-studies", "/customers", :permanent, preserve_query_string: true)
    redirect("/case-studies/:slug", "/customers/:slug", :permanent, preserve_query_string: true)
    # The flaky-tests and test-insights pages folded into the tests page.
    redirect("/flaky-tests", "/tests", :permanent, preserve_query_string: true)
    redirect("/test-insights", "/tests", :permanent, preserve_query_string: true)

    # Keep the raw query; Redirect's preserve_query_string re-encodes decoded params.
    match(:*, "/es/build-insights", LegacyRedirectsPlug, to: "/es/docs/guides/features/build-insights")
    match(:*, "/ko/flaky-tests", LegacyRedirectsPlug, to: "/ko/tests")
    match(:*, "/zh_Hant/selective-testing", LegacyRedirectsPlug, to: "/zh_Hant/docs/guides/features/selective-testing")

    match(:*, "/blog/2025/11/27/teaching-ai-to-r", LegacyRedirectsPlug,
      to: "/blog/2025/11/27/teaching-ai-to-read-xcode-builds"
    )

    # Portuguese is retired; only map audited pages with verified English sources.
    for {old_path, new_path} <- [
          {"guides/features/projects/dependencies", "guides/features/projects/dependencies"},
          {"guides/features/projects/synthesized-files", "guides/features/projects/synthesized-files"},
          {"guides/develop/projects/adoption/migrate/swift-package",
           "guides/features/projects/adoption/migrate/swift-package"}
        ] do
      match(:*, "/pt/docs/#{old_path}", LegacyRedirectsPlug, to: "/en/docs/#{new_path}")
    end

    match(
      :*,
      "/ar/docs/references/examples/generated_app_with_build_rules",
      LegacyRedirectsPlug,
      to: "/en/docs/references/examples/generated-projects/generated_app_with_build_rules"
    )

    get "/blog/rss.xml", MarketingController, :blog_rss, metadata: @marketing_route_metadata

    get "/blog/atom.xml", MarketingController, :blog_atom, metadata: @marketing_route_metadata

    get "/changelog/rss.xml", MarketingController, :changelog_rss, metadata: @marketing_route_metadata

    get "/changelog/atom.xml", MarketingController, :changelog_atom, metadata: @marketing_route_metadata

    get "/sitemap.xml", MarketingController, :sitemap, metadata: @marketing_route_metadata
    get "/sitemap-projects.xml", TuistWeb.ProjectSitemapController, :index, metadata: %{robots_txt: false}
    get "/sitemaps/projects/:page", TuistWeb.ProjectSitemapController, :show, metadata: %{robots_txt: false}
  end

  scope "/", TuistWeb.Marketing do
    pipe_through [:non_authenticated_api]

    # Steps for the build timeline embedded in the Bazel announcement post.
    get "/blog/bazel/timeline.json", BazelShowcaseController, :timeline, metadata: %{type: :marketing, robots_txt: false}
  end

  scope "/", TuistWeb do
    pipe_through [:non_authenticated_api]

    # Build traces for agents. The token is the authorization: the MCP server
    # signs it for one build after authorizing the caller.
    get "/build-traces/:token", BuildController, :signed_trace, metadata: %{robots_txt: false}
  end

  scope "/" do
    pipe_through [
      :open_api,
      :browser_marketing_page,
      :browser_marketing,
      :assign_current_path
    ]

    for locale <- ["en"] ++ Localization.additional_locales() do
      locale_path_prefix = Localization.locale_path_prefix(locale)

      private = %{locale: locale}

      live_session String.to_atom("marketing_#{locale}"),
        on_mount: Localization do
        live Path.join(locale_path_prefix, "/blog"), TuistWeb.Marketing.MarketingBlogLive,
          metadata: @marketing_route_metadata,
          private: private

        live Path.join(locale_path_prefix, "/changelog"),
             TuistWeb.Marketing.MarketingChangelogLive,
             metadata: @marketing_route_metadata,
             private: private

        live Path.join(locale_path_prefix, "/changelog/:id"),
             TuistWeb.Marketing.MarketingChangelogEntryLive,
             metadata: @marketing_route_metadata,
             private: private

        live Path.join(locale_path_prefix, "/customers"),
             TuistWeb.Marketing.MarketingCustomersLive,
             metadata: @marketing_route_metadata,
             private: private

        live Path.join(locale_path_prefix, "/cache"),
             TuistWeb.Marketing.MarketingCacheLive,
             metadata: @marketing_route_metadata,
             private: private

        live Path.join(locale_path_prefix, "/globe"),
             TuistWeb.Marketing.MarketingGlobeLive,
             metadata: @marketing_route_metadata,
             private: private

        live Path.join(locale_path_prefix, "/previews"),
             TuistWeb.Marketing.MarketingPreviewsLive,
             metadata: @marketing_route_metadata,
             private: private

        live Path.join(locale_path_prefix, "/blog/:year/:month/:day/:slug"),
             TuistWeb.Marketing.MarketingBlogPostLive,
             metadata: @marketing_route_metadata,
             private: private
      end

      get locale_path_prefix, MarketingController, :home,
        metadata: @marketing_route_metadata,
        private: private

      get Path.join(locale_path_prefix, "/pricing"),
          MarketingController,
          :pricing,
          metadata: @marketing_route_metadata,
          private: private

      get Path.join(locale_path_prefix, "/compute"),
          MarketingController,
          :compute,
          metadata: @marketing_route_metadata,
          private: private

      get Path.join(locale_path_prefix, "/tests"),
          MarketingController,
          :tests,
          metadata: @marketing_route_metadata,
          private: private

      get Path.join(locale_path_prefix, "/blog/:year/:month/:day/:slug/iframe.html"),
          TuistWeb.Marketing.MarketingBlogIframeController,
          :show,
          metadata: @marketing_route_metadata,
          private: private

      get Path.join(locale_path_prefix, "/customers/:slug"),
          MarketingController,
          :case_study,
          metadata: @marketing_route_metadata,
          private: private

      for %{slug: page_slug} <- Tuist.Marketing.Pages.get_pages() do
        get Path.join(locale_path_prefix, page_slug),
            MarketingController,
            :page,
            metadata: @marketing_route_metadata,
            private: private
      end

      get Path.join(locale_path_prefix, "/about"), MarketingController, :about,
        metadata: @marketing_route_metadata,
        private: private

      get Path.join(locale_path_prefix, "/brand"), MarketingController, :brand,
        metadata: @marketing_route_metadata,
        private: private

      get Path.join(locale_path_prefix, "/download"), MarketingController, :download,
        metadata: @marketing_route_metadata,
        private: private

      get Path.join(locale_path_prefix, "/newsletter"),
          MarketingController,
          :newsletter,
          metadata: @marketing_route_metadata,
          private: private

      get Path.join(locale_path_prefix, "/newsletter/verify"),
          MarketingController,
          :newsletter_verify,
          metadata: @marketing_route_metadata,
          private: private

      get Path.join(locale_path_prefix, "/newsletter/issues/:issue_number"),
          MarketingController,
          :newsletter_issue,
          metadata: @marketing_route_metadata,
          private: private
    end

    # Problem, comparison, and build-system guides are authored in English only,
    # so they have no localized routes.
    for guide_path <- TuistWeb.Utilities.MarketingMarkdown.guide_page_paths() do
      get guide_path, MarketingController, :guide,
        metadata: @marketing_route_metadata,
        private: %{locale: "en"}
    end
  end

  # The newsletter forms are submitted from cached marketing pages whose
  # embedded CSRF token belongs to another session.
  scope "/" do
    pipe_through [
      :open_api,
      :same_origin_csrf_exemption,
      :browser_marketing_form,
      :browser_marketing,
      :assign_current_path
    ]

    for locale <- ["en"] ++ Localization.additional_locales() do
      post Path.join(Localization.locale_path_prefix(locale), "/newsletter"),
           MarketingController,
           :newsletter_signup,
           metadata: %{type: :marketing},
           private: %{locale: locale}
    end
  end

  scope "/" do
    pipe_through [
      :open_api,
      :same_origin_csrf_exemption,
      :browser_marketing_page,
      :browser_marketing,
      :assign_current_path
    ]

    for locale <- ["en"] ++ Localization.additional_locales() do
      post Path.join(Localization.locale_path_prefix(locale), "/newsletter/verify"),
           MarketingController,
           :newsletter_confirm,
           metadata: @marketing_route_metadata,
           private: %{locale: locale}
    end
  end

  scope "/", TuistWeb do
    pipe_through [:open_api, :browser_docs]

    get "/docs", DocsRedirectController, :show, metadata: %{type: :docs}
    get "/docs/login", UserSessionController, :new, metadata: %{type: :docs}
    get "/docs/:locale", DocsRedirectController, :show, metadata: %{type: :docs}
    get "/docs/:locale/*path", DocsRedirectController, :show, metadata: %{type: :docs}
    get "/:locale/docs-markdown/*path", DocsMarkdownController, :show, metadata: @docs_route_metadata

    for locale <- ["en"] ++ Localization.additional_locales() do
      private = %{locale: locale}

      live_session String.to_atom("docs_#{locale}"),
        on_mount: [{TuistWeb.Authentication, :mount_current_user}, Localization] do
        live "/#{locale}/docs", DocsLive, :overview, metadata: @docs_route_metadata, private: private
        live "/#{locale}/docs/*path", DocsLive, :show, metadata: @docs_route_metadata, private: private
      end
    end
  end

  scope "/", TuistWeb do
    pipe_through [:open_api, :browser_app]

    get "/ready", PageController, :ready
    get "/api/docs", APIController, :docs
    get "/agent/auth/claim/view", AgentAuthController, :claim_view
  end

  scope "/", TuistWeb do
    pipe_through [:open_api]

    get "/api/kura/rollout-status", KuraRolloutStatusController, :show
  end

  scope "/", TuistWeb do
    pipe_through [:open_api, :authenticated_api, :ops_api]

    get "/api/ops/kura/pods/:pod/metrics", OpsKuraMetricsController, :show
  end

  scope "/", TuistWeb do
    pipe_through [:open_api, :browser_app, :require_authenticated_user]

    get "/agent/identity/claim", AgentAuthController, :protocol_claim_page
    post "/agent/identity/claim/complete", AgentAuthController, :confirm_protocol_claim
  end

  scope "/", TuistWeb do
    pipe_through [:open_api]

    get "/auth.md", AgentAuthController, :auth_md
    post "/agent/auth/revoke", AgentAuthController, :revoke
    post "/agent/event/notify", AgentAuthController, :protocol_event
  end

  scope "/", TuistWeb do
    pipe_through [:open_api, :non_authenticated_api]

    post "/agent/auth", AgentAuthController, :register
    post "/agent/auth/claim", AgentAuthController, :claim
    post "/agent/auth/claim/complete", AgentAuthController, :complete_claim
    post "/agent/identity", AgentAuthController, :identity
    post "/agent/identity/claim", AgentAuthController, :protocol_claim
  end

  scope "/integrations", TuistWeb do
    pipe_through [:open_api, :browser_app, :require_authenticated_user]

    get "/entire/start", EntirePluginController, :start
    get "/entire/callback", EntirePluginController, :callback
    get "/github/setup", GitHubAppSetupController, :setup
    get "/github/authorize", GitHubAppSetupController, :authorize
    get "/installation", IntegrationInstallationController, :show
    post "/installation", IntegrationInstallationController, :create
    delete "/installation", IntegrationInstallationController, :delete
    get "/origin/start", OriginAppSetupController, :start
    get "/origin/setup", OriginAppSetupController, :setup
    # The query carries the authorization code and state; keep them out of request logs.
    get "/mcp/callback", MCPServerOAuthController, :callback, log: false
  end

  scope "/integrations", TuistWeb do
    pipe_through [:open_api, :browser_app]

    get "/github/manifest/start", GitHubAppManifestController, :start
    get "/github/manifest/callback", GitHubAppManifestController, :callback
    get "/slack/callback", SlackOAuthController, :callback
  end

  scope "/.well-known", TuistWeb do
    pipe_through [:open_api, :api_catalog]

    get "/api-catalog", WellKnownController, :api_catalog, metadata: %{robots_txt: false}
    get "/agent-skills/index.json", WellKnownController, :agent_skills_index, metadata: %{robots_txt: false}
  end

  scope "/.well-known", TuistWeb do
    pipe_through [:open_api, :non_authenticated_api]

    get "/oauth-authorization-server", WellKnownController, :oauth_authorization_server
    get "/oauth-protected-resource", WellKnownController, :oauth_protected_resource
    get "/oauth-protected-resource/*resource_path", WellKnownController, :oauth_protected_resource
    get "/jwks.json", WellKnownController, :jwks
    get "/mcp/server-card.json", WellKnownController, :mcp_server_card
    get "/registry.json", WellKnownController, :registry_discovery, metadata: %{robots_txt: false}
    get "/once", WellKnownController, :once_discovery, metadata: %{robots_txt: false}
    get "/tuist.json", WellKnownController, :tuist_discovery, metadata: %{robots_txt: false}
    get "/apple-app-site-association", WellKnownController, :apple_app_site_association
    get "/assetlinks.json", WellKnownController, :assetlinks
  end

  scope "/oidc/accounts/:account_id", TuistWeb do
    pipe_through [:open_api, :non_authenticated_api]

    get "/.well-known/openid-configuration", OIDCIssuerController, :openid_configuration, metadata: %{robots_txt: false}

    get "/jwks.json", OIDCIssuerController, :jwks, metadata: %{robots_txt: false}
  end

  scope "/.well-known", TuistWeb do
    pipe_through :open_api

    get "/openai-apps-challenge", WellKnownController, :openai_apps_challenge
  end

  scope "/" do
    pipe_through [:mcp]

    forward "/mcp", Tuist.MCP.Transport.StreamableHTTP, server: Tuist.MCP.Server
  end

  scope "/api/webmcp", TuistWeb do
    pipe_through [:public_webmcp]

    post "/public", WebMCPController, :public
  end

  scope "/api/webmcp", TuistWeb do
    pipe_through [:webmcp]

    post "/accounts/:account_handle", WebMCPController, :account
  end

  scope "/api/dashboard-search", TuistWeb do
    # The same browser-session, CSRF, SSO and requester limits as WebMCP reads.
    pipe_through [:webmcp]

    post "/:account_handle", DashboardSearchController, :search
  end

  scope "/scim/v2", TuistWeb.SCIM do
    pipe_through [:scim_api]

    get "/ServiceProviderConfig", DiscoveryController, :service_provider_config
    get "/ResourceTypes", DiscoveryController, :resource_types
    get "/Schemas", DiscoveryController, :schemas
    get "/Schemas/:id", DiscoveryController, :schema

    get "/Users", UsersController, :index
    post "/Users", UsersController, :create
    get "/Users/:id", UsersController, :show
    put "/Users/:id", UsersController, :replace
    patch "/Users/:id", UsersController, :patch
    delete "/Users/:id", UsersController, :delete

    get "/Groups", GroupsController, :index
    get "/Groups/:id", GroupsController, :show
    patch "/Groups/:id", GroupsController, :patch
  end

  scope "/api", TuistWeb.API, assigns: %{caching: not Tuist.Environment.test?(), cache_ttl: to_timeout(minute: 1)} do
    pipe_through [:open_api, :report_publishing_api, :on_premise_api]
    post "/projects/:account_handle/:project_handle/gradle/builds", GradleController, :create_build
    post "/projects/:account_handle/:project_handle/builds", BuildsController, :create
    post "/projects/:account_handle/:project_handle/xcode/builds", BuildsController, :create
    post "/projects/:account_handle/:project_handle/mix/builds", MixController, :create_build
    post "/projects/:account_handle/:project_handle/tests", TestsController, :create
    post "/projects/:account_handle/:project_handle/bazel/publishing", BazelPublishingController, :create
  end

  scope "/api", TuistWeb.API, assigns: %{auth_cache_default: true, cache_ttl: to_timeout(minute: 1)} do
    pipe_through [:open_api, :cache_endpoint_api, :on_premise_api]
    get "/cache/endpoint", CacheController, :endpoint
  end

  for collection <- [:threads, :jams] do
    scope "/api/accounts/:account_handle/#{collection}", TuistWeb.API, assigns: %{threads_collection: collection} do
      pipe_through [:threads_no_store, :open_api, :authenticated_api, :on_premise_api]

      # Phoenix's dispatch logs include request params, including private prompts.
      get "/", ThreadsController, :index, log: false
      post "/", ThreadsController, :create, log: false
      get "/repositories", ThreadsController, :repositories, log: false
      get "/models", ThreadsController, :models, log: false
      get "/:id", ThreadsController, :show, log: false
      post "/:id/messages", ThreadsController, :message, log: false
      patch "/:id", ThreadsController, :update, log: false
      post "/:id/ship-preview", ThreadsController, :ship_preview, log: false
      post "/:id/ship", ThreadsController, :ship, log: false
      post "/:id/ship-reconcile", ThreadsController, :reconcile_ship, log: false
    end
  end

  scope path: "/api",
        alias: TuistWeb.API,
        assigns: %{auth_cache_default: true, cache_ttl: to_timeout(minute: 1)} do
    pipe_through [:open_api, :authenticated_api, :on_premise_api]

    scope "/accounts/:account_handle" do
      patch "/", AccountController, :update_account
      delete "/", AccountController, :delete_account

      scope "/pulse" do
        get "/errors/issues/:issue_id/events/:event_id", PulseController, :event
        get "/errors/issues/:issue_id", PulseController, :issue
        get "/:signal/analytics", PulseController, :analytics
        get "/:signal", PulseController, :query
      end

      scope "/tokens" do
        post "/", AccountTokensController, :create
        get "/", AccountTokensController, :index
        get "/:token_id", AccountTokensController, :show
        delete "/:token_name", AccountTokensController, :delete
      end

      scope "/runners" do
        get "/jobs", RunnersController, :index_jobs
        post "/jobs", RunnersController, :create_job
        get "/jobs/:workflow_job_id", RunnersController, :show_job
        post "/jobs/:workflow_job_id/cancel", RunnersController, :cancel_job
        get "/jobs/:workflow_job_id/steps", RunnersController, :index_job_steps
        get "/jobs/:workflow_job_id/metrics", RunnersController, :index_job_metrics
        get "/jobs/:workflow_job_id/logs", RunnersController, :index_job_logs
        get "/workflows", RunnersController, :index_workflows
        get "/catalog", RunnersController, :catalog
        get "/profiles", RunnersController, :index_profiles
        post "/profiles", RunnersController, :create_profile
        patch "/profiles/:profile_name", RunnersController, :update_profile
        delete "/profiles/:profile_name", RunnersController, :delete_profile
        get "/volumes", RunnerVolumesController, :list
        get "/volumes/analytics", RunnerVolumesController, :analytics
        get "/volumes/:volume_id", RunnerVolumesController, :show
        get "/volumes/:volume_id/jobs", RunnerVolumesController, :jobs
        delete "/volumes/:volume_id", RunnerVolumesController, :delete
        post "/volumes/:volume_id/clear", RunnerVolumesController, :clear
        get "/jobs/:workflow_job_id/volumes", RunnerVolumesController, :job_volumes
      end

      scope "/webhooks" do
        get "/", WebhooksController, :index
        get "/:webhook_endpoint_id", WebhooksController, :show
        get "/:webhook_endpoint_id/delivery-attempts", WebhooksController, :index_delivery_attempts

        get "/:webhook_endpoint_id/delivery-attempts/:delivery_attempt_id",
            WebhooksController,
            :show_delivery_attempt
      end

      # The literal analytics, agent-environments and agent-sessions routes
      # must precede `/:sandbox_id`.
      scope "/sandboxes" do
        post "/amp-orbs/:orb_id", SandboxesController, :dispatch_amp_orb
        post "/agent-environments", SandboxesController, :create_agent_environment
        get "/agent-environments", SandboxesController, :index_agent_environments
        patch "/agent-environments/:agent_environment_id", SandboxesController, :update_agent_environment
        delete "/agent-environments/:agent_environment_id", SandboxesController, :delete_agent_environment
        post "/agent-sessions", AgentSessionsController, :create
        get "/agent-sessions", AgentSessionsController, :index
        get "/agent-sessions/:agent_session_id", AgentSessionsController, :show
        post "/agent-sessions/:agent_session_id/messages", AgentSessionsController, :create_message
        get "/agent-sessions/:agent_session_id/events", AgentSessionsController, :index_events
        post "/agent-sessions/:agent_session_id/archive", AgentSessionsController, :archive
        get "/analytics", SandboxesController, :analytics
        get "/", SandboxesController, :index
        post "/", SandboxesController, :create
        get "/:sandbox_id", SandboxesController, :show
        post "/:sandbox_id/exec", SandboxesController, :exec
        post "/:sandbox_id/commands", SandboxesController, :start_command
        get "/:sandbox_id/commands", SandboxesController, :index_commands
        get "/:sandbox_id/commands/:command_id", SandboxesController, :show_command
        get "/:sandbox_id/commands/:command_id/logs", SandboxesController, :stream_command_logs
        post "/:sandbox_id/commands/:command_id/stdin", SandboxesController, :write_command_stdin
        post "/:sandbox_id/commands/:command_id/cancel", SandboxesController, :cancel_command
        post "/:sandbox_id/uploads", SandboxesController, :create_upload
        post "/:sandbox_id/pause", SandboxesController, :pause
        post "/:sandbox_id/resume", SandboxesController, :resume
        post "/:sandbox_id/archive", SandboxesController, :archive
        delete "/:sandbox_id", SandboxesController, :delete
      end
    end

    post "/analytics", AnalyticsController, :create

    post "/runners/interactive/shell", RunnerInteractiveShellSessionController, :create
    get "/runners/interactive/shell/connect", RunnerInteractiveShellController, :connect
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
          get "/:bundle_id/artifacts", BundleArtifactsController, :show
          get "/:bundle_id", BundlesController, :show
          post "/", BundlesController, :create
        end

        scope "/runs" do
          get "/", RunsController, :index
          post "/", RunsController, :create
          get "/:run_id/module-cache-targets", ModuleCacheTargetsController, :index
          post "/:run_id/start", AnalyticsController, :multipart_start_project
          post "/:run_id/generate-url", AnalyticsController, :multipart_generate_url_project
          post "/:run_id/complete", AnalyticsController, :multipart_complete_project

          put "/:run_id/complete_artifacts_uploads",
              AnalyticsController,
              :complete_artifacts_uploads_project
        end

        scope "/generations" do
          get "/", GenerationsController, :index
          get "/:generation_id", GenerationsController, :show
        end

        scope "/cache-runs" do
          get "/", CacheRunsController, :index
          get "/:cache_run_id", CacheRunsController, :show
        end

        scope "/tests" do
          get "/", TestsController, :index

          scope "/metrics" do
            get "/duration", MetricsController, :test_duration
            get "/dimensions/:dimension/values", MetricsController, :test_dimension_values
          end

          scope "/test-cases" do
            get "/", TestCasesController, :index

            scope "/runs" do
              get "/", TestCaseRunsController, :index
              get "/:test_case_run_id/attachments", TestCaseRunAttachmentsController, :index
              get "/:test_case_run_id", TestCaseRunsController, :show
            end

            get "/:test_case_id", TestCasesController, :show
            patch "/:test_case_id", TestCasesController, :update
            get "/:test_case_id/events", TestCasesController, :events
            get "/:test_case_id/runs", TestCaseRunsController, :index_by_test_case
          end

          scope "/coverage" do
            get "/", CoverageController, :show
            get "/settings", CoverageController, :settings
            get "/commits/:git_commit_sha", CoverageController, :show_commit
            get "/commits/:git_commit_sha/files", CoverageController, :list_files
            get "/commits/:git_commit_sha/file", CoverageController, :show_file
            post "/uploads", CoverageController, :create_upload
            post "/commits/:git_commit_sha/complete", CoverageController, :complete_commit
          end

          scope "/selective-testing/coverage" do
            post "/baseline", SelectiveTestingCoverageController, :baseline
            post "/runs", SelectiveTestingCoverageController, :create_run
          end

          get "/:test_run_id/modules", TestModuleRunsController, :index
          get "/:test_run_id/suites", TestSuiteRunsController, :index
          get "/:test_run_id/targets", SelectiveTestingTargetsController, :index
          get "/:test_run_id", TestsController, :show
          get "/:test_run_id/test-case-runs", TestCaseRunsController, :index_by_test_run
          post "/stress-new-tests/plan", StressNewTestsController, :plan
          post "/crash-reports", CrashReportsController, :create
          post "/attachments", TestCaseRunAttachmentsController, :create

          scope "/git-history" do
            get "/settings", GitHistoryController, :settings
            post "/commits/missing", GitHistoryController, :missing_commits
            post "/commits", GitHistoryController, :upload_commits
            post "/listings/missing", GitHistoryController, :missing_listings
            post "/listings", GitHistoryController, :upload_listing
          end

          scope "/shards" do
            post "/", ShardsController, :create
            post "/upload/start", ShardsController, :start_upload
            post "/upload/generate-url", ShardsController, :generate_url
            post "/upload/complete", ShardsController, :complete
            get "/:reference/:shard_index", ShardsController, :show
          end
        end

        scope "/automations/alerts" do
          get "/", Automations.AlertsController, :index
          post "/", Automations.AlertsController, :create
          get "/:alert_id", Automations.AlertsController, :show
          get "/:alert_id/revisions", Automations.AlertsController, :index_revisions
          put "/:alert_id", Automations.AlertsController, :update
          delete "/:alert_id", Automations.AlertsController, :delete
        end

        get "/notification-alerts", ProjectNotificationAlertsController, :index

        put "/vcs-connection", ProjectVCSConnectionController, :update
        delete "/vcs-connection", ProjectVCSConnectionController, :delete

        scope "/builds" do
          get "/", BuildsController, :index

          scope "/metrics" do
            get "/health", MetricsController, :build_health
            get "/health/dimensions/:dimension/values", MetricsController, :build_health_dimension_values
            get "/duration", MetricsController, :build_duration
            get "/dimensions/:dimension/values", MetricsController, :build_dimension_values
          end

          get "/:build_id", BuildsController, :show
          post "/upload/start", BuildsController, :multipart_start
          post "/upload/generate-url", BuildsController, :multipart_generate_url
          post "/upload/complete", BuildsController, :multipart_complete

          scope "/gradle" do
            get "/:build_id/tasks", GradleTasksController, :index
          end
        end

        scope "/xcode" do
          get "/modules", XcodeModulesController, :index
          get "/modules/:module_id", XcodeModulesController, :show
          get "/modules/:module_id/events", XcodeModulesController, :history

          scope "/builds" do
            get "/", BuildsController, :index
            get "/:build_id/steps", BuildStepsController, :index
            get "/:build_id/steps/:step_id", BuildStepsController, :show
            get "/:build_id/targets", BuildTargetsController, :index
            get "/:build_id/files", BuildFilesController, :index
            get "/:build_id/issues", BuildIssuesController, :index
            get "/:build_id/cache-tasks", BuildCacheTasksController, :index
            get "/:build_id/cas-outputs", BuildCASOutputsController, :index
            get "/:build_id", BuildsController, :show
          end
        end

        scope "/gradle" do
          get "/tasks", GradleTaskDetailsController, :index
          get "/tasks/:task_id", GradleTaskDetailsController, :show
          get "/tasks/:task_id/executions", GradleTaskDetailsController, :history
          get "/builds/metrics", MetricsController, :gradle_metrics
          get "/builds/metrics/dimensions/:dimension/values", MetricsController, :gradle_dimension_values
          get "/builds", GradleController, :list_builds
          get "/builds/:build_id", GradleController, :get_build
          get "/builds/:build_id/steps", GradleBuildStepsController, :index
          get "/builds/:build_id/steps/:step_id", GradleBuildStepsController, :show
        end

        scope "/cargo" do
          get "/crates", CargoCratesController, :index
          get "/crates/:crate_id", CargoCratesController, :show
          get "/crates/:crate_id/compilations", CargoCratesController, :history
          post "/builds", CargoController, :create_build
          get "/builds", CargoController, :list_builds
          get "/builds/:build_id", CargoController, :get_build
        end

        scope "/mix" do
          get "/builds", MixController, :list_builds
          get "/builds/:build_id", MixController, :get_build
          get "/files", MixFilesController, :index
          get "/files/:file_id", MixFilesController, :show
          get "/files/:file_id/compilations", MixFilesController, :history
          get "/modules", MixModulesController, :index
          get "/modules/:module_id", MixModulesController, :show
          get "/modules/:module_id/compilations", MixModulesController, :history
        end

        scope "/once" do
          get "/runs", OnceRunsController, :index
          get "/runs/:once_run_id", OnceRunsController, :show
          get "/actions", OnceActionsController, :index
          get "/actions/:action_id", OnceActionsController, :show
          get "/actions/:action_id/executions", OnceActionsController, :history
        end

        scope "/bazel" do
          get "/actions", BazelActionsController, :index
          get "/actions/:action_id", BazelActionsController, :show
          get "/actions/:action_id/executions", BazelActionsController, :history
          get "/invocations", BazelController, :list_invocations
          get "/invocations/:invocation_id", BazelController, :get_invocation
          get "/invocations/:invocation_id/steps", BazelBuildStepsController, :index
          get "/invocations/:invocation_id/steps/:step_id", BazelBuildStepsController, :show
          get "/invocations/:invocation_id/logs", BazelController, :list_invocation_logs
          get "/invocations/:invocation_id/logs/:invocation_log_id", BazelController, :get_invocation_log
          get "/cache-events", BazelController, :list_cache_events
          get "/cache-events/:cache_event_id", BazelController, :get_cache_event
        end

        scope "/artifacts" do
          get "/", ArtifactsController, :capabilities
          get "/publications/:key", ArtifactsController, :show
          post "/publications/:key", ArtifactsController, :commit
          post "/publications/:key/content/:digest", ArtifactsController, :upload
          get "/publications/:key/content/:digest", ArtifactsController, :download
        end

        scope "/previews" do
          post "/start", PreviewsController, :multipart_start
          post "/generate-url", PreviewsController, :multipart_generate_url
          post "/complete", PreviewsController, :multipart_complete
          post "/:preview_id/icons", PreviewsController, :upload_icon
          get "/tracks", PreviewsController, :tracks
          get "/latest", PreviewsController, :latest
          get "/:preview_id", PreviewsController, :show
          get "/", PreviewsController, :index
          delete "/:preview_id", PreviewsController, :delete
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
      get "/access", CacheController, :access
      get "/endpoints", CacheController, :endpoints
      post "/token", CacheController, :token
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

    get "/me/push-devices", PushDevicesController, :index
    put "/me/push-devices/:installation_id", PushDevicesController, :update
    delete "/me/push-devices/:installation_id", PushDevicesController, :delete
    delete "/me/push-device-registrations/:registration_id", PushDevicesController, :remove
    get "/me/notification-events", NotificationRulesController, :events

    get "/me/notification-events/:event/projects/:account_handle/:project_handle/condition-options",
        NotificationRulesController,
        :condition_options

    resources "/me/notification-rules", NotificationRulesController, only: [:index, :show, :create, :delete]
    patch "/me/notification-rules/:id", NotificationRulesController, :update

    get "/me/feature-flags", FeatureFlagsController, :index
    get "/me/ai-subscriptions", AISubscriptionsController, :index
    put "/me/ai-subscriptions/claude", AISubscriptionsController, :connect_claude
    post "/me/ai-subscriptions/chatgpt/login", AISubscriptionsController, :start_chatgpt_login
    post "/me/ai-subscriptions/chatgpt/login/poll", AISubscriptionsController, :poll_chatgpt_login
    delete "/me/ai-subscriptions/chatgpt/login", AISubscriptionsController, :cancel_chatgpt_login
    delete "/me/ai-subscriptions/:provider", AISubscriptionsController, :delete
  end

  scope "/api" do
    pipe_through [:open_api, :non_authenticated_api]

    get "/spec", OpenApiSpex.Plug.RenderSpec, []
  end

  scope "/api", TuistWeb.API do
    pipe_through [:open_api, :non_authenticated_api]

    get "/metadata/limits", MetadataController, :limits
    get "/auth/device_code/:device_code", AuthController, :device_code
    post "/auth/refresh_token", AuthController, :refresh_token

    post "/auth", AuthController, :authenticate
    post "/auth/apple", AuthController, :authenticate_apple
  end

  scope "/api", TuistWeb.API do
    pipe_through [:open_api, :non_authenticated_api, :oidc_exchange_rate_limit]

    post "/auth/oidc/token", OIDCController, :exchange_token
  end

  scope "/api", TuistWeb.API do
    pipe_through [:open_api, :non_authenticated_api, :device_authorization_rate_limit]

    post "/auth/device_codes", AuthController, :create_device_code
  end

  scope "/api/remote-execution", TuistWeb do
    pipe_through [:non_authenticated_api]

    get "/:account/:project/capabilities", RemoteExecutionController, :capabilities
    post "/:account/:project/operations", RemoteExecutionController, :create
    post "/:account/:project/leases", RemoteExecutionController, :lease
    get "/:account/:project/operations/:id", RemoteExecutionController, :show
  end

  # Runner Pod dispatch + autoscaler signals endpoints.
  # Authenticated by the Pod's projected ServiceAccount token
  # (audience-scoped to `tuist-dispatch`) — the controller
  # validates it via Kubernetes `TokenReview` against the
  # workload cluster's apiserver, not via the user-auth flow.
  # Lives under `/api/internal` to make the boundary explicit:
  # these endpoints are for our own runner infrastructure, not
  # for SDK / CLI consumers.
  scope "/api/internal", TuistWeb do
    pipe_through [:non_authenticated_api]

    post "/runners/dispatch", RunnersController, :dispatch
    post "/runners/cache-volumes/authorize", RunnerCacheVolumesController, :authorize
    post "/runners/cache-volumes/checkout", RunnerCacheVolumesController, :checkout
    post "/runners/cache-volumes/docker", RunnerCacheVolumesController, :docker
    post "/runners/cache-volumes/docker-seen", RunnerCacheVolumesController, :docker_seen
    post "/runners/cache-volumes/execution", RunnerCacheVolumesController, :execution
    post "/runners/cache-volumes/report", RunnerCacheVolumesController, :report
    post "/runners/cache-volumes/image", RunnerCacheVolumesController, :image
    get "/runners/cache-volumes/masters", RunnerCacheVolumesController, :masters
    post "/runners/cache-volumes/actions-cache/lookup", RunnerCacheVolumesController, :actions_cache_lookup
    post "/runners/cache-volumes/actions-cache/enabled", RunnerCacheVolumesController, :actions_cache_enabled
    post "/runners/cache-volumes/actions-cache/reserve", RunnerCacheVolumesController, :actions_cache_reserve
    post "/runners/cache-volumes/actions-cache/upload", RunnerCacheVolumesController, :actions_cache_upload
    post "/runners/cache-volumes/actions-cache/commit", RunnerCacheVolumesController, :actions_cache_commit
    get "/runners/cache-masters", RunnerCacheMastersController, :index
    get "/runners/desired_replicas", RunnersController, :desired_replicas
    get "/runners/interactive/shell/sessions", RunnerInteractiveShellAgentController, :show
    get "/runners/interactive/shell/:session_id/tunnel", RunnerInteractiveShellAgentController, :connect
    post "/runners/pods/stopped", RunnerPodsController, :stopped
    post "/runners/pods/:pod_name/metrics", RunnerJobMetricsController, :create
    post "/runners/jobs/logs", RunnerJobReportsController, :logs
    post "/runners/jobs/finish", RunnerJobReportsController, :finish
    post "/runners/jobs/bitrise/started", RunnerBitriseReportsController, :started
    post "/runners/jobs/cache/download", RunnerJobCacheController, :download
    post "/runners/jobs/cache/uploads", RunnerJobCacheController, :start_upload
    post "/runners/jobs/cache/uploads/part", RunnerJobCacheController, :upload_part
    post "/runners/jobs/cache/uploads/complete", RunnerJobCacheController, :complete_upload
    post "/runners/jobs/cache/uploads/abort", RunnerJobCacheController, :abort_upload
    post "/amp-orbs/:orb_id", AmpOrbsController, :dispatch
    post "/claude-code-runners/spawn", ClaudeCodeRunnersController, :spawn
    get "/sandboxes/nodes/connect", SandboxNodesController, :connect
    post "/sandboxes/allocation", SandboxAllocationsController, :update
  end

  scope "/api/environment-providers/atlas/:account_handle/:environment_id", TuistWeb do
    pipe_through :environment_provider_api

    put "/", AtlasEnvironmentsController, :start, log: false
    post "/exec", AtlasEnvironmentsController, :exec, log: false
    post "/pause", AtlasEnvironmentsController, :pause, log: false
    delete "/", AtlasEnvironmentsController, :delete, log: false
  end

  scope "/api/internal", TuistWeb.Internal do
    pipe_through [:atlas_internal_api]

    get "/atlas/flags", AtlasFeatureFlagsController, :index
    get "/atlas/flags/evaluate", AtlasFeatureFlagsController, :evaluate
    get "/atlas/flags/:name", AtlasFeatureFlagsController, :show
    put "/atlas/flags/:name", AtlasFeatureFlagsController, :update

    get "/atlas/accounts/lookup", AtlasAccountsController, :lookup

    get "/atlas/accounts/:account_id/runner-concurrency-limits",
        AtlasAccountsController,
        :runner_concurrency_limits

    put "/atlas/accounts/:account_id/runner-concurrency-limits",
        AtlasAccountsController,
        :update_runner_concurrency_limits

    post "/atlas/db/query", AtlasDatabaseController, :query
    get "/atlas/db/tables", AtlasDatabaseController, :tables
    get "/atlas/db/tables/:schema/:name", AtlasDatabaseController, :describe

    post "/atlas/clickhouse/query", AtlasClickHouseController, :query
    get "/atlas/clickhouse/tables", AtlasClickHouseController, :tables
    get "/atlas/clickhouse/tables/:database/:name", AtlasClickHouseController, :describe
  end

  scope "/_internal", TuistWeb.Internal do
    pipe_through [:non_authenticated_api]

    post "/kura/activate", KuraActivationController, :create
    post "/kura/usage", KuraUsageController, :create
    get "/kura/cache-policy", KuraMeshController, :cache_policy
    post "/kura/mesh/enroll", KuraMeshController, :enroll
    post "/kura/mesh/heartbeat", KuraMeshController, :heartbeat
    get "/kura/mesh/peers", KuraMeshController, :peers
    post "/kura/mesh/registrations", KuraMeshController, :register
    post "/kura/volume-keys", KuraVolumeKeysController, :create
  end

  scope "/oauth2", TuistWeb.Oauth do
    pipe_through [:browser_app, :fetch_current_user, :require_sso_for_credentials]

    get "/authorize", AuthorizeController, :authorize
  end

  scope "/oauth2", TuistWeb.Oauth do
    pipe_through [:browser_app, :fetch_current_user]

    get "/github", AuthorizeController, :authorize_with_github
    get "/google", AuthorizeController, :authorize_with_google
    get "/apple", AuthorizeController, :authorize_with_apple
  end

  scope "/oauth2", TuistWeb.Oauth do
    pipe_through :non_authenticated_api

    post "/introspect", IntrospectController, :introspect
    post "/token", TokenController, :token
    post "/revoke", TokenController, :revoke
    post "/register", RegistrationController, :register
  end

  scope "/oauth/callback", TuistWeb.Oauth do
    pipe_through [:browser_app]

    get "/android", AndroidCallbackController, :callback
  end

  # Ops Routes
  pipeline :ops do
    plug :require_authenticated_user
    plug TuistWeb.Authorization, [:current_user, :read, :ops]
    plug :assign_current_path
    plug :skip_csrf_for_fun_with_flags_assets
  end

  scope "/ops", TuistWeb do
    pipe_through [:browser_app, :ops]

    get "/accounts/:id/stripe-customer", OpsController, :stripe_customer
  end

  scope "/ops" do
    pipe_through [:browser_app, :ops]

    oban_dashboard("/oban",
      csp_nonce_assign_key: :csp_nonce,
      on_mount: [
        {TuistWeb.Authentication, :ensure_authenticated},
        {TuistWeb.Authorization, [:current_user, :read, :ops]},
        {TuistWeb.Authentication, :revalidate_browser_session_on_info}
      ]
    )

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

    live_session :ops,
      layout: {TuistWeb.Layouts, :ops},
      on_mount: [
        {TuistWeb.Authentication, :ensure_authenticated},
        {TuistWeb.Authorization, [:current_user, :read, :ops]},
        {TuistWeb.LayoutLive, :ops}
      ] do
      live "/", TuistWeb.OpsCacheLive
      live "/kura", TuistWeb.OpsKuraLive
      live "/kura/rollouts", TuistWeb.OpsKuraRolloutsLive
      live "/kura/rollouts/:id", TuistWeb.OpsKuraRolloutLive
      live "/accounts", TuistWeb.OpsAccountsLive
      live "/accounts/:id", TuistWeb.OpsAccountLive
      live "/accounts/:id/kura/deployments/:deployment_id", TuistWeb.OpsAccountKuraDeploymentLive
      live "/accounts/:id/kura/sizing", TuistWeb.OpsAccountKuraSizingLive
      live "/accounts/:id/kura/placement", TuistWeb.OpsAccountKuraPlacementLive
      live "/registry", TuistWeb.OpsRegistryLive
      live "/registry/:scope/:name", TuistWeb.OpsRegistryPackageLive
      live "/db", TuistWeb.OpsDatabaseLive
      live "/db/tables/:schema/:name", TuistWeb.OpsDatabaseTableLive
    end
  end

  if Tuist.Environment.dev?() do
    scope "/ops" do
      pipe_through [:browser_app]

      forward "/sent_emails", Bamboo.SentEmailViewerPlug
      # Every Open Graph image on one page while the cards are redesigned.
      get "/og-gallery", TuistWeb.OpsOpenGraphGalleryController, :index
    end
  end

  ## Authentication routes

  scope "/", TuistWeb do
    pipe_through [:browser_app, :redirect_if_user_is_authenticated, :google_one_tap]

    live_session :redirect_if_user_is_authenticated,
      session: {TuistWeb.UserForgotPasswordLive, :password_reset_session, []},
      on_mount: [{TuistWeb.Authentication, :redirect_if_user_is_authenticated}] do
      live "/users/register", UserRegistrationLive, :new
      live "/users/log_in", UserLoginLive, :new
      live "/users/log_in/sso", SSOLoginLive, :new
      live "/users/reset_password", UserForgotPasswordLive, :new
      live "/users/reset_password/:token", UserResetPasswordLive, :edit
      live "/users/confirm", UserConfirmationInstructionsLive, :new
      live "/users/choose-username", ChooseUsernameLive, :new
    end

    post "/users/log_in", UserSessionController, :create
    post "/users/reset_password/:token", UserResetPasswordController, :update
    post "/users/log_in/passkey/options", UserPasskeyController, :authentication_options
    post "/users/log_in/passkey", UserPasskeyController, :authenticate
  end

  scope "/", TuistWeb do
    pipe_through [:browser_app, :require_authenticated_user, :analytics]

    get "/users/settings/mfa", UserMFAController, :show
    post "/users/settings/mfa/enroll", UserMFAController, :enroll
    post "/users/settings/mfa/confirm", UserMFAController, :confirm
    post "/users/settings/mfa/cancel", UserMFAController, :cancel
    post "/users/settings/mfa/disable", UserMFAController, :disable
    post "/users/settings/mfa/recovery", UserMFAController, :regenerate
    get "/users/settings/passkeys", UserPasskeyController, :show
    get "/users/settings/passkeys/new", UserPasskeyController, :new
    post "/users/settings/passkeys/options", UserPasskeyController, :registration_options
    post "/users/settings/passkeys", UserPasskeyController, :create
    get "/users/settings/passkeys/:id/delete", UserPasskeyController, :confirm_delete
    post "/users/settings/passkeys/:id/rename", UserPasskeyController, :rename
    post "/users/settings/passkeys/:id/delete", UserPasskeyController, :delete

    live_session :require_authenticated_user,
      session: {TuistWeb.RemoteIp, :live_session, []},
      on_mount: [
        {TuistWeb.Authentication, :ensure_authenticated},
        {TuistWeb.Locale, :assign_locale}
      ] do
      get "/dashboard", DashboardController, :dashboard
      live "/organizations/new", CreateOrganizationLive, :new
      live "/projects/new", CreateProjectLive, :new
    end
  end

  scope "/", TuistWeb do
    pipe_through [:browser_app]

    get "/users/mfa", UserMFAController, :challenge
    post "/users/mfa", UserMFAController, :verify
    post "/users/mfa/passkey/options", UserMFAController, :passkey_options
    delete "/users/log_out", UserSessionController, :delete

    live_session :current_user,
      on_mount: [{TuistWeb.Authentication, :mount_current_user}] do
      live "/users/confirm/:token", UserConfirmationLive, :edit
    end
  end

  # The One Tap start request is fetched from cached marketing pages and
  # returns a fresh token for the credential form, which stays CSRF-protected.
  scope "/auth", TuistWeb do
    pipe_through [:same_origin_csrf_exemption, :browser_app]
    post "/google/one-tap/start", AuthController, :google_one_tap_start
  end

  scope "/auth", TuistWeb do
    pipe_through [:browser_app]
    post "/google/one-tap", AuthController, :google_one_tap
    get "/complete-signup", AuthController, :complete_signup
    get "/cancel-pending-signup", AuthController, :cancel_pending_signup
  end

  scope "/users/auth", TuistWeb do
    pipe_through :browser_app
    get "/okta", AuthController, :okta_request
    get "/okta/callback", AuthController, :okta_callback
    get "/oauth2", AuthController, :oauth2_request
    get "/oauth2/callback", AuthController, :oauth2_callback
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
      live "/device/success", DeviceCodesSuccessLive, :new
      live "/invitations/:token", AcceptInvitationLive, :new
    end

    get "/sso/link", SSOLinkController, :show
    post "/sso/link", SSOLinkController, :create
    delete "/sso/link", SSOLinkController, :delete
  end

  scope "/auth", TuistWeb do
    pipe_through [:browser_app, :require_authenticated_user, :require_sso_for_credentials]

    # This route is deprecated and will be removed in future versions.
    get "/cli/:device_code", AuthController, :authenticate_cli_deprecated
    get "/device_codes/:device_code", AuthController, :authenticate_device_code
    post "/device_codes/:device_code", AuthController, :confirm_device_code

    # The standard device flow (RFC 8628): the person types the code their
    # terminal shows, and the confirmation POST approves it.
    live_session :device_authorization,
      on_mount: [{TuistWeb.Authentication, :ensure_authenticated}] do
      live "/device", DeviceAuthorizationLive, :new
    end

    post "/device", AuthController, :confirm_user_code
  end

  # Anonymous Turnstile challenge shown before public-project and
  # public-account dashboard pages when the feature flag is armed.
  # Kept OUTSIDE the `:project` / `:public_account` scopes so the
  # visitor can actually reach the challenge without solving it first.
  scope "/turnstile-challenge", TuistWeb do
    pipe_through [:browser_app]

    get "/", PublicPageChallengeController, :show
    post "/verify", PublicPageChallengeController, :verify
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

  scope "/:account_handle/:project_handle", TuistWeb do
    pipe_through [:project_asset]

    get "/logo", ProjectLogoController, :show
  end

  scope "/:account_handle/:project_handle/previews/:id", TuistWeb do
    pipe_through [
      :open_api,
      :browser_app,
      :analytics
    ]

    get "/manifest.plist", PreviewController, :manifest
    get "/app.ipa", PreviewController, :download_archive
    get "/app.apk", PreviewController, :download_apk
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

  # `/download` is the install-flow redirect a mobile device opens
  # to fetch the signed S3 URL of the archive. It cannot render a
  # Turnstile widget, so it stays outside the challenge gate. Other
  # native-download endpoints (`app.ipa`, `app.apk`, `manifest.plist`,
  # `qr-code.{svg,png}`, `icon.png`) already live in sibling scopes
  # above that never carry the challenge plug.
  scope "/:account_handle/:project_handle/previews/:id", TuistWeb do
    pipe_through [
      :open_api,
      :browser_app,
      :require_authenticated_user_for_previews,
      :mark_public_preview_page,
      :analytics,
      :embeddable
    ]

    get "/download", PreviewController, :download_preview
  end

  scope "/:account_handle/:project_handle/previews/:id", TuistWeb do
    pipe_through [
      :open_api,
      :browser_app,
      :require_authenticated_user_for_previews,
      :mark_public_preview_page,
      PublicPageChallengePlug,
      :require_member_sso_authentication,
      :analytics,
      :embeddable
    ]

    live_session :preview_detail,
      layout: {TuistWeb.Layouts, :project},
      on_mount: [
        PublicPageChallenge,
        {TuistWeb.Authentication, :mount_current_user},
        {TuistWeb.Authentication, :require_member_sso_authentication},
        {TuistWeb.LayoutLive, :optional_project}
      ] do
      live "/", PreviewLive, metadata: @public_project_route_metadata
    end
  end

  # Dashboards a public account exposes to signed-out visitors. Each
  # LiveView here re-checks `:account_dashboard_read`, which is what
  # gates the LiveSocket connect — the pipeline below only covers the
  # dead render.
  scope "/:account_handle", TuistWeb do
    pipe_through [
      :open_api,
      :browser_app,
      :rate_limit,
      :load_operator_grant,
      :redirect_to_ops_if_operator,
      :require_authenticated_user_for_private_accounts,
      :mark_public_account_page,
      PublicPageChallengePlug,
      :require_sso_authentication,
      :analytics
    ]

    get "/runners/runs/:workflow_run_id/jobs/:workflow_job_id/logs/download",
        RunnerJobLogsController,
        :download

    get "/runners/by-runner/:runner_name", RunnerJobRedirectController, :show

    live_session :public_account,
      layout: {TuistWeb.Layouts, :account},
      session: {TuistWeb.RemoteIp, :live_session, []},
      on_mount: [
        PublicPageChallenge,
        {TuistWeb.Authentication, :mount_current_user},
        {TuistWeb.OperatorGrant, :load},
        {TuistWeb.Authentication, :require_sso_authentication},
        {TuistWeb.Locale, :assign_locale},
        {TuistWeb.LayoutLive, :account}
      ] do
      live "/", ProjectsLive
      live "/projects", ProjectsLive
      live "/runners", RunnersLive
      live "/runners/workflows", RunnerWorkflowsLive
      live "/runners/workflows/:repo_owner/:repo_name/:workflow_name", RunnerWorkflowLive
      live "/runners/jobs", RunnerJobsLive
      live "/runners/runs/:workflow_run_id/jobs/:workflow_job_id", RunnerJobLive
      live "/usage", UsageLive
    end
  end

  scope "/:account_handle", TuistWeb do
    pipe_through [
      :open_api,
      :browser_app,
      :load_operator_grant,
      :redirect_to_ops_if_operator,
      :require_authenticated_user,
      :require_sso_authentication,
      :analytics
    ]

    get "/billing/manage", BillingController, :manage
    get "/billing/upgrade", BillingController, :upgrade
    get "/billing/pay", BillingController, :pay

    get "/runners/interactive/vnc",
        RunnerInteractiveVNCController,
        :connect

    get "/runners/interactive/shell",
        RunnerInteractiveShellController,
        :connect

    live_session :account,
      layout: {TuistWeb.Layouts, :account},
      on_mount: [
        {TuistWeb.Authentication, :ensure_authenticated},
        {TuistWeb.OperatorGrant, :load},
        {TuistWeb.Authentication, :require_sso_authentication},
        {TuistWeb.Locale, :assign_locale},
        {TuistWeb.LayoutLive, :account}
      ] do
      live "/~/pulse/errors/issues/:issue_id/events/:event_id", PulseErrorLive, :event
      live "/~/pulse/errors/issues/:issue_id", PulseErrorLive, :issue
      live "/~/pulse/metrics", PulseLive, :metrics
      live "/~/pulse/logs", PulseLive, :logs
      live "/~/pulse/traces", PulseLive, :traces
      live "/~/pulse/errors", PulseLive, :errors
      live "/runners/profiles", RunnerProfilesLive
      live "/runners/volumes", RunnerVolumesLive
      live "/runners/volumes/:id", RunnerVolumesLive
      live "/sandboxes", SandboxesLive
      live "/sandboxes/instances", SandboxInstancesLive
      live "/sandboxes/:sandbox_id", SandboxLive
      live "/members", MembersLive
      live "/webhooks", WebhooksLive
      live "/webhooks/:id", WebhookLive
      live "/webhooks/:id/events/:attempt_id", WebhookEventLive
      live "/cache", CacheLive
      live "/billing", BillingLive
      live "/settings", AccountSettingsLive
      live "/settings/passkeys", UserSecuritySettingsLive, :passkeys
      live "/settings/two-factor-authentication", UserSecuritySettingsLive, :mfa
      live "/settings/tokens", AccountTokensLive
      live "/settings/tokens/:token_id", AccountTokenLive
      live "/settings/integrations", IntegrationsLive
      live "/settings/authentication", AuthenticationSettingsLive
      live "/settings/authentication/workload-identities", AuthenticationSettingsLive, :workload_identities
      live "/settings/ai", AISubscriptionsSettingsLive
      live "/settings/ai/routing", OrganizationAISettingsLive
    end
  end

  scope "/:account_handle/:project_handle", TuistWeb do
    pipe_through [
      :open_api,
      :browser_app,
      :rate_limit,
      :load_operator_grant,
      :redirect_to_ops_if_operator,
      :require_authenticated_user_for_private_projects,
      :mark_public_project_page,
      PublicPageChallengePlug,
      :require_sso_authentication,
      :analytics,
      :require_user_can_read_project
    ]

    live_session :project,
      layout: {TuistWeb.Layouts, :project},
      on_mount: [
        PublicPageChallenge,
        {TuistWeb.Authentication, :mount_current_user},
        {TuistWeb.OperatorGrant, :load},
        {TuistWeb.Authentication, :require_sso_authentication},
        {TuistWeb.Locale, :assign_locale},
        {TuistWeb.LayoutLive, :project}
      ] do
      live "/tests", TestsLive, metadata: @public_project_route_metadata
      live "/tests/test-runs", TestRunsLive, metadata: @public_project_route_metadata
      live "/tests/coverage", CoverageLive
      live "/tests/coverage/branches/*branch", CoverageDetailLive, :branch
      live "/tests/coverage/commits/:git_commit_sha", CoverageDetailLive, :commit
      live "/tests/coverage/files/*path", CoverageFileLive, :show
      live "/tests/test-selection", TestSelectionsLive
      live "/tests/test-runs/:test_run_id", TestRunLive, metadata: @public_project_route_metadata
      live "/tests/test-cases", TestCasesLive, metadata: @public_project_route_metadata
      live "/tests/test-cases/:test_case_id", TestCaseLive, metadata: @public_project_route_metadata
      live "/tests/test-cases/runs/:test_case_run_id", TestCaseRunLive, metadata: @public_project_route_metadata
      live "/tests/flaky-tests", FlakyTestsLive, metadata: @public_project_route_metadata
      live "/tests/quarantined-tests", QuarantinedTestsLive, metadata: @public_project_route_metadata
      live "/tests/shards", ShardsLive, metadata: @public_project_route_metadata
      live "/module-cache", ModuleCacheLive, metadata: @public_project_route_metadata
      live "/module-cache/cache-runs", CacheRunsLive, metadata: @public_project_route_metadata
      live "/module-cache/generate-runs", GenerateRunsLive, metadata: @public_project_route_metadata
      live "/module-cache/modules", ModulesLive, metadata: @public_project_route_metadata
      live "/module-cache/modules/:module", ModuleCacheModuleLive, metadata: @public_project_route_metadata
      live "/xcode-cache", XcodeCacheLive, metadata: @public_project_route_metadata
      live "/gradle-cache", GradleCacheLive, metadata: @public_project_route_metadata
      live "/mix-cache", ToolchainCacheLive, :mix, metadata: @public_project_route_metadata
      live "/cargo-cache", ToolchainCacheLive, :cargo, metadata: @public_project_route_metadata
      live "/builds/tasks", GradleTasksLive, :tasks, metadata: @public_project_route_metadata
      live "/builds/tasks/:name", GradleTasksLive, :task, metadata: @public_project_route_metadata
      live "/bazel-cache", BazelCacheLive, metadata: @public_project_route_metadata
      get "/once", RedirectPlug, to: "/once/builds"
      get "/once/runs", RedirectPlug, to: "/once/build-runs"
      live "/once/runs/:once_run_id", OnceRunLive, :overview, metadata: @public_project_route_metadata
      live "/once/runs/:once_run_id/cache", OnceRunLive, :cache, metadata: @public_project_route_metadata
      live "/once/builds", OnceRunsLive, :builds, metadata: @public_project_route_metadata
      live "/once/build-runs", OnceRunsLive, :build_runs, metadata: @public_project_route_metadata
      live "/once/tests", OnceTestsLive, metadata: @public_project_route_metadata
      live "/once/test-runs", OnceRunsLive, :tests, metadata: @public_project_route_metadata
      live "/once/test-runs/:once_run_id", OnceTestRunLive, metadata: @public_project_route_metadata

      live "/once/test-runs/:once_run_id/test-cases/:case_id", OnceTestCaseRunLive,
        metadata: @public_project_route_metadata

      live "/once-cache", OnceCacheLive, metadata: @public_project_route_metadata
      live "/connect", ConnectLive
      get "/invocations", RedirectPlug, to: "/builds"
      live "/invocations/:invocation_id", BazelBuildInvocationLive, metadata: @public_project_route_metadata
      live "/", OverviewLive, metadata: %{public_project: true, robots_txt: false}
      live "/analytics", OverviewLive, :analytics, metadata: @public_project_route_metadata
      live "/bundles", BundlesLive, metadata: @public_project_route_metadata
      live "/bundles/:bundle_id", BundleLive, metadata: @public_project_route_metadata
      live "/builds/cargo/crates", BuildEntityLive, :cargo_crates, metadata: @public_project_route_metadata
      live "/builds/cargo/crates/:crate_id", BuildEntityLive, :cargo_crates, metadata: @public_project_route_metadata
      live "/builds/bazel/actions", BuildEntityLive, :bazel_actions, metadata: @public_project_route_metadata
      live "/builds/bazel/actions/:action_id", BuildEntityLive, :bazel_actions, metadata: @public_project_route_metadata
      live "/builds/gradle/tasks", BuildEntityLive, :gradle_tasks, metadata: @public_project_route_metadata
      live "/builds/gradle/tasks/:task_id", BuildEntityLive, :gradle_tasks, metadata: @public_project_route_metadata
      live "/builds/xcode/modules", BuildEntityLive, :xcode_modules, metadata: @public_project_route_metadata
      live "/builds/xcode/modules/:module_id", BuildEntityLive, :xcode_modules, metadata: @public_project_route_metadata
      live "/builds/once/actions", BuildEntityLive, :once_actions, metadata: @public_project_route_metadata
      live "/builds/once/actions/:action_id", BuildEntityLive, :once_actions, metadata: @public_project_route_metadata
      live "/builds/mix/files", BuildEntityLive, :mix_files, metadata: @public_project_route_metadata
      live "/builds/mix/files/:file_id", BuildEntityLive, :mix_files, metadata: @public_project_route_metadata
      live "/builds/mix/modules", BuildEntityLive, :mix_modules, metadata: @public_project_route_metadata
      live "/builds/mix/modules/:module_id", BuildEntityLive, :mix_modules, metadata: @public_project_route_metadata

      live "/builds", BuildsLive, metadata: @public_project_route_metadata
      live "/builds/build-runs", BuildRunsLive, metadata: @public_project_route_metadata

      live "/builds/build-runs/:build_run_id/tasks/:task_id", GradleTaskExecutionLive,
        metadata: @public_project_route_metadata

      live "/builds/build-runs/:build_run_id", BuildRunLive, metadata: @public_project_route_metadata
      live "/builds/invocations/:invocation_id", BazelBuildInvocationLive, metadata: @public_project_route_metadata
      live "/builds/cargo-builds/:build_id", CargoBuildLive, metadata: @public_project_route_metadata
      live "/builds/mix-builds/:build_id", MixBuildLive, metadata: @public_project_route_metadata
      live "/previews", PreviewsLive, metadata: @public_project_route_metadata
      live "/runs/:run_id", RunDetailLive, metadata: @public_project_route_metadata
      get "/runs/:run_id/download", RunsController, :download
      get "/runs/:run_id/download_session", RunsController, :download_session
      get "/builds/build-runs/:build_run_id/download", BuildController, :download
      get "/builds/build-runs/:build_run_id/timeline.json", BuildController, :timeline
      get "/builds/invocations/:invocation_id/timeline.json", BuildController, :timeline
      get "/builds/build-runs/:build_run_id/trace.json", BuildController, :trace
      get "/builds/invocations/:invocation_id/trace.json", BuildController, :trace

      get "/tests/test-cases/runs/:test_case_run_id/attachments/:file_name",
          TestCaseRunAttachmentsController,
          :download

      live "/settings", ProjectSettingsLive
      live "/settings/integrations", ProjectIntegrationsLive
      live "/settings/automations", ProjectAutomationsLive
      live "/settings/automations/:automation_id", ProjectAutomationLive
      live "/settings/bundles", ProjectBundleSettingsLive
      live "/settings/notifications", ProjectNotificationsLive
    end

    # Redirects for renamed routes
    get "/binary-cache/cache-runs", RedirectPlug, to: "/module-cache/cache-runs"

    get "/binary-cache/generate-runs", RedirectPlug, to: "/module-cache/generate-runs"
  end

  def assign_current_path(conn, _params) do
    assign(conn, :current_path, conn.request_path)
  end

  defp put_threads_no_store(conn, _opts), do: put_resp_header(conn, "cache-control", "no-store")

  defp put_request_kind(conn, kind) when is_binary(kind) do
    assign(conn, :request_kind, kind)
  end

  def disable_robot_indexing(conn, _params) do
    put_resp_header(conn, "x-robots-tag", "noindex, nofollow")
  end

  defp enable_robot_indexing(conn, params) do
    if Tuist.Environment.prod?() and Tuist.Environment.tuist_hosted?() do
      put_resp_header(conn, "x-robots-tag", "index, follow")
    else
      disable_robot_indexing(conn, params)
    end
  end

  # FunWithFlags.UI serves its bundled JS via Plug.Static after the :browser_app
  # pipeline registers Plug.CSRFProtection's before_send callback, which raises
  # InvalidCrossOriginRequestError on any non-XHR GET that returns a JS response.
  # Constrained to safe methods so any future state-changing route under this
  # prefix still goes through CSRF protection.
  defp skip_csrf_for_fun_with_flags_assets(
         %Plug.Conn{method: method, path_info: ["ops", "flags", "assets" | _]} = conn,
         _opts
       )
       when method in ["GET", "HEAD"] do
    Plug.Conn.put_private(conn, :plug_skip_csrf_protection, true)
  end

  defp skip_csrf_for_fun_with_flags_assets(conn, _opts), do: conn
end
