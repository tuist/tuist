defmodule TuistWeb.DocsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Docs
  alias Tuist.Docs.Redirects
  alias TuistWeb.Errors.NotFoundError

  def mount(_params, _session, socket) do
    socket =
      attach_hook(socket, :assign_current_path, :handle_params, fn _params, url, socket ->
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
     |> assign(:head_title, "Docs · Tuist")
     |> assign(:head_description, "Learn how to use Tuist to make mobile your competitive advantage.")}
  end

  defp handle_show(params, socket) do
    path = build_path(params)

    case Redirects.redirect_path(path) do
      nil ->
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
             |> assign(:head_title, head_title)
             |> assign(:head_description, page.description)}
        end

      destination ->
        query_string = URI.parse(socket.assigns.current_path).query
        target = if query_string, do: "/docs#{destination}?#{query_string}", else: "/docs#{destination}"
        {:noreply, redirect(socket, to: target)}
    end
  end

  def render(%{view: :overview} = assigns) do
    ~H"""
    <TuistWeb.Docs.Components.layout current_slug="/en" tab={:guides} headings={[]} markdown="">
      <div id="docs-overview">
        <%!-- Hero --%>
        <section data-part="hero">
          <h1>Make mobile your competitive advantage</h1>
          <p>
            Tuist helps teams scale app development and ship faster &mdash; transforming the complexity of large codebases into
            a smooth, productive experience that grows with your team.
          </p>
        </section>

        <%!-- Hero cards --%>
        <section data-part="hero-cards">
          <div data-part="hero-card">
            <div data-part="hero-card-bg"></div>
            <h3>Install Tuist CLI</h3>
            <div data-part="terminal-group" id="docs-install-terminal" phx-hook="DocsInstallTabs">
              <div data-part="terminal">
                <div data-part="terminal-header">
                  <div data-part="terminal-tabs">
                    <span data-part="terminal-tab" data-selected>mise</span>
                    <span data-part="terminal-tab">homebrew</span>
                  </div>
                  <button data-part="terminal-copy" aria-label="Copy command">
                    <.copy />
                  </button>
                </div>
                <div data-part="terminal-body">
                  <code>mise install tuist</code>
                </div>
              </div>
              <p data-part="hero-card-hint">
                or follow the instructions to
                <.link navigate="/docs/en/guides/install-tuist" data-part="hero-card-link">
                  install specific version of tuist
                </.link>
              </p>
            </div>
          </div>
          <.link navigate="/tuist/tuist" data-part="hero-card" data-variant="dashboard">
            <div data-part="hero-card-bg"></div>
            <h3>Explore dashboard</h3>
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
          <h1>Learn more about what Tuist offers</h1>
          <p>
            Learn how to generate projects, automate your workflows, and scale your app development efficiently with Tuist.
          </p>
        </section>

        <%!-- Builds --%>
        <section data-part="feature-section">
          <h2>Builds</h2>
          <p>
            Skip the manual steps, auto-generate projects, speeds up builds, and explore insights with built-in analytics.
          </p>
          <div data-part="feature-cards">
            <.link navigate="/docs/en/guides/features/cache/module-cache" data-part="feature-card">
              <div data-part="feature-card-image">
                <span data-part="feature-card-icon"><.database /></span>
                <span data-part="feature-card-title">Cache</span>
              </div>
              <div data-part="feature-card-body">
                <p>
                  Speeds up builds by caching compiled modules, cutting down load times in both local development and CI workflows.
                </p>
              </div>
            </.link>
            <.link navigate="/docs/en/guides/features/insights" data-part="feature-card">
              <div data-part="feature-card-image">
                <span data-part="feature-card-icon"><.search /></span>
                <span data-part="feature-card-title">Insights</span>
              </div>
              <div data-part="feature-card-body">
                <p>
                  Monitor build performance across your CI infrastructure to catch slowdowns before they impact development.
                </p>
              </div>
            </.link>
          </div>
        </section>

        <%!-- Tests --%>
        <section data-part="feature-section">
          <h2>Tests</h2>
          <p>
            Run only impacted tests based on your changes, faster feedback loops, less waiting, both locally and on CI.
          </p>
          <div data-part="feature-cards">
            <.link
              navigate="/docs/en/guides/features/selective-testing"
              data-part="feature-card"
            >
              <div data-part="feature-card-image">
                <span data-part="feature-card-icon"><.subtask /></span>
                <span data-part="feature-card-title">Selective Testing</span>
              </div>
              <div data-part="feature-card-body">
                <p>
                  Run only the tests that matter by detecting changes since your last successful run, cutting down test times both locally and on CI.
                </p>
              </div>
            </.link>
            <.link navigate="/docs/en/guides/features/test-insights/flaky-tests" data-part="feature-card">
              <div data-part="feature-card-image">
                <span data-part="feature-card-icon"><.progress_x /></span>
                <span data-part="feature-card-title">Flaky Tests</span>
              </div>
              <div data-part="feature-card-body">
                <p>
                  Automatically detect flaky tests that fail without code changes and save time spent investigating false failures.
                </p>
              </div>
            </.link>
            <.link navigate="/docs/en/guides/features/test-insights" data-part="feature-card">
              <div data-part="feature-card-image">
                <span data-part="feature-card-icon"><.search /></span>
                <span data-part="feature-card-title">Insights</span>
              </div>
              <div data-part="feature-card-body">
                <p>
                  Track test performance, catch slow tests early, and debug CI failures through real-time logs.
                </p>
              </div>
            </.link>
          </div>
        </section>

        <%!-- Artifacts --%>
        <section data-part="feature-section">
          <h2>Artifacts</h2>
          <p>
            From code to feedback in minutes. Instant previews and AI-powered testing close the loop between building and validating.
          </p>
          <div data-part="feature-cards">
            <.link navigate="/docs/en/guides/features/previews" data-part="feature-card">
              <div data-part="feature-card-image">
                <span data-part="feature-card-icon"><.devices /></span>
                <span data-part="feature-card-title">Previews</span>
              </div>
              <div data-part="feature-card-body">
                <p>
                  Share your app instantly with a URL, no TestFlight or setup needed, so others can run it on their device or simulator in seconds.
                </p>
              </div>
            </.link>
            <.link navigate="/docs/en/guides/features/qa" data-part="feature-card">
              <div data-part="feature-card-image">
                <span data-part="feature-card-icon"><.checkup_list /></span>
                <span data-part="feature-card-title">Agentic QA</span>
              </div>
              <div data-part="feature-card-body">
                <p>
                  Mention @tuist on your PR and an AI agent tests your app for you, exploring edge cases and reporting issues with screenshots and logs.
                </p>
              </div>
            </.link>
          </div>
        </section>

        <%!-- See Tuist in action --%>
        <section data-part="section-intro">
          <h1>See Tuist in action</h1>
          <p>
            Learn from real implementations and get inspired by what's possible when your toolchain just works.
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
          <h1>Open source and community</h1>
          <p>
            Connect with thousands of developers who are shipping better apps with Tuist. Get help, share wins, and shape
            the future of app development tooling.
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
            <p>Contribute or report issues to our open source repository.</p>
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
            <p>Chat with the Tuist community in real-time.</p>
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
            <p>Share your ideas, report issues, and discuss with other community members.</p>
          </a>
          <a
            href="https://videos.tuist.dev"
            target="_blank"
            rel="noopener noreferrer"
            data-part="community-card"
          >
            <div data-part="community-card-header">
              <.player_play />
              <span>Videos</span>
            </div>
            <p>Learn from videos from the Tuist team and the community.</p>
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
            <p>Follow us on Bluesky to stay up to date with our work.</p>
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
            <p>Follow us on Mastodon to stay up to date with our work.</p>
          </a>
          <a
            href="https://www.linkedin.com/company/tuistio"
            target="_blank"
            rel="noopener noreferrer"
            data-part="community-card"
          >
            <div data-part="community-card-header">
              <.icon name="external_link" />
              <span>LinkedIn</span>
            </div>
            <p>Follow Tuist on LinkedIn for news and updates.</p>
          </a>
        </section>
      </div>
    </TuistWeb.Docs.Components.layout>
    """
  end

  def render(%{view: :show} = assigns) do
    ~H"""
    <TuistWeb.Docs.Components.layout
      current_slug={@page.slug}
      tab={Tuist.Docs.Sidebar.tab_for_slug(@page.slug)}
      headings={@page.headings}
      markdown={@page.markdown}
    >
      <article id={"docs-body-#{@page.slug}"} data-part="docs-body" data-prose phx-hook="DocsContent">
        {raw(@page.body)}
      </article>
    </TuistWeb.Docs.Components.layout>
    """
  end

  def handle_event("copy-page-markdown", _params, socket) do
    {:noreply, push_event(socket, "docs:copy-to-clipboard", %{text: socket.assigns.page.markdown})}
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

  defp build_path(%{"path" => path_parts}), do: "/en/" <> Enum.join(path_parts, "/")
  defp build_path(_params), do: "/en"
end
