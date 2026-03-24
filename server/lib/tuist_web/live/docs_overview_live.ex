defmodule TuistWeb.DocsOverviewLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  alias Tuist.Docs.Paths

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
    socket =
      attach_hook(socket, :assign_current_path, :handle_params, fn _params, url, socket ->
        uri = URI.parse(url)
        current_path = if(is_nil(uri.query), do: uri.path, else: "#{uri.path}?#{uri.query}")
        {:cont, assign(socket, current_path: current_path)}
      end)

    videos = fetch_latest_videos()
    {:ok, assign(socket, :videos, videos)}
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

  def handle_params(_params, _url, socket) do
    {:noreply,
     socket
     |> assign(:head_title, "Docs · Tuist")
     |> assign(:head_description, "Learn how to use Tuist to make mobile your competitive advantage.")}
  end

  def render(assigns) do
    assigns =
      assigns
      |> assign(:install_path, docs_path("/en/guides/install-tuist"))
      |> assign(:copy_check_icon, @copy_check_icon)
      |> assign(:headings, @overview_headings)

    ~H"""
    <TuistWeb.Docs.Components.layout current_slug="/en" tab={:guides} headings={@headings} markdown="">
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
          <div
            id="docs-install-card"
            data-part="hero-card"
            data-clickable
            phx-click={JS.patch(@install_path)}
            phx-key="Enter"
            role="link"
            tabindex="0"
            aria-label="Install Tuist CLI"
          >
            <div data-part="hero-card-bg"></div>
            <h3>Install Tuist CLI</h3>
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
                    aria-label="Copy command"
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
                or follow the instructions to
                <.link patch={@install_path} data-part="hero-card-link">
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
          <h1 id="learn-more">Learn more about what Tuist offers</h1>
          <p>
            Learn how to generate projects, automate your workflows, and scale your app development efficiently with Tuist.
          </p>
        </section>

        <%!-- Builds --%>
        <section data-part="feature-section">
          <h2 id="builds">Builds</h2>
          <p>
            Skip the manual steps, auto-generate projects, speeds up builds, and explore insights with built-in analytics.
          </p>
          <div data-part="feature-cards">
            <.link
              patch={docs_path("/en/guides/features/cache/module-cache")}
              data-part="feature-card"
            >
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
            <.link
              patch={docs_path("/en/guides/features/builds/insights")}
              data-part="feature-card"
            >
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
          <h2 id="tests">Tests</h2>
          <p>
            Run only impacted tests based on your changes, faster feedback loops, less waiting, both locally and on CI.
          </p>
          <div data-part="feature-cards">
            <.link
              patch={docs_path("/en/guides/features/tests/selective-testing")}
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
            <.link
              patch={docs_path("/en/guides/features/tests/flaky-tests")}
              data-part="feature-card"
            >
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
            <.link patch={docs_path("/en/guides/features/test-insights")} data-part="feature-card">
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
          <h2 id="artifacts">Artifacts</h2>
          <p>
            From code to feedback in minutes. Instant previews and AI-powered testing close the loop between building and validating.
          </p>
          <div data-part="feature-cards">
            <.link patch={docs_path("/en/guides/features/previews")} data-part="feature-card">
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
            <div data-part="feature-card">
              <div data-part="feature-card-image">
                <span data-part="feature-card-icon"><.checkup_list /></span>
                <span data-part="feature-card-title">Agentic QA</span>
              </div>
              <div data-part="feature-card-body">
                <p>
                  Mention @tuist on your PR and an AI agent tests your app for you, exploring edge cases and reporting issues with screenshots and logs.
                </p>
              </div>
            </div>
          </div>
        </section>

        <%!-- See Tuist in action --%>
        <section data-part="section-intro">
          <h1 id="see-tuist-in-action">See Tuist in action</h1>
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
          <h1 id="open-source-and-community">Open source and community</h1>
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
              <.brand_linkedin />
              <span>LinkedIn</span>
            </div>
            <p>Follow Tuist on LinkedIn for news and updates.</p>
          </a>
        </section>
      </div>
    </TuistWeb.Docs.Components.layout>
    """
  end

  defp docs_path(slug), do: Paths.public_path_from_slug(slug)
end
