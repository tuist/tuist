defmodule TuistWeb.GradleBuildLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Runs.RanByBadge

  alias Tuist.Gradle
  alias Tuist.Repo
  alias Tuist.Utilities.ByteFormatter
  alias Tuist.Utilities.DateFormatter
  alias Tuist.Utilities.ThroughputFormatter
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.Utilities.Query

  @table_page_size 25

  def mount(
        %{"gradle_build_id" => build_id},
        _session,
        %{assigns: %{selected_project: project, selected_account: account}} = socket
      ) do
    build = Gradle.get_build(build_id)

    if is_nil(build) or build.project_id != project.id do
      raise NotFoundError, dgettext("dashboard_gradle", "Build not found.")
    end

    build = Repo.preload(build, :built_by_account)

    aggregates = Gradle.task_cache_aggregates(build_id)

    download_throughput =
      if aggregates.download_duration_ms > 0,
        do: aggregates.cache_download_bytes / (aggregates.download_duration_ms / 1000),
        else: 0

    upload_throughput =
      if aggregates.upload_duration_ms > 0,
        do: aggregates.cache_upload_bytes / (aggregates.upload_duration_ms / 1000),
        else: 0

    slug = "#{account.name}/#{project.name}"
    title = build.root_project_name || dgettext("dashboard_gradle", "Gradle Build")

    socket =
      socket
      |> assign(:build, build)
      |> assign(:cache_download_bytes, aggregates.cache_download_bytes)
      |> assign(:cache_upload_bytes, aggregates.cache_upload_bytes)
      |> assign(:download_throughput, download_throughput)
      |> assign(:upload_throughput, upload_throughput)
      |> assign(:title, title)
      |> assign(:head_title, "#{title} · #{slug} · Tuist")

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    selected_tab = params["tab"] || "overview"
    uri = URI.new!("?" <> URI.encode_query(params))

    socket =
      socket
      |> assign(:selected_tab, selected_tab)
      |> assign(:uri, uri)
      |> assign_tab_data(selected_tab, params)

    {:noreply, socket}
  end

  defp assign_tab_data(socket, "overview", params) do
    build_id = socket.assigns.build.id
    page = String.to_integer(params["tasks-page"] || "1")

    flop_params = %{
      page: page,
      page_size: @table_page_size
    }

    {tasks, meta} = Gradle.list_tasks(build_id, flop_params)

    socket
    |> assign(:tasks, tasks)
    |> assign(:tasks_page, page)
    |> assign(:tasks_page_count, meta.total_pages)
  end

  defp assign_tab_data(socket, "gradle-cache", params) do
    build_id = socket.assigns.build.id
    page = String.to_integer(params["cacheable-tasks-page"] || "1")

    flop_params = %{
      page: page,
      page_size: @table_page_size,
      filters: [%{field: :cacheable, op: :==, value: true}]
    }

    {cacheable_tasks, meta} = Gradle.list_tasks(build_id, flop_params)

    socket
    |> assign(:cacheable_tasks, cacheable_tasks)
    |> assign(:cacheable_tasks_page, page)
    |> assign(:cacheable_tasks_page_count, meta.total_pages)
  end

  defp assign_tab_data(socket, _tab, _params), do: socket

  defp cache_hit_rate(build) do
    from_cache = (build.tasks_local_hit_count || 0) + (build.tasks_remote_hit_count || 0)
    executed = build.tasks_executed_count || 0
    total = from_cache + executed

    if total == 0 do
      0.0
    else
      Float.round(from_cache / total * 100.0, 1)
    end
  end

  defp outcome_color("local_hit"), do: "success"
  defp outcome_color("remote_hit"), do: "information"
  defp outcome_color("up_to_date"), do: "information"
  defp outcome_color("executed"), do: "secondary"
  defp outcome_color("failed"), do: "destructive"
  defp outcome_color(_), do: "secondary"

  defp outcome_label("local_hit"), do: dgettext("dashboard_gradle", "Local hit")
  defp outcome_label("remote_hit"), do: dgettext("dashboard_gradle", "Remote hit")
  defp outcome_label("up_to_date"), do: dgettext("dashboard_gradle", "Up-to-date")
  defp outcome_label("executed"), do: dgettext("dashboard_gradle", "Executed")
  defp outcome_label("failed"), do: dgettext("dashboard_gradle", "Failed")
  defp outcome_label("skipped"), do: dgettext("dashboard_gradle", "Skipped")
  defp outcome_label("no_source"), do: dgettext("dashboard_gradle", "No source")
  defp outcome_label(other), do: other

  defp format_duration(duration_ms) do
    DateFormatter.format_duration_from_milliseconds(duration_ms)
  end

end
