defmodule TuistWeb.DocsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Docs.MarkdownComponents, warn: false

  alias Tuist.Docs
  alias Tuist.Docs.Paths
  alias TuistWeb.Errors.NotFoundError

  @overview_headings [
    %{id: "start-with-your-setup", text: "Start with your setup", level: 2},
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

    {:noreply,
     socket
     |> assign(:view, :overview)
     |> assign(:videos, videos)
     |> assign(:markdown, overview_markdown(socket.assigns.locale, videos))
     |> assign(:page_title, "Docs · Tuist")
     |> assign(:head_title, "Docs · Tuist")
     |> assign(
       :head_description,
       "Build, test, and run Xcode and Gradle projects faster with Tuist's shared build infrastructure."
     )}
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

        og_image_filename = Tuist.Docs.OgImage.slug_to_filename(path)
        og_image_path = "/docs/images/og/generated/#{og_image_filename}"

        {:noreply,
         socket
         |> assign(:view, :show)
         |> assign(:page, page)
         |> assign(:markdown, page.markdown)
         |> assign(:requested_slug, path)
         |> assign(:page_title, head_title)
         |> assign(:head_title, head_title)
         |> assign(:head_description, page.description)
         |> assign(:head_image, Tuist.Environment.app_url(path: og_image_path))
         |> assign(:head_twitter_card, "summary_large_image")}
    end
  end

  def render(%{view: :overview} = assigns) do
    assigns =
      assigns
      |> assign(:install_path, docs_path("/#{assigns.locale}/guides/install-tuist"))
      |> assign(:xcode_path, docs_path("/#{assigns.locale}/guides/features/cache/xcode-cache"))
      |> assign(:gradle_path, docs_path("/#{assigns.locale}/guides/install-gradle-plugin"))
      |> assign(:runners_path, docs_path("/#{assigns.locale}/guides/features/runners/getting-started"))
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
              "Connect local development, continuous integration, and coding agents through shared caching, actionable insights, test optimization, and managed runners for Xcode and Gradle."
            )}
          </p>
        </section>

        <%!-- Starting paths --%>
        <section data-part="start">
          <div data-part="start-heading">
            <h2 id="start-with-your-setup">{dgettext("docs", "Start with your setup")}</h2>
            <p>
              {dgettext(
                "docs",
                "Choose the path that matches how your team builds today. You can adopt Tuist without changing how your projects are generated."
              )}
            </p>
          </div>

          <div data-part="journey-cards">
            <.link id="docs-xcode-path" patch={@xcode_path} data-part="feature-card">
              <div data-part="image">
                <span data-part="icon"><.brand_apple /></span>
                <span data-part="title">{dgettext("docs", "Xcode project")}</span>
              </div>
              <div data-part="body">
                <p>
                  {dgettext(
                    "docs",
                    "Add compilation caching and insights without adopting project generation."
                  )}
                </p>
                <span data-part="journey-link">
                  {dgettext("docs", "Explore Xcode")}
                  <.arrow_right />
                </span>
              </div>
            </.link>

            <.link id="docs-gradle-path" patch={@gradle_path} data-part="feature-card">
              <div data-part="image">
                <span data-part="icon"><.settings /></span>
                <span data-part="title">{dgettext("docs", "Gradle project")}</span>
              </div>
              <div data-part="body">
                <p>
                  {dgettext(
                    "docs",
                    "Connect remote caching, build insights, and test insights to your existing project."
                  )}
                </p>
                <span data-part="journey-link">
                  {dgettext("docs", "Start with Gradle")}
                  <.arrow_right />
                </span>
              </div>
            </.link>

            <.link id="docs-runners-path" patch={@runners_path} data-part="feature-card">
              <div data-part="image">
                <span data-part="icon"><.server /></span>
                <span data-part="title">{dgettext("docs", "CI runners")}</span>
              </div>
              <div data-part="body">
                <p>
                  {dgettext(
                    "docs",
                    "Run continuous integration workflows with GitHub Actions on managed macOS and Linux infrastructure next to your cache."
                  )}
                </p>
                <span data-part="journey-link">
                  {dgettext("docs", "Start with runners")}
                  <.arrow_right />
                </span>
              </div>
            </.link>
          </div>

          <div data-part="secondary-actions">
            <.link patch={@install_path}>
              {dgettext("docs", "Install Tuist")}
              <.arrow_right />
            </.link>
            <.link navigate="/tuist/tuist">
              {dgettext("docs", "Explore dashboard")}
              <.arrow_right />
            </.link>
          </div>
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
                    "Reuse build artifacts across Xcode and Gradle so work completed in one environment speeds up every other environment."
                  )}
                </p>
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
    xcode_path = docs_path("/#{locale}/guides/features/cache/xcode-cache")
    gradle_path = docs_path("/#{locale}/guides/install-gradle-plugin")
    runners_path = docs_path("/#{locale}/guides/features/runners/getting-started")

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
          "Connect local development, continuous integration, and coding agents through shared caching, actionable insights, test optimization, and managed runners for Xcode and Gradle."
        ),
        "",
        "## " <> dgettext("docs", "Start with your setup"),
        "",
        dgettext(
          "docs",
          "Choose the path that matches how your team builds today. You can adopt Tuist without changing how your projects are generated."
        ),
        "",
        "- #{markdown_link(dgettext("docs", "Xcode project"), xcode_path)}: " <>
          dgettext(
            "docs",
            "Add compilation caching and insights without adopting project generation."
          ),
        "- #{markdown_link(dgettext("docs", "Gradle project"), gradle_path)}: " <>
          dgettext(
            "docs",
            "Connect remote caching, build insights, and test insights to your existing project."
          ),
        "- #{markdown_link(dgettext("docs", "CI runners"), runners_path)}: " <>
          dgettext(
            "docs",
            "Run continuous integration workflows with GitHub Actions on managed macOS and Linux infrastructure next to your cache."
          ),
        "",
        markdown_link(dgettext("docs", "Install Tuist"), install_path),
        markdown_link(dgettext("docs", "Explore dashboard"), "/tuist/tuist"),
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
            "Reuse build artifacts across Xcode and Gradle so work completed in one environment speeds up every other environment."
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
