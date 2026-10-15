defmodule TuistWeb.MixBuildLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.BuildTimeline
  import TuistWeb.Components.EmptyTabStateBackground
  import TuistWeb.Components.ErrorCardSection
  import TuistWeb.Components.Skeleton
  import TuistWeb.PercentileDropdownWidget
  import TuistWeb.Runs.ProjectWithTags
  import TuistWeb.Runs.RanByBadge

  alias Phoenix.LiveView.AsyncResult
  alias Tuist.Mix
  alias Tuist.Mix.Cache
  alias Tuist.Projects
  alias Tuist.ReapiCache
  alias Tuist.Utilities.ByteFormatter
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.BuildRunLive
  alias TuistWeb.BuildTimelineLoader
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.ReapiCacheOutputs
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
     |> assign(:cache_task_outputs, AsyncResult.ok([]))
     |> assign(:cache_expanded_entries, MapSet.new())
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
     |> assign(:cache_search, params["cache-search"] || "")
     |> assign(:cache_outcome, cache_outcome(params["cache-outcome"]))
     |> assign(:cache_page, min(positive_integer(params["cache-page"]), 10_000))
     |> assign(:selected_cache_tab, if(params["cache-tab"] == "cas-outputs", do: "cas-outputs", else: "cacheable-tasks"))
     |> assign(:cache_sort_order, if(params["cache-sort-order"] == "asc", do: :asc, else: :desc))
     |> assign(:cache_output_params, ReapiCacheOutputs.params(socket.assigns.run.id, params))
     |> assign(:cache_read_latency_type, cache_percentile(params["cache-read-latency-type"]))
     |> assign(:cache_write_latency_type, cache_percentile(params["cache-write-latency-type"]))
     |> assign(:selected_breakdown_tab, tab)
     |> assign(:breakdown_search, search)
     |> assign(:breakdown_sort_by, sort_by)
     |> assign(:breakdown_page, page)
     |> assign(:breakdown_page_count, max(ceil(total / @breakdown_page_size), 1))
     |> assign(:breakdown_rows, rows)
     |> assign_cache()}
  end

  @impl true
  def handle_event("search-breakdown", %{"search" => search}, socket) do
    query =
      socket.assigns.uri.query
      |> Query.put("breakdown-search", search)
      |> Query.put("breakdown-page", "1")

    {:noreply, push_patch(socket, to: "#{socket.assigns.uri.path}?#{query}", replace: true)}
  end

  def handle_event("search-cache", %{"search" => search}, socket) do
    query = socket.assigns.uri.query |> Query.put("cache-search", search) |> Query.put("cache-page", "1")
    {:noreply, push_patch(socket, to: "#{socket.assigns.uri.path}?#{query}", replace: true)}
  end

  def handle_event("search-cache-outputs", %{"search" => search}, socket) do
    query =
      socket.assigns.uri.query
      |> Query.put("cache-output-search", search)
      |> Query.drop("cache-output-key")
      |> Query.put("cache-output-page", "1")

    {:noreply, push_patch(socket, to: "#{socket.assigns.uri.path}?#{query}", replace: true)}
  end

  def handle_event("toggle-cache-entry", %{"dependency" => dependency}, socket) do
    events = socket.assigns[:cache_events]
    rows = if events && events.ok? && !events.failed, do: events.result.rows, else: []

    if Enum.any?(rows, &(&1.dependency == dependency)) do
      entries = socket.assigns.cache_expanded_entries

      entries =
        if MapSet.member?(entries, dependency),
          do: MapSet.delete(entries, dependency),
          else: MapSet.put(entries, dependency)

      {:noreply, socket |> assign(:cache_expanded_entries, entries) |> assign_task_outputs(entries)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("select_cache_read_latency", %{"type" => type}, socket) when type in ~w(avg p50 p90 p99),
    do: select_cache_percentile(socket, "cache-read-latency-type", type)

  def handle_event("select_cache_write_latency", %{"type" => type}, socket) when type in ~w(avg p50 p90 p99),
    do: select_cache_percentile(socket, "cache-write-latency-type", type)

  def handle_event("load-timeline", params, socket) do
    BuildTimelineLoader.handle_event("load-timeline", params, socket)
  end

  defp select_cache_percentile(socket, parameter, type) do
    query = Query.put(socket.assigns.uri.query, parameter, type)
    {:noreply, push_patch(socket, to: "#{socket.assigns.uri.path}?#{query}", replace: true)}
  end

  defp assign_cache(%{assigns: %{selected_tab: "cache", run: run}} = socket) do
    project_id = run.project_id
    build_id = run.id
    identity = {project_id, build_id}

    opts = [
      search: socket.assigns.cache_search,
      outcome: socket.assigns.cache_outcome,
      page: socket.assigns.cache_page,
      sort_order: socket.assigns.cache_sort_order
    ]

    events_key = {identity, opts}

    socket =
      if socket.assigns[:cache_summary_key] == identity and !socket.assigns.cache_summary.failed do
        socket
      else
        socket
        |> assign(:cache_summary_key, identity)
        |> assign_async(:cache_summary, fn -> {:ok, %{cache_summary: Cache.build_summary(project_id, build_id)}} end)
      end

    socket =
      if socket.assigns[:cache_transport_key] == identity and !socket.assigns.cache_transport.failed do
        socket
      else
        socket
        |> assign(:cache_transport_key, identity)
        |> assign_async(:cache_transport, fn ->
          {:ok, %{cache_transport: ReapiCache.invocation_detail_metrics(project_id, build_id, client_kind: "mix")}}
        end)
      end

    cond do
      socket.assigns.selected_cache_tab == "cas-outputs" ->
        socket |> cancel_async(:cache_events) |> cancel_async(:cache_task_outputs) |> assign_outputs()

      socket.assigns[:cache_events_key] == events_key and !socket.assigns.cache_events.failed ->
        socket

      true ->
        socket
        |> assign(:cache_expanded_entries, MapSet.new())
        |> cancel_async(:cache_outputs)
        |> cancel_async(:cache_task_outputs)
        |> assign(:cache_task_outputs, AsyncResult.ok([]))
        |> assign(:cache_events_key, events_key)
        |> assign_async(:cache_events, fn -> {:ok, %{cache_events: Cache.build_events(project_id, build_id, opts)}} end)
    end
  end

  defp assign_cache(socket),
    do:
      socket
      |> cancel_async(:cache_summary)
      |> cancel_async(:cache_events)
      |> cancel_async(:cache_transport)
      |> cancel_async(:cache_outputs)
      |> cancel_async(:cache_task_outputs)

  defp assign_task_outputs(socket, entries) do
    socket = cancel_async(socket, :cache_task_outputs)

    if MapSet.size(entries) == 0 do
      assign(socket, :cache_task_outputs, AsyncResult.ok([]))
    else
      project_id = socket.assigns.run.project_id

      params = %{
        filters:
          ReapiCacheOutputs.event_filters(socket.assigns.run.id) ++
            [%{field: :target_label, op: :in, value: MapSet.to_list(entries)}],
        page_size: 100
      }

      assign_async(socket, :cache_task_outputs, fn ->
        {rows, _meta} = ReapiCache.list_cache_events(project_id, params, client_kind: "mix")
        {:ok, %{cache_task_outputs: rows}}
      end)
    end
  end

  defp assign_outputs(socket) do
    project_id = socket.assigns.run.project_id
    params = socket.assigns.cache_output_params
    key = {project_id, params}

    if socket.assigns[:cache_outputs_key] == key and !socket.assigns.cache_outputs.failed do
      socket
    else
      socket
      |> assign(:cache_outputs_key, key)
      |> assign_async(:cache_outputs, fn ->
        {rows, meta} = ReapiCache.list_cache_events(project_id, params, client_kind: "mix")
        {:ok, %{cache_outputs: %{rows: rows, meta: meta}}}
      end)
    end
  end

  defp cache_outcome(value) when value in ~w(local_hit remote_hit miss bypass), do: value
  defp cache_outcome(_), do: "all"

  defp cache_value(nil, _), do: dgettext("dashboard", "No data")
  defp cache_value(value, "hit_rate"), do: "#{Float.round(value, 1)}%"
  defp cache_value(value, type) when type in ~w(read_bytes write_bytes), do: ByteFormatter.format_bytes(value)
  defp cache_value(value, _), do: format_number(value)

  defp cache_title("hits"), do: dgettext("dashboard_builds", "Task hits")
  defp cache_title("misses"), do: dgettext("dashboard_builds", "Task misses")
  defp cache_title("hit_rate"), do: dgettext("dashboard_builds", "Hit rate")
  defp cache_title("read_bytes"), do: dgettext("dashboard_builds", "Cache downloads")
  defp cache_title("write_bytes"), do: dgettext("dashboard_builds", "Cache uploads")

  defp cache_description("hits"),
    do: dgettext("dashboard", "Artifacts restored from local snapshots or the shared remote CAS.")

  defp cache_description("misses"), do: dgettext("dashboard", "Cache lookups without reusable local or remote artifacts.")

  defp cache_description("hit_rate"),
    do: dgettext("dashboard", "Hits divided by hits plus misses. Work without a cache lookup is excluded.")

  defp cache_description("read_bytes"),
    do:
      dgettext(
        "dashboard",
        "Successful client CAS download bytes and local snapshot copy bytes. CAS Outputs shows only Kura-reported remote transfers."
      )

  defp cache_description("write_bytes"),
    do:
      dgettext(
        "dashboard",
        "Successful client CAS upload bytes and local snapshot copy bytes. CAS Outputs shows only Kura-reported remote transfers."
      )

  defp cache_percentile(value) when value in ~w(avg p50 p90 p99), do: value
  defp cache_percentile(_), do: "avg"
  defp cache_entry_id(dependency), do: "mix-build-cache-entry-#{Base.url_encode64(dependency, padding: false)}"

  defp cache_latency(summary, operation, type) do
    Map.fetch!(summary, String.to_existing_atom("#{type}_#{operation}_duration_us"))
  end

  defp cache_latency_value(nil), do: dgettext("dashboard", "No data")
  defp cache_latency_value(value), do: DateFormatter.format_duration_from_milliseconds(value / 1_000)

  defp cache_latency_metrics(summary, operation),
    do: Map.new(~w(avg p99 p90 p50)a, &{&1, cache_latency_value(cache_latency(summary, operation, to_string(&1)))})

  defp cache_latency_title("avg", "read"), do: dgettext("dashboard_builds", "Avg. latency reading cache artifacts")
  defp cache_latency_title("p99", "read"), do: dgettext("dashboard_builds", "p99 latency reading cache artifacts")
  defp cache_latency_title("p90", "read"), do: dgettext("dashboard_builds", "p90 latency reading cache artifacts")
  defp cache_latency_title("p50", "read"), do: dgettext("dashboard_builds", "p50 latency reading cache artifacts")
  defp cache_latency_title("avg", "write"), do: dgettext("dashboard_builds", "Avg. latency writing cache artifacts")
  defp cache_latency_title("p99", "write"), do: dgettext("dashboard_builds", "p99 latency writing cache artifacts")
  defp cache_latency_title("p90", "write"), do: dgettext("dashboard_builds", "p90 latency writing cache artifacts")
  defp cache_latency_title("p50", "write"), do: dgettext("dashboard_builds", "p50 latency writing cache artifacts")

  defp cache_hit_label("remote_hit"), do: dgettext("dashboard_builds", "Remote")
  defp cache_hit_label("local_hit"), do: dgettext("dashboard_builds", "Local")
  defp cache_hit_label("miss"), do: dgettext("dashboard_builds", "Missed")
  defp cache_hit_label("bypass"), do: dgettext("dashboard", "Not cached")

  defp cache_outcome_label("remote_hit"), do: dgettext("dashboard_cache", "Remote hit")
  defp cache_outcome_label("local_hit"), do: dgettext("dashboard_cache", "Local hit")
  defp cache_outcome_label("miss"), do: dgettext("dashboard_cache", "Miss")
  defp cache_outcome_label("bypass"), do: dgettext("dashboard", "Not cached")
  defp cache_outcome_label(_), do: dgettext("dashboard", "All results")
  defp cache_outcome_color("remote_hit"), do: "focus"
  defp cache_outcome_color("local_hit"), do: "secondary"
  defp cache_outcome_color("miss"), do: "warning"
  defp cache_outcome_color("bypass"), do: "neutral"

  defp cache_breakdown_series(summary) do
    [
      %{
        name: dgettext("dashboard_builds", "Local"),
        type: "bar",
        stack: "total",
        emphasis: %{focus: "series"},
        data: [summary.local_hits],
        color: "var:hits-chart-legend-local",
        itemStyle: %{borderRadius: cache_border_radius(summary, :local)}
      },
      %{
        name: dgettext("dashboard_builds", "Remote"),
        type: "bar",
        stack: "total",
        emphasis: %{focus: "series"},
        data: [summary.remote_hits],
        color: "var:hits-chart-legend-remote",
        itemStyle: %{borderRadius: cache_border_radius(summary, :remote)}
      },
      %{
        name: dgettext("dashboard_builds", "Missed"),
        type: "bar",
        stack: "total",
        emphasis: %{focus: "series"},
        data: [summary.misses],
        color: "var:hits-chart-legend-missed",
        itemStyle: %{borderRadius: cache_border_radius(summary, :misses)}
      }
    ]
  end

  defp cache_border_radius(summary, category),
    do: BuildRunLive.cache_chart_border_radius(summary.local_hits, summary.remote_hits, summary.misses, category)

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
