defmodule TuistWeb.MixBuildLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.BuildTimeline
  import TuistWeb.Components.EmptyTabStateBackground
  import TuistWeb.Runs.ProjectWithTags
  import TuistWeb.Runs.RanByBadge

  alias Tuist.Mix
  alias Tuist.Projects
  alias TuistWeb.BuildTimelineLoader
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  @breakdown_page_size 20

  @impl true
  def mount(%{"build_id" => build_id}, _session, %{assigns: %{selected_project: project}} = socket) do
    run =
      case Mix.get_build(build_id, project.id) do
        {:ok, run} ->
          run

        {:error, :not_found} ->
          raise NotFoundError, dgettext("dashboard_builds", "Build not found.")
      end

    run = Tuist.Repo.preload(run, ran_by_account: [])

    slug = Projects.get_project_slug_from_id(project.id)
    diagnostics = Mix.list_diagnostics(run)

    errors = Enum.filter(diagnostics, &(&1.severity == "error"))
    warnings = Enum.filter(diagnostics, &(&1.severity == "warning"))

    {:ok,
     socket
     |> assign(:run, run)
     |> assign(:diagnostics, diagnostics)
     |> assign(:errors, errors)
     |> assign(:warnings, warnings)
     |> assign(:errors_grouped_by_path, group_by_path(errors))
     |> assign(:warnings_grouped_by_path, group_by_path(warnings))
     |> assign(:selected_project, Tuist.Repo.preload(project, :vcs_connection))
     |> assign(:files?, Mix.compiled_files?(run))
     |> assign(:selected_tab, "overview")
     |> assign(:head_title, "#{dgettext("dashboard_builds", "Mix Build")} · #{slug} · Tuist")
     |> assign(
       OpenGraph.project_image_assigns(project,
         title: dgettext("dashboard_builds", "mix compile"),
         subtitle: Enum.join(Enum.reject([run.mix_env, run.git_branch], &(&1 in [nil, ""])), " · "),
         badge: run.status |> to_string() |> String.capitalize(),
         fallback: "build-runs"
       )
     )}
  end

  @impl true
  def handle_params(params, uri, socket) do
    search = params["breakdown-search"] || ""
    sort_by = params["breakdown-sort-by"] || "compile-duration"
    page = positive_integer(params["breakdown-page"])
    tab = if params["breakdown-tab"] == "module", do: "module", else: "file"

    socket = BuildTimelineLoader.select_tab(socket, Map.get(params, "tab", "overview"), socket.assigns.run)

    # Only Overview shows the breakdown, and on a large build it is the
    # page's most expensive query.
    %{rows: rows, total: total} =
      if socket.assigns.selected_tab == "overview",
        do:
          Mix.compiled_files_page(socket.assigns.run,
            by: if(tab == "module", do: :module, else: :file),
            search: search,
            sort_by: sort_by,
            page: page,
            page_size: @breakdown_page_size
          ),
        else: %{rows: [], total: 0}

    {:noreply,
     socket
     |> BuildTimelineLoader.assign_timeline(socket.assigns.selected_tab, socket.assigns.run)
     |> assign(:uri, URI.parse(uri))
     |> assign(:selected_breakdown_tab, tab)
     |> assign(:breakdown_search, search)
     |> assign(:breakdown_sort_by, sort_by)
     |> assign(:breakdown_page, page)
     |> assign(:breakdown_page_count, max(ceil(total / @breakdown_page_size), 1))
     |> assign(:breakdown_rows, rows)}
  end

  @impl true
  def handle_event("search-breakdown", %{"search" => search}, socket) do
    query =
      socket.assigns.uri.query
      |> Query.put("breakdown-search", search)
      |> Query.put("breakdown-page", "1")

    {:noreply, push_patch(socket, to: "#{socket.assigns.uri.path}?#{query}", replace: true)}
  end

  def handle_event("load-timeline", params, socket) do
    BuildTimelineLoader.handle_event("load-timeline", params, socket)
  end

  # Query parameters are the visitor's to type: anything that is not a
  # positive number is the first page.
  defp positive_integer(value) when is_binary(value) do
    case Integer.parse(value) do
      {number, ""} when number > 0 -> number
      _ -> 1
    end
  end

  defp positive_integer(_value), do: 1

  # Same grouping the Xcode build page uses: one collapsible card per file.
  defp group_by_path(diagnostics) do
    diagnostics |> Enum.group_by(& &1.file) |> Enum.sort_by(fn {path, issues} -> {-length(issues), path} end)
  end

  attr(:issues, :list, required: true)
  attr(:path, :string, required: true)
  attr(:run, :map, required: true)
  attr(:project, :map, required: true)
  attr(:type, :string, required: true, values: ~w(error warning))

  # Mirrors TuistWeb.BuildRunLive.issue_card/1 so the two pages share markup and CSS.
  def issue_card(assigns) do
    ~H"""
    <div
      id={"#{@type}-#{String.replace(@path, "/", "-")}-issue-collapsible"}
      phx-hook="NooraCollapsible"
      data-part="collapsible"
      data-state="closed"
      data-type={@type}
      class="issue-card"
    >
      <div data-part="root">
        <div data-part="trigger">
          <div data-part="header">
            <div data-part="icon">
              <%= if @type == "error" do %>
                <.alert_circle />
              <% else %>
                <.alert_hexagon />
              <% end %>
            </div>
            <div data-part="title-and-subtitle">
              <h3 data-part="title">
                {issue_title(@path, @type)}
              </h3>
              <span :if={issue_modules(@issues) != ""} data-part="subtitle">
                {issue_modules(@issues)}
              </span>
            </div>
            <.badge
              label={format_number(Enum.count(@issues))}
              color={if @type == "error", do: "destructive", else: "warning"}
              style="light-fill"
              size="large"
            />
          </div>
          <.neutral_button data-part="closed-collapsible-button" variant="secondary" size="medium">
            <.chevron_down />
          </.neutral_button>
          <.neutral_button data-part="open-collapsible-button" variant="secondary" size="medium">
            <.chevron_up />
          </.neutral_button>
        </div>
        <div data-part="content" data-state="closed">
          <%= for issue <- @issues do %>
            <span data-part="issue">
              {issue_message(issue, @run, @project)}
            </span>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  defp issue_title("", "error"), do: dgettext("dashboard_builds", "Compilation failed")
  defp issue_title("", "warning"), do: dgettext("dashboard_builds", "Compilation warning")
  defp issue_title(path, "error"), do: dgettext("dashboard_builds", "Failed compiling Elixir file %{path}", path: path)

  defp issue_title(path, "warning"),
    do: dgettext("dashboard_builds", "Warning when compiling Elixir file %{path}", path: path)

  defp issue_modules(issues) do
    issues |> Enum.map(& &1.module) |> Enum.reject(&(&1 == "")) |> Enum.uniq() |> Enum.join(" • ")
  end

  defp issue_message(%{file: file} = issue, run, project) when file != "" do
    location = if issue.line, do: "#{file}#L#{issue.line}", else: file

    if github_connected?(project) and run.git_commit_sha != "" do
      href =
        "https://github.com/#{project.vcs_connection.repository_full_handle}/blob/#{run.git_commit_sha}/#{location}"

      # The message and path come from the client, so escape both before
      # building the link.
      raw(
        dgettext("dashboard_builds", "%{message} in %{link}",
          message: escape(issue.message),
          link: ~s(<a href="#{escape(href)}" target="_blank">#{escape(location)}</a>)
        )
      )
    else
      dgettext("dashboard_builds", "%{message} in %{link}", message: issue.message, link: location)
    end
  end

  defp issue_message(issue, _run, _project), do: issue.message

  defp escape(value), do: value |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  defp github_connected?(%{vcs_connection: %{provider: :github}}), do: true
  defp github_connected?(_project), do: false

  @doc false
  def breakdown_sort_label("name"), do: dgettext("dashboard_builds", "Name")
  def breakdown_sort_label("dependents"), do: dgettext("dashboard_builds", "Compile-time dependents")
  def breakdown_sort_label("dependencies"), do: dgettext("dashboard_builds", "Compile-time dependencies")
  def breakdown_sort_label(_), do: dgettext("dashboard_builds", "Compilation duration")

  @doc false
  def breakdown_sort_patch(uri, sort_by) do
    "?#{uri.query |> Query.put("breakdown-sort-by", sort_by) |> Query.put("breakdown-page", "1")}"
  end

  @doc false
  def format_ms(ms) when ms < 1000, do: "#{ms}ms"
  def format_ms(ms), do: "#{Float.round(ms / 1000, 1)}s"

  @doc false
  def files_label(0), do: "–"
  def files_label(count), do: dngettext("dashboard_builds", "%{count} file", "%{count} files", count, count: count)

  @doc false
  def url?(value) when is_binary(value) do
    case URI.parse(value) do
      %URI{scheme: scheme, host: host} when scheme in ["http", "https"] and is_binary(host) and host != "" -> true
      _ -> false
    end
  end

  def url?(_), do: false
end
