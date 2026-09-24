defmodule TuistWeb.DocsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Docs.MarkdownComponents, warn: false

  alias Tuist.Docs
  alias Tuist.Docs.Paths
  alias Tuist.Docs.Sidebar
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Marketing.SocialCards
  alias TuistWeb.Marketing.StructuredMarkup

  @noora_icons_path Path.expand("../../../../noora/lib/noora/icons", __DIR__)
  @copy_check_icon @noora_icons_path |> Path.join("copy-check.svg") |> File.read!() |> String.trim()

  @overview_headings [
    %{id: "learn-more", text: "Explore Tuist's capabilities", level: 2},
    %{id: "builds", text: "Builds", level: 2},
    %{id: "tests", text: "Tests", level: 2},
    %{id: "artifacts", text: "Artifacts", level: 2},
    %{id: "see-tuist-in-action", text: "See Tuist in action", level: 2},
    %{id: "open-source-and-community", text: "Open source and community", level: 2}
  ]

  def mount(_params, _session, socket) do
    locale = Gettext.get_locale()

    socket =
      socket
      |> assign(:locale, locale)
      |> attach_hook(:assign_current_path, :handle_params, fn _params, url, socket ->
        uri = URI.parse(url)
        current_path = if(is_nil(uri.query), do: uri.path, else: "#{uri.path}?#{uri.query}")
        {:cont, assign(socket, current_path: current_path)}
      end)

    {:ok, socket}
  end

  def handle_params(params, _url, socket) do
    case socket.assigns.live_action do
      :overview -> handle_overview(socket)
      :show -> handle_show(params, socket)
    end
  end

  defp handle_overview(socket) do
    videos = fetch_latest_videos()
    locale = socket.assigns.locale
    root_path = Paths.root_path(locale)
    description = "Build, test, and run Xcode and Gradle projects faster with Tuist's shared build infrastructure."

    {:noreply,
     socket
     |> assign(:view, :overview)
     |> assign(:videos, videos)
     |> assign(:markdown, overview_markdown(locale, videos))
     |> assign(:page_title, "Docs · Tuist")
     |> assign(:head_title, "Docs · Tuist")
     |> assign(:head_description, description)
     # The landing page has a designed social card; the docs pages below
     # it keep their rendered per-page cards.
     |> assign(:head_image, SocialCards.image_url("docs"))
     |> assign(:head_twitter_card, "summary_large_image")
     |> assign(:head_markdown_path, Paths.markdown_root_path(locale))
     |> StructuredMarkup.put_structured_data([
       StructuredMarkup.get_documentation_structured_data("Docs", description, root_path),
       StructuredMarkup.get_breadcrumbs_structured_data([
         {"Tuist", Tuist.Environment.app_url(path: "/")},
         {"Docs", Tuist.Environment.app_url(path: root_path)}
       ])
     ])}
  end

  defp handle_show(params, socket) do
    path = build_path(params, socket.assigns.locale)

    case Docs.get_page(path) do
      nil ->
        raise NotFoundError, dgettext("errors", "Page not found")

      page ->
        head_title =
          case page.title_template do
            nil -> "#{page.title} · Docs · Tuist"
            template -> String.replace(template, ":title", page.title)
          end

        head_image =
          if Tuist.Environment.tuist_hosted?() do
            og_image_path =
              OpenGraph.image_path(:docs,
                title: page.title,
                description: page.description,
                category: Sidebar.category_for_slug(page.slug)
              )

            Tuist.Environment.app_url(path: og_image_path)
          end

        # Every URL below is derived from the requested slug, never from
        # `page.slug`. `Docs.get_page/1` falls back to the English page when a
        # locale has no translation, so `page.slug` would point the markup at
        # `/en/...` while the canonical link still says `/es/...`, leaving the
        # page claiming two identities.
        public_path = Paths.public_path_from_slug(path)
        locale = socket.assigns.locale

        {:noreply,
         socket
         |> assign(:view, :show)
         |> assign(:page, page)
         |> assign(:markdown, page.markdown)
         |> assign(:requested_slug, path)
         |> assign(:page_title, head_title)
         |> assign(:head_title, head_title)
         |> assign(:head_description, page.description)
         |> assign(:head_image, head_image)
         |> assign(:head_twitter_card, "summary_large_image")
         |> assign(:head_markdown_path, Paths.markdown_path_from_slug(path))
         |> StructuredMarkup.put_structured_data([
           StructuredMarkup.get_documentation_structured_data(page.title, page.description, public_path),
           StructuredMarkup.get_breadcrumbs_structured_data(docs_breadcrumbs(page.title, locale, public_path))
         ])}
    end
  end

  # Breadcrumbs give search engines and assistants the page's place in the docs
  # tree, which a flat URL alone does not convey. Sidebar categories are omitted
  # because they have no page of their own to point at.
  defp docs_breadcrumbs(title, locale, public_path) do
    [
      {"Tuist", Tuist.Environment.app_url(path: "/")},
      {"Docs", Tuist.Environment.app_url(path: Paths.root_path(locale))},
      {title, Tuist.Environment.app_url(path: public_path)}
    ]
  end

  attr :systems, :list, required: true

  defp supported_for(assigns) do
    ~H"""
    <div :if={@systems != []} data-part="supported-for">
      <span data-part="supported-label">{dgettext("docs", "Supported for:")}</span>
      <span :for={system <- @systems} data-part="supported-icon" title={system}>
        <.icon name={"brand_#{system}"} />
      </span>
    </div>
    """
  end

  def render(%{view: :overview} = assigns) do
    assigns =
      assigns
      |> assign(:install_path, docs_path("/#{assigns.locale}/guides/install-tuist"))
      |> assign(:get_started_path, docs_path("/#{assigns.locale}/guides/get-started"))
      |> assign(:copy_check_icon, @copy_check_icon)
      |> assign(:headings, @overview_headings)

    ~H"""
    <TuistWeb.Docs.Components.layout
      current_slug={"/#{@locale}"}
      tab={:guides}
      headings={@headings}
      markdown={@markdown}
      locale={@locale}
    >
      <div id="docs-overview">
        <%!-- Hero --%>
        <section data-part="hero">
          <h1>{dgettext("docs", "One platform for faster build toolchains")}</h1>
          <p>
            {dgettext(
              "docs",
              "Code is being produced faster and at greater volume than ever. Tuist plugs into the build systems you already use, on Xcode, Gradle, and Bazel projects, providing the infrastructure that lets software integration and delivery keep pace."
            )}
          </p>
        </section>

        <%!-- Hero cards --%>
        <section data-part="hero-cards">
          <div
            id="docs-install-card"
            data-part="hero-card"
            data-clickable
            phx-click={JS.patch(@install_path)}
            phx-key="Enter"
            role="link"
            tabindex="0"
            aria-label={dgettext("docs", "Install Tuist CLI")}
          >
            <div data-part="hero-card-bg"></div>
            <h3>{dgettext("docs", "Install Tuist CLI")}</h3>
            <div data-part="terminal-group" id="docs-install-terminal" phx-hook="DocsInstallTabs">
              <div data-part="terminal">
                <div data-part="terminal-header">
                  <div data-part="terminal-tabs">
                    <span
                      data-part="terminal-tab"
                      data-selected
                      phx-click={JS.exec("event.stopPropagation()", to: "window")}
                    >
                      mise
                    </span>
                    <span
                      data-part="terminal-tab"
                      phx-click={JS.exec("event.stopPropagation()", to: "window")}
                    >
                      homebrew
                    </span>
                  </div>
                  <button
                    data-part="terminal-copy"
                    aria-label={dgettext("docs", "Copy command")}
                    phx-click={JS.exec("event.stopPropagation()", to: "window")}
                  >
                    <span data-part="copy-icon"><.copy /></span>
                    <span data-part="copy-check-icon">{raw(@copy_check_icon)}</span>
                  </button>
                </div>
                <div data-part="terminal-body">
                  <code>mise install tuist</code>
                </div>
              </div>
              <p data-part="hero-card-hint">
                {dgettext("docs", "or follow the instructions to")}
                <.link patch={@install_path} data-part="hero-card-link">
                  {dgettext("docs", "install specific version of tuist")}
                </.link>
              </p>
            </div>
          </div>
          <.link navigate="/tuist/tuist" data-part="hero-card" data-variant="dashboard">
            <div data-part="hero-card-bg"></div>
            <h3>{dgettext("docs", "Explore dashboard")}</h3>
            <div data-part="browser-mockup">
              <div data-part="browser-bar">
                <span data-part="browser-dot" data-color="red"></span>
                <span data-part="browser-dot" data-color="yellow"></span>
                <span data-part="browser-dot" data-color="green"></span>
              </div>
              <div data-part="browser-content">
                <div data-part="browser-sidebar">
                  <div data-part="browser-sidebar-items">
                    <div data-part="sidebar-line"></div>
                    <div data-part="sidebar-line"></div>
                    <div data-part="sidebar-line"></div>
                    <div data-part="sidebar-line"></div>
                  </div>
                </div>
                <div data-part="browser-main">
                  <div data-part="main-row" data-cols="4">
                    <div data-part="main-block"></div>
                    <div data-part="main-block"></div>
                    <div data-part="main-block"></div>
                    <div data-part="main-block"></div>
                  </div>
                  <div data-part="main-row" data-cols="2-wide">
                    <div data-part="main-block" data-wide></div>
                    <div data-part="main-block" data-narrow></div>
                  </div>
                  <div data-part="main-row" data-cols="2-equal">
                    <div data-part="main-block" data-equal></div>
                    <div data-part="main-block" data-equal></div>
                  </div>
                  <div data-part="sidebar-line" data-short></div>
                </div>
              </div>
            </div>
          </.link>
        </section>
        <%!-- What Tuist offers --%>
        <section data-part="section-intro">
          <h1 id="learn-more">{dgettext("docs", "Explore Tuist's capabilities")}</h1>
          <p>
            {dgettext(
              "docs",
              "Speed up builds, improve test reliability, understand performance, and run workflows on infrastructure designed for your toolchain."
            )}
          </p>
        </section>

        <%!-- Builds --%>
        <section data-part="feature-section">
          <h2 id="builds">{dgettext("docs", "Builds")}</h2>
          <p>
            {dgettext(
              "docs",
              "Share build work across developer machines, continuous integration, runners, and coding agents, then use insights to find regressions."
            )}
          </p>
          <div data-part="feature-cards">
            <.link
              id="docs-cache-card"
              patch={docs_path("/#{@locale}/guides/features/cache")}
              data-part="feature-card"
            >
              <div data-part="image">
                <span data-part="icon"><.database /></span>
                <span data-part="title">{dgettext("docs", "Cache")}</span>
              </div>
              <div data-part="body">
                <p>
                  {dgettext(
                    "docs",
                    "Reuse build artifacts across Xcode, Gradle, and Bazel so work completed in one environment speeds up every other environment."
                  )}
                </p>
                <.supported_for systems={~w(apple gradle bazel)} />
              </div>
            </.link>
            <.link
              patch={docs_path("/#{@locale}/guides/features/build-insights")}
              data-part="feature-card"
            >
              <div data-part="image">
                <span data-part="icon"><.search /></span>
                <span data-part="title">{dgettext("docs", "Insights")}</span>
              </div>
              <div data-part="body">
                <p>
                  {dgettext(
                    "docs",
                    "Understand build performance across local and continuous integration environments before slowdowns affect your team."
                  )}
                </p>
                <.supported_for systems={~w(apple gradle bazel)} />
              </div>
            </.link>
          </div>
        </section>

        <%!-- Tests --%>
        <section data-part="feature-section">
          <h2 id="tests">{dgettext("docs", "Tests")}</h2>
          <p>
            {dgettext(
              "docs",
              "Run the tests that matter, detect flaky behavior, and understand test performance locally and in continuous integration."
            )}
          </p>
          <div data-part="feature-cards">
            <.link
              patch={docs_path("/#{@locale}/guides/features/selective-testing")}
              data-part="feature-card"
            >
              <div data-part="image">
                <span data-part="icon"><.subtask /></span>
                <span data-part="title">{dgettext("docs", "Selective Testing")}</span>
              </div>
              <div data-part="body">
                <p>
                  {dgettext(
                    "docs",
                    "Run only impacted tests by detecting changes since your last successful run, both locally and in continuous integration."
                  )}
                </p>
                <.supported_for systems={~w(apple)} />
              </div>
            </.link>
            <.link
              patch={docs_path("/#{@locale}/guides/features/test-insights/flaky-tests")}
              data-part="feature-card"
            >
              <div data-part="image">
                <span data-part="icon"><.progress_x /></span>
                <span data-part="title">{dgettext("docs", "Flaky Tests")}</span>
              </div>
              <div data-part="body">
                <p>
                  {dgettext(
                    "docs",
                    "Automatically detect flaky tests that fail without code changes and save time spent investigating false failures."
                  )}
                </p>
                <.supported_for systems={~w(apple gradle bazel)} />
              </div>
            </.link>
            <.link
              patch={docs_path("/#{@locale}/guides/features/test-insights")}
              data-part="feature-card"
            >
              <div data-part="image">
                <span data-part="icon"><.search /></span>
                <span data-part="title">{dgettext("docs", "Insights")}</span>
              </div>
              <div data-part="body">
                <p>
                  {dgettext(
                    "docs",
                    "Track test performance, catch slow tests early, and debug continuous integration failures through real-time logs."
                  )}
                </p>
                <.supported_for systems={~w(apple gradle bazel)} />
              </div>
            </.link>
          </div>
        </section>

        <%!-- Artifacts --%>
        <section data-part="feature-section">
          <h2 id="artifacts">{dgettext("docs", "Artifacts")}</h2>
          <p>
            {dgettext(
              "docs",
              "Move from a successful build to useful feedback with shareable previews and bundle-size insights."
            )}
          </p>
          <div data-part="feature-cards">
            <.link patch={docs_path("/#{@locale}/guides/features/previews")} data-part="feature-card">
              <div data-part="image">
                <span data-part="icon"><.devices /></span>
                <span data-part="title">{dgettext("docs", "Previews")}</span>
              </div>
              <div data-part="body">
                <p>
                  {dgettext(
                    "docs",
                    "Share your app with a link so others can run it on their device or simulator without TestFlight setup."
                  )}
                </p>
                <.supported_for systems={~w(apple android)} />
              </div>
            </.link>
          </div>
        </section>

        <%!-- See Tuist in action --%>
        <section data-part="section-intro">
          <h1 id="see-tuist-in-action">{dgettext("docs", "See Tuist in action")}</h1>
          <p>
            {dgettext(
              "docs",
              "Learn from real implementations and get inspired by what's possible when your toolchain just works."
            )}
          </p>
        </section>

        <section data-part="video-cards">
          <a
            :for={video <- @videos}
            href={"https://videos.tuist.dev/w/#{video.uuid}"}
            target="_blank"
            rel="noopener noreferrer"
            data-part="video-card"
          >
            <div data-part="video-card-thumbnail">
              <img src={video.thumbnail_url} alt={video.name} />
              <span data-part="video-play-icon"><.player_play /></span>
            </div>
            <div data-part="video-card-info">
              <p>{video.name}</p>
            </div>
          </a>
        </section>

        <%!-- Open source and community --%>
        <section data-part="section-intro">
          <h1 id="open-source-and-community">{dgettext("docs", "Open source and community")}</h1>
          <p>
            {dgettext(
              "docs",
              "Connect with thousands of developers who are shipping better apps with Tuist. Get help, share wins, and shape the future of app development tooling."
            )}
          </p>
        </section>

        <section data-part="community-cards">
          <a
            href="https://github.com/tuist/tuist"
            target="_blank"
            rel="noopener noreferrer"
            data-part="community-card"
          >
            <div data-part="community-card-header">
              <.brand_github />
              <span>GitHub</span>
            </div>
            <p>{dgettext("docs", "Contribute or report issues to our open source repository.")}</p>
          </a>
          <a
            href="https://slack.tuist.dev"
            target="_blank"
            rel="noopener noreferrer"
            data-part="community-card"
          >
            <div data-part="community-card-header">
              <.brand_slack />
              <span>Slack</span>
            </div>
            <p>{dgettext("docs", "Chat with the Tuist community in real-time.")}</p>
          </a>
          <a
            href="https://community.tuist.dev"
            target="_blank"
            rel="noopener noreferrer"
            data-part="community-card"
          >
            <div data-part="community-card-header">
              <.message_circle />
              <span>Discourse</span>
            </div>
            <p>
              {dgettext(
                "docs",
                "Share your ideas, report issues, and discuss with other community members."
              )}
            </p>
          </a>
          <a
            href="https://videos.tuist.dev"
            target="_blank"
            rel="noopener noreferrer"
            data-part="community-card"
          >
            <div data-part="community-card-header">
              <.player_play />
              <span>{dgettext("docs", "Videos")}</span>
            </div>
            <p>{dgettext("docs", "Learn from videos from the Tuist team and the community.")}</p>
          </a>
          <a
            href="https://bsky.app/profile/tuist.dev"
            target="_blank"
            rel="noopener noreferrer"
            data-part="community-card"
          >
            <div data-part="community-card-header">
              <.brand_bluesky />
              <span>Bluesky</span>
            </div>
            <p>{dgettext("docs", "Follow us on Bluesky to stay up to date with our work.")}</p>
          </a>
          <a
            href="https://fosstodon.org/@tuist"
            target="_blank"
            rel="noopener noreferrer"
            data-part="community-card"
          >
            <div data-part="community-card-header">
              <.brand_mastodon />
              <span>Mastodon</span>
            </div>
            <p>{dgettext("docs", "Follow us on Mastodon to stay up to date with our work.")}</p>
          </a>
          <a
            href="https://www.linkedin.com/company/tuistio"
            target="_blank"
            rel="noopener noreferrer"
            data-part="community-card"
          >
            <div data-part="community-card-header">
              <.brand_linkedin />
              <span>LinkedIn</span>
            </div>
            <p>{dgettext("docs", "Follow Tuist on LinkedIn for news and updates.")}</p>
          </a>
          <a
            href="https://x.com/tuistdev"
            target="_blank"
            rel="noopener noreferrer"
            data-part="community-card"
          >
            <div data-part="community-card-header">
              <.brand_x />
              <span>X</span>
            </div>
            <p>{dgettext("docs", "Follow us on X to stay up to date with our work.")}</p>
          </a>
        </section>
      </div>
    </TuistWeb.Docs.Components.layout>
    """
  end

  def render(%{view: :show} = assigns) do
    ~H"""
    <TuistWeb.Docs.Components.layout
      current_slug={@requested_slug}
      tab={Tuist.Docs.Sidebar.tab_for_slug(@requested_slug)}
      headings={@page.headings}
      markdown={@markdown}
      locale={@locale}
    >
      <article id={"docs-body-#{@page.slug}"} class="tuist-docs" data-prose phx-hook="DocsContent">
        {render_doc_body(@page, assigns)}
      </article>
      <footer id="docs-page-footer">
        <div data-part="markdown-link">
          <span>{dgettext("docs", "View")}</span>
          <.link_button
            label={dgettext("docs", "as Markdown")}
            variant="primary"
            size="large"
            href={docs_markdown_path(@requested_slug)}
            target="_blank"
            rel="noopener noreferrer"
          />
        </div>
        <div data-part="edit-row">
          <.link_button
            label={dgettext("docs", "Edit this page")}
            variant="primary"
            size="large"
            href={github_edit_url(@page.source_path)}
            target="_blank"
            rel="noopener noreferrer"
          >
            <:icon_left><.icon name="pencil" /></:icon_left>
          </.link_button>
          <span :if={@page.last_modified} data-part="last-updated">
            {dgettext("docs", "Last updated on %{date}", date: format_date(@page.last_modified))}
          </span>
        </div>
      </footer>
    </TuistWeb.Docs.Components.layout>
    """
  end

  def handle_event("copy-page-markdown", _params, %{assigns: %{markdown: markdown}} = socket)
      when is_binary(markdown) and markdown != "" do
    {:noreply, push_event(socket, "docs:copy-to-clipboard", %{text: markdown})}
  end

  def handle_event("copy-page-markdown", _params, socket) do
    {:noreply, socket}
  end

  defp overview_markdown(locale, videos) do
    cache_path = docs_path("/#{locale}/guides/features/cache")
    build_insights_path = docs_path("/#{locale}/guides/features/build-insights")
    selective_testing_path = docs_path("/#{locale}/guides/features/selective-testing")
    flaky_tests_path = docs_path("/#{locale}/guides/features/test-insights/flaky-tests")
    test_insights_path = docs_path("/#{locale}/guides/features/test-insights")
    previews_path = docs_path("/#{locale}/guides/features/previews")
    install_path = docs_path("/#{locale}/guides/install-tuist")

    get_started_path = docs_path("/#{locale}/guides/get-started")

    video_lines =
      if videos == [] do
        []
      else
        [
          "## " <> dgettext("docs", "See Tuist in action"),
          "",
          dgettext(
            "docs",
            "Learn from real implementations and get inspired by what's possible when your toolchain just works."
          ),
          ""
        ] ++
          Enum.map(videos, fn video ->
            "- [#{video.name}](https://videos.tuist.dev/w/#{video.uuid})"
          end) ++ [""]
      end

    Enum.join(
      [
        "# " <> dgettext("docs", "One platform for faster build toolchains"),
        "",
        dgettext(
          "docs",
          "Code is being produced faster and at greater volume than ever. Tuist plugs into the build systems you already use, on Xcode, Gradle, and Bazel projects, providing the infrastructure that lets software integration and delivery keep pace."
        ),
        "",
        markdown_link(dgettext("docs", "Install Tuist"), install_path),
        markdown_link(dgettext("docs", "Get started"), get_started_path),
        "",
        "## " <> dgettext("docs", "Explore Tuist's capabilities"),
        "",
        dgettext(
          "docs",
          "Speed up builds, improve test reliability, understand performance, and run workflows on infrastructure designed for your toolchain."
        ),
        "",
        "## " <> dgettext("docs", "Builds"),
        "",
        dgettext(
          "docs",
          "Share build work across developer machines, continuous integration, runners, and coding agents, then use insights to find regressions."
        ),
        "",
        "- #{markdown_link(dgettext("docs", "Cache"), cache_path)}: " <>
          dgettext(
            "docs",
            "Reuse build artifacts across Xcode, Gradle, and Bazel so work completed in one environment speeds up every other environment."
          ),
        "- #{markdown_link(dgettext("docs", "Insights"), build_insights_path)}: " <>
          dgettext(
            "docs",
            "Understand build performance across local and continuous integration environments before slowdowns affect your team."
          ),
        "",
        "## " <> dgettext("docs", "Tests"),
        "",
        dgettext(
          "docs",
          "Run the tests that matter, detect flaky behavior, and understand test performance locally and in continuous integration."
        ),
        "",
        "- #{markdown_link(dgettext("docs", "Selective Testing"), selective_testing_path)}: " <>
          dgettext(
            "docs",
            "Run only impacted tests by detecting changes since your last successful run, both locally and in continuous integration."
          ),
        "- #{markdown_link(dgettext("docs", "Flaky Tests"), flaky_tests_path)}: " <>
          dgettext(
            "docs",
            "Automatically detect flaky tests that fail without code changes and save time spent investigating false failures."
          ),
        "- #{markdown_link(dgettext("docs", "Insights"), test_insights_path)}: " <>
          dgettext(
            "docs",
            "Track test performance, catch slow tests early, and debug continuous integration failures through real-time logs."
          ),
        "",
        "## " <> dgettext("docs", "Artifacts"),
        "",
        dgettext(
          "docs",
          "Move from a successful build to useful feedback with shareable previews and bundle-size insights."
        ),
        "",
        "- #{markdown_link(dgettext("docs", "Previews"), previews_path)}: " <>
          dgettext(
            "docs",
            "Share your app with a link so others can run it on their device or simulator without TestFlight setup."
          ),
        ""
      ] ++
        video_lines ++
        [
          "## " <> dgettext("docs", "Open source and community"),
          "",
          dgettext(
            "docs",
            "Connect with thousands of developers who are shipping better apps with Tuist. Get help, share wins, and shape the future of app development tooling."
          ),
          "",
          "- [GitHub](https://github.com/tuist/tuist): " <>
            dgettext("docs", "Contribute or report issues to our open source repository."),
          "- [Slack](https://slack.tuist.dev): " <> dgettext("docs", "Chat with the Tuist community in real-time."),
          "- [Discourse](https://community.tuist.dev): " <>
            dgettext("docs", "Share your ideas, report issues, and discuss with other community members."),
          "- [#{dgettext("docs", "Videos")}](https://videos.tuist.dev): " <>
            dgettext("docs", "Learn from videos from the Tuist team and the community."),
          "- [Bluesky](https://bsky.app/profile/tuist.dev): " <>
            dgettext("docs", "Follow us on Bluesky to stay up to date with our work."),
          "- [Mastodon](https://fosstodon.org/@tuist): " <>
            dgettext("docs", "Follow us on Mastodon to stay up to date with our work."),
          "- [LinkedIn](https://www.linkedin.com/company/tuistio): " <>
            dgettext("docs", "Follow Tuist on LinkedIn for news and updates.")
        ],
      "\n"
    )
  end

  defp markdown_link(label, href), do: "[#{label}](#{href})"

  defp fetch_latest_videos do
    case Req.get("https://videos.tuist.dev/api/v1/videos",
           params: [count: 3, sort: "-publishedAt"]
         ) do
      {:ok, %{status: 200, body: %{"data" => videos}}} ->
        Enum.map(videos, fn video ->
          %{
            name: video["name"],
            uuid: video["uuid"],
            thumbnail_url: "https://videos.tuist.dev#{video["thumbnailPath"]}"
          }
        end)

      _ ->
        []
    end
  end

  defp render_doc_body(%{body_template: template, code_blocks: code_blocks}, assigns) when not is_nil(template) do
    merged_assigns = Map.put(assigns, :_doc_code_blocks, code_blocks || [])

    {rendered, _} =
      Code.eval_quoted(template, [assigns: merged_assigns], Macro.Env.prune_compile_info(__ENV__))

    rendered
  end

  defp render_doc_body(%{body: body}, _assigns), do: raw(body)

  defp build_path(%{"path" => path_parts}, locale), do: Paths.slug(locale, path_parts)
  defp build_path(_params, locale), do: Paths.slug(locale)

  defp docs_path(slug), do: Paths.public_path_from_slug(slug)

  defp docs_markdown_path("/" <> _ = slug) do
    case String.split(slug, "/", trim: true) do
      [locale | path_segments] -> "/#{locale}/docs-markdown/#{Enum.join(path_segments, "/")}"
      [] -> "/en/docs-markdown"
    end
  end

  defp github_edit_url(source_path) do
    "https://github.com/tuist/tuist/edit/main/server/priv/docs/#{source_path}"
  end

  defp format_date(date) do
    Calendar.strftime(date, "%b %d, %Y")
  end
end
