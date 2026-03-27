defmodule TuistWeb.DocsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Docs
  alias Tuist.Docs.Paths
  alias TuistWeb.Errors.NotFoundError

  @noora_icons_path Path.expand("../noora/lib/noora/icons", File.cwd!())
  @copy_check_icon @noora_icons_path |> Path.join("copy-check.svg") |> File.read!() |> String.trim()
  @overview_headings [
    %{id: "learn-more", text: "Learn more about what Tuist offers", level: 2},
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

    {:noreply,
     socket
     |> assign(:view, :overview)
     |> assign(:videos, videos)
     |> assign(:page_title, "Docs · Tuist")
     |> assign(:head_title, "Docs · Tuist")
     |> assign(:head_description, "Learn how to use Tuist to make mobile your competitive advantage.")}
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

        {:noreply,
         socket
         |> assign(:view, :show)
         |> assign(:page, page)
         |> assign(:requested_slug, path)
         |> assign(:page_title, head_title)
         |> assign(:head_title, head_title)
         |> assign(:head_description, page.description)}
    end
  end

  def render(%{view: :overview} = assigns) do
    assigns =
      assigns
      |> assign(:install_path, docs_path("/#{assigns.locale}/guides/install-tuist"))
      |> assign(:copy_check_icon, @copy_check_icon)
      |> assign(:headings, @overview_headings)

    ~H"""
    <TuistWeb.Docs.Components.layout
      current_slug={"/#{@locale}"}
      tab={:guides}
      headings={@headings}
      markdown=""
      locale={@locale}
    >
      <div id="docs-overview">
        <%!-- Hero --%>
        <section data-part="hero">
          <h1>{dgettext("docs", "Your mobile platform team, as a service")}</h1>
          <p>
            {dgettext(
              "docs",
              "Let us be your virtual companion that continuously optimizes and observes your setup, so you can focus on shipping."
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
          <h1 id="learn-more">{dgettext("docs", "Learn more about what Tuist offers")}</h1>
          <p>
            {dgettext(
              "docs",
              "Learn how to generate projects, automate your workflows, and scale your app development efficiently with Tuist."
            )}
          </p>
        </section>

        <%!-- Builds --%>
        <section data-part="feature-section">
          <h2 id="builds">{dgettext("docs", "Builds")}</h2>
          <p>
            {dgettext(
              "docs",
              "Skip the manual steps, auto-generate projects, speeds up builds, and explore insights with built-in analytics."
            )}
          </p>
          <div data-part="feature-cards">
            <.link
              patch={docs_path("/#{@locale}/guides/features/cache/module-cache")}
              data-part="feature-card"
            >
              <div data-part="feature-card-image">
                <span data-part="feature-card-icon"><.database /></span>
                <span data-part="feature-card-title">{dgettext("docs", "Cache")}</span>
              </div>
              <div data-part="feature-card-body">
                <p>
                  {dgettext(
                    "docs",
                    "Speeds up builds by caching compiled modules, cutting down load times in both local development and CI workflows."
                  )}
                </p>
              </div>
            </.link>
            <.link
              patch={docs_path("/#{@locale}/guides/features/build-insights")}
              data-part="feature-card"
            >
              <div data-part="feature-card-image">
                <span data-part="feature-card-icon"><.search /></span>
                <span data-part="feature-card-title">{dgettext("docs", "Insights")}</span>
              </div>
              <div data-part="feature-card-body">
                <p>
                  {dgettext(
                    "docs",
                    "Monitor build performance across your CI infrastructure to catch slowdowns before they impact development."
                  )}
                </p>
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
              "Run only impacted tests based on your changes, faster feedback loops, less waiting, both locally and on CI."
            )}
          </p>
          <div data-part="feature-cards">
            <.link
              patch={docs_path("/#{@locale}/guides/features/selective-testing")}
              data-part="feature-card"
            >
              <div data-part="feature-card-image">
                <span data-part="feature-card-icon"><.subtask /></span>
                <span data-part="feature-card-title">{dgettext("docs", "Selective Testing")}</span>
              </div>
              <div data-part="feature-card-body">
                <p>
                  {dgettext(
                    "docs",
                    "Run only the tests that matter by detecting changes since your last successful run, cutting down test times both locally and on CI."
                  )}
                </p>
              </div>
            </.link>
            <.link
              patch={docs_path("/#{@locale}/guides/features/test-insights/flaky-tests")}
              data-part="feature-card"
            >
              <div data-part="feature-card-image">
                <span data-part="feature-card-icon"><.progress_x /></span>
                <span data-part="feature-card-title">{dgettext("docs", "Flaky Tests")}</span>
              </div>
              <div data-part="feature-card-body">
                <p>
                  {dgettext(
                    "docs",
                    "Automatically detect flaky tests that fail without code changes and save time spent investigating false failures."
                  )}
                </p>
              </div>
            </.link>
            <.link
              patch={docs_path("/#{@locale}/guides/features/test-insights")}
              data-part="feature-card"
            >
              <div data-part="feature-card-image">
                <span data-part="feature-card-icon"><.search /></span>
                <span data-part="feature-card-title">{dgettext("docs", "Insights")}</span>
              </div>
              <div data-part="feature-card-body">
                <p>
                  {dgettext(
                    "docs",
                    "Track test performance, catch slow tests early, and debug CI failures through real-time logs."
                  )}
                </p>
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
              "From code to feedback in minutes. Instant previews and AI-powered testing close the loop between building and validating."
            )}
          </p>
          <div data-part="feature-cards">
            <.link patch={docs_path("/#{@locale}/guides/features/previews")} data-part="feature-card">
              <div data-part="feature-card-image">
                <span data-part="feature-card-icon"><.devices /></span>
                <span data-part="feature-card-title">{dgettext("docs", "Previews")}</span>
              </div>
              <div data-part="feature-card-body">
                <p>
                  {dgettext(
                    "docs",
                    "Share your app instantly with a URL, no TestFlight or setup needed, so others can run it on their device or simulator in seconds."
                  )}
                </p>
              </div>
            </.link>
            <div data-part="feature-card">
              <div data-part="feature-card-image">
                <span data-part="feature-card-icon"><.checkup_list /></span>
                <span data-part="feature-card-title">{dgettext("docs", "Agentic QA")}</span>
              </div>
              <div data-part="feature-card-body">
                <p>
                  {dgettext(
                    "docs",
                    "Mention @tuist on your PR and an AI agent tests your app for you, exploring edge cases and reporting issues with screenshots and logs."
                  )}
                </p>
              </div>
            </div>
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
      markdown={@page.markdown}
      locale={@locale}
    >
      <article id={"docs-body-#{@page.slug}"} class="tuist-docs" data-prose phx-hook="DocsContent">
        {raw(@page.body)}
      </article>
    </TuistWeb.Docs.Components.layout>
    """
  end

  def handle_event("copy-page-markdown", _params, %{assigns: %{page: page}} = socket) do
    {:noreply, push_event(socket, "docs:copy-to-clipboard", %{text: page.markdown})}
  end

  def handle_event("copy-page-markdown", _params, socket) do
    {:noreply, socket}
  end

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

  defp build_path(%{"path" => path_parts}, locale), do: Paths.slug(locale, path_parts)
  defp build_path(_params, locale), do: Paths.slug(locale)

  defp docs_path(slug), do: Paths.public_path_from_slug(slug)
end
