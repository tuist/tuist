defmodule TuistWeb.SnapshotsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.Skeleton
  import TuistWeb.EmptyState

  alias Tuist.FeatureFlags
  alias Tuist.Snapshots
  alias Tuist.Snapshots.Commit
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.SnapshotBuildLive
  alias TuistWeb.Utilities.Query
  alias TuistWeb.Utilities.SHA

  @widgets ~w(snapshot_runs visual_changes snapshots)
  @page_size 48
  @visible_tag_count 2

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    if !FeatureFlags.snapshots_enabled?(account), do: raise(NotFoundError)

    {:ok,
     socket
     |> assign(:head_title, "#{dgettext("dashboard_snapshots", "Snapshots")} · #{account.name}/#{project.name} · Tuist")
     |> assign(OpenGraph.project_image_assigns(project, title: dgettext("dashboard_snapshots", "Snapshots")))
     |> assign(:library_sources, Snapshots.library_sources(project))
     |> assign(:groups, Snapshots.library_groups(project))
     |> assign(:visible_tag_count, @visible_tag_count)}
  end

  def handle_params(_params, uri, %{assigns: %{selected_project: project, library_sources: sources}} = socket) do
    params = Query.query_params(uri)

    %{preset: preset, period: period} =
      DatePicker.date_picker_params(params, "analytics")

    set_names = Enum.map(sources, & &1.set_name)
    set_name = if params["set"] in set_names, do: params["set"]
    group = if Enum.any?(socket.assigns.groups, &(&1.group == params["group"])), do: params["group"]
    search = String.trim(params["search"] || "")
    filters = [set_name: set_name, group: group, search: search, page_size: @page_size]
    {page, total_pages, library} = library_page(project, filters, parse_page(params["page"]))

    {:noreply,
     socket
     |> assign(:uri, URI.new!("?" <> URI.encode_query(params)))
     |> assign(:analytics_preset, preset)
     |> assign(:analytics_period, period)
     |> assign(:analytics_trend_label, trend_label(preset))
     |> assign(:selected_widget, selected_widget(params["analytics-selected-widget"]))
     |> assign(:set_names, set_names)
     |> assign(:set_name, set_name)
     |> assign(:group, group)
     |> assign(:search, search)
     |> assign(:page, page)
     |> assign(:total_pages, total_pages)
     |> assign(:image_count, library.total_count)
     |> assign(:snapshot_count, if((search != "" or set_name) || group, do: Snapshots.count_library_images(project)))
     |> assign(:images, library.images)
     |> assign_analytics(socket, project, period)}
  end

  def handle_event(
        "analytics_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        socket
      ) do
    query =
      if preset == "custom" do
        socket.assigns.uri.query
        |> Query.put("analytics-date-range", "custom")
        |> Query.put("analytics-start-date", start_date)
        |> Query.put("analytics-end-date", end_date)
      else
        Query.put(socket.assigns.uri.query, "analytics-date-range", preset)
      end

    {:noreply, push_patch(socket, to: snapshots_path(socket, query))}
  end

  def handle_event("select_widget", %{"widget" => widget}, socket) do
    query = Query.put(socket.assigns.uri.query, "analytics-selected-widget", widget)

    {:noreply,
     socket
     |> assign(:selected_widget, selected_widget(widget))
     |> assign(:uri, URI.new!("?" <> query))
     |> push_event("replace-url", %{url: "?" <> query})}
  end

  def handle_event("search", %{"search" => search}, socket) do
    query = socket.assigns.uri.query |> Query.put("search", search) |> Query.drop("page")
    {:noreply, push_patch(socket, to: snapshots_path(socket, query), replace: true)}
  end

  defp snapshots_path(%{assigns: %{selected_account: account, selected_project: project}}, query),
    do: "/#{account.name}/#{project.name}/snapshots?#{query}"

  # A tile shows its first tags by key, as the review page labels them; the rest only count.
  defp visible_tags(tags) do
    tags |> Enum.sort() |> Enum.take(@visible_tag_count) |> Enum.map(fn {key, value} -> "#{key}: #{value}" end)
  end

  @doc "The path of an image's history page."
  def history_path(account, project, set_name, name),
    do:
      "/#{account.name}/#{project.name}/snapshots/images/#{encode_segment(set_name)}/" <>
        (name |> String.split("/") |> Enum.map_join("/", &encode_segment/1))

  defp encode_segment(segment), do: URI.encode(segment, &URI.char_unreserved?/1)

  defp library_page(project, filters, page) do
    library = Snapshots.list_library_images(project, Keyword.put(filters, :page, page))
    total_pages = max(div(library.total_count + @page_size - 1, @page_size), 1)

    # A page past the end, from a stale link or a narrower search, shows the last one.
    if page > total_pages do
      {total_pages, total_pages, Snapshots.list_library_images(project, Keyword.put(filters, :page, total_pages))}
    else
      {page, total_pages, library}
    end
  end

  # Searching and paging the library patch the URL too; only a new period reloads the analytics.
  defp assign_analytics(updated, socket, project, {start_datetime, end_datetime} = period) do
    if Map.has_key?(socket.assigns, :analytics) and socket.assigns.analytics_period == period do
      updated
    else
      assign_async(updated, :analytics, fn ->
        {:ok, %{analytics: Snapshots.analytics(project, start_datetime: start_datetime, end_datetime: end_datetime)}}
      end)
    end
  end

  defp parse_page(page) do
    case Integer.parse(page || "") do
      {page, ""} when page > 0 -> page
      _ -> 1
    end
  end

  defp selected_widget(widget) when widget in @widgets, do: widget
  defp selected_widget(_), do: "snapshot_runs"

  defp trend_label("last-24-hours"), do: dgettext("dashboard_snapshots", "since yesterday")
  defp trend_label("last-7-days"), do: dgettext("dashboard_snapshots", "since last week")
  defp trend_label("last-12-months"), do: dgettext("dashboard_snapshots", "since last year")
  defp trend_label("custom"), do: dgettext("dashboard_snapshots", "since last period")
  defp trend_label(_), do: dgettext("dashboard_snapshots", "since last month")

  defp widget_title("snapshot_runs"), do: dgettext("dashboard_snapshots", "Snapshot runs")
  defp widget_title("visual_changes"), do: dgettext("dashboard_snapshots", "Visual changes")
  defp widget_title("snapshots"), do: dgettext("dashboard_snapshots", "Snapshots")

  defp widget_color("snapshot_runs"), do: "primary"
  defp widget_color("visual_changes"), do: "secondary"
  defp widget_color("snapshots"), do: "tertiary"

  defp widget_description("snapshot_runs"),
    do:
      dgettext(
        "dashboard_snapshots",
        "Snapshot uploads from CI and local runs in the period. Each set, shard and rerun counts, so a sharded pull request counts once per shard."
      )

  defp widget_description("visual_changes"),
    do:
      dgettext(
        "dashboard_snapshots",
        "Commits in which at least one snapshot looked different from its baseline or was removed. It counts commits rather than runs because a commit pools its shards and reruns: one shard alone sees the images other shards rendered as removed. New snapshots alone don't count."
      )

  defp widget_description("snapshots"),
    do:
      dgettext(
        "dashboard_snapshots",
        "Snapshots in the latest run on the default branch, summed over snapshot sets. These are the baselines pull requests are compared with."
      )

  @doc "The icon of an image status, wherever a change shows as an icon."
  def change_icon("changed"), do: "pencil"
  def change_icon("added"), do: "plus"
  def change_icon("removed"), do: "minus"
  def change_icon("renamed"), do: "arrows_exchange"
  def change_icon("unchanged"), do: "check"
  def change_icon("skipped"), do: "player_track_next"

  @doc "The commit a commit's snapshots were compared with: its branch and short SHA."
  def compared_with(%Commit{} = commit),
    do:
      "#{commit.baseline_git_branch || dgettext("dashboard_snapshots", "Unknown")} · #{SHA.format_commit_sha(commit.baseline_commit_sha)}"

  @doc """
  A commit is named by its pull request's title, like Argos names builds,
  else by its short SHA; the branch moves to the description.
  """
  def commit_label(%Commit{pull_request_title: title}) when is_binary(title), do: title
  def commit_label(%Commit{} = commit), do: SHA.format_commit_sha(commit.git_commit_sha)

  def completeness_label(commit) do
    case Commit.completeness(commit) do
      :complete -> dgettext("dashboard_snapshots", "Complete")
      :in_progress -> dgettext("dashboard_snapshots", "In progress")
    end
  end

  def completeness_description(commit) do
    case Commit.completeness(commit) do
      :complete ->
        dgettext("dashboard_snapshots", "CI signalled that every job of this commit reported its snapshots.")

      :in_progress ->
        dgettext(
          "dashboard_snapshots",
          "More sets or shards may still upload: CI hasn't signalled the commit complete, with `tuist coverage complete` or `./gradlew tuistCoverageComplete`."
        )
    end
  end

  defp chart_series(analytics, widget) do
    %{dates: dates, values: values} = Map.fetch!(analytics, String.to_existing_atom(widget))
    dates |> Enum.zip(values) |> Enum.map(&Tuple.to_list/1)
  end

  attr :theme, :string, required: true, values: ~w(light dark)

  @doc """
  The empty state's background: the baseline, diff and new frames of a snapshot above the
  card, and recorded snapshots below it, faded out towards the edges like the Previews one.
  """
  def empty_state_illustration(assigns) do
    colors =
      if assigns.theme == "light",
        do: %{
          card: "#FDFDFD",
          block: "#F1F2F4",
          line: "#C7CCD1",
          shadow: "#0D0D0D",
          diff: "#FCE3E6",
          diff_line: "#F29AA6"
        },
        else: %{
          card: "#0E0E0E",
          block: "#181818",
          line: "#3A3A3A",
          shadow: "#000000",
          diff: "#2B1517",
          diff_line: "#6E2B33"
        }

    frames = [
      %{x: 322, y: 70, kind: :plain},
      %{x: 522, y: 70, kind: :diff},
      %{x: 722, y: 70, kind: :plain},
      %{x: 412, y: 790, kind: :plain},
      %{x: 632, y: 790, kind: :plain}
    ]

    assigns = assign(assigns, colors: colors, frames: frames, id: "snapshots-empty-#{assigns.theme}")

    ~H"""
    <svg
      width="1184"
      height="1045"
      viewBox="0 0 1184 1045"
      fill="none"
      xmlns="http://www.w3.org/2000/svg"
    >
      <defs>
        <radialGradient id={"#{@id}-fade"} cx="592" cy="500" r="620" gradientUnits="userSpaceOnUse">
          <stop offset="0" stop-color="white" stop-opacity="0.9" />
          <stop offset="1" stop-color="white" stop-opacity="0" />
        </radialGradient>
        <mask id={"#{@id}-mask"} maskUnits="userSpaceOnUse" x="0" y="0" width="1184" height="1045">
          <rect width="1184" height="1045" fill={"url(##{@id}-fade)"} />
        </mask>
        <filter id={"#{@id}-shadow"} x="-20%" y="-20%" width="140%" height="140%">
          <feDropShadow
            dx="0"
            dy="2"
            stdDeviation="1.5"
            flood-color={@colors.shadow}
            flood-opacity="0.12"
          />
        </filter>
      </defs>
      <g mask={"url(##{@id}-mask)"}>
        <g stroke={@colors.line} stroke-dasharray="10 10" stroke-linejoin="round">
          <path d="M462 180H522" />
          <path d="M662 180H722" />
          <path d="M592 300V400" />
          <path d="M592 720V760H482V790" />
          <path d="M592 760H702V790" />
        </g>
        <g :for={frame <- @frames} filter={"url(##{@id}-shadow)"}>
          <rect
            x={frame.x}
            y={frame.y}
            width="140"
            height="230"
            rx="16"
            fill={@colors.card}
            stroke={@colors.line}
          />
          <rect x={frame.x + 12} y={frame.y + 14} width="56" height="10" rx="5" fill={@colors.block} />
          <rect x={frame.x + 12} y={frame.y + 36} width="116" height="64" rx="8" fill={@colors.block} />
          <rect x={frame.x + 12} y={frame.y + 112} width="92" height="10" rx="5" fill={@colors.block} />
          <rect x={frame.x + 12} y={frame.y + 130} width="70" height="10" rx="5" fill={@colors.block} />
          <rect
            x={frame.x + 12}
            y={frame.y + 186}
            width="116"
            height="28"
            rx="8"
            fill={if frame.kind == :diff, do: @colors.diff, else: @colors.block}
            stroke={if frame.kind == :diff, do: @colors.diff_line, else: "none"}
          />
        </g>
      </g>
    </svg>
    """
  end
end
