defmodule TuistWeb.OnceActionLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Helpers.VCSLinks
  import TuistWeb.Widget

  alias Tuist.OnceEvents.ActionHistory
  alias Tuist.OnceEvents.Presentation
  alias Tuist.Repo
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Errors.NotFoundError
  alias TuistWeb.OnceActionComponents
  alias TuistWeb.Utilities.Query

  def mount(%{"once_run_id" => run_id, "action_id" => action_id}, _session, socket) do
    project = Repo.preload(socket.assigns.selected_project, vcs_connection: :github_app_installation)
    action = fetch_action!(project.id, run_id, action_id)

    if connected?(socket) and action.history_id, do: ActionHistory.subscribe(project.id, action.history_id)

    {:ok,
     socket
     |> assign(:selected_project, project)
     |> assign(:action, action)
     |> assign(:current_user_timezone, socket.assigns.user_timezone)
     |> assign(:head_title, "#{OnceActionComponents.label(action)} · #{project.name} · Tuist")
     |> assign(:analytics_key, nil)
     |> assign(:history_key, nil)
     |> assign(:history_refresh_ref, nil)}
  end

  def handle_params(params, uri, socket) do
    tab = if params["tab"] == "history", do: "history", else: "overview"
    days = if params["days"] in ["7", "30", "90"], do: String.to_integer(params["days"]), else: 30
    page = integer(params["page"])

    metric =
      if params["metric"] in ["executions", "failures", "cache", "duration"], do: params["metric"], else: "duration"

    branch = String.slice(params["branch"] || "", 0, 256)
    until = Date.utc_today() |> Date.add(1) |> DateTime.new!(~T[00:00:00], "Etc/UTC")
    since = DateTime.add(until, -days, :day)
    opts = [since: since, until: until, branch: branch]
    action = socket.assigns.action
    metadata = Presentation.normalize(action.presentation) || %{"package" => nil, "platforms" => [], "context" => []}
    source_search = String.slice(params["source-search"] || "", 0, 256)

    sources =
      Enum.filter(
        OnceActionComponents.source_rows(action),
        &String.contains?(String.downcase(&1.file), String.downcase(source_search))
      )

    source_page = integer(params["source-page"])

    socket =
      socket
      |> assign(:uri, URI.parse(uri))
      |> assign(:params, params)
      |> assign(:tab, tab)
      |> assign(:days, days)
      |> assign(:metric, metric)
      |> assign(:branch, branch)
      |> assign(:period_opts, opts)
      |> assign(:metadata, metadata)
      |> assign(:badges, OnceActionComponents.badges(metadata))
      |> assign(:history_available, ActionHistory.available?(action))
      |> assign(:source_search, source_search)
      |> assign(:source_page, source_page)
      |> assign(:source_pages, max(ceil(length(sources) / 20), 1))
      |> assign(:source_count, length(sources))
      |> assign(:sources, Enum.slice(sources, (source_page - 1) * 20, 20))

    analytics_key = {action.id, action.history_ambiguous, days, branch, since, until}

    socket =
      if socket.assigns.analytics_key != analytics_key or async_failed?(socket, :analytics) do
        socket
        |> assign(:analytics_key, analytics_key)
        |> assign_async(:analytics, fn -> {:ok, %{analytics: ActionHistory.analytics(action, opts)}} end)
      else
        socket
      end

    {:noreply, load_occurrences(socket, action, opts, {analytics_key, tab, page})}
  end

  def handle_event("select-metric", %{"widget" => metric}, socket) do
    {:noreply, push_patch(socket, to: patch(socket.assigns, %{"metric" => metric}), replace: true)}
  end

  def handle_event("filter-history", %{"branch" => branch}, socket) do
    {:noreply, push_patch(socket, to: patch(socket.assigns, %{"branch" => branch, "page" => "1"}), replace: true)}
  end

  def handle_event("source-search", %{"source-search" => search}, socket) do
    {:noreply,
     push_patch(socket, to: patch(socket.assigns, %{"source-search" => search, "source-page" => "1"}), replace: true)}
  end

  def handle_info({:action_history_updated, id}, %{assigns: %{action: %{history_id: id}}} = socket) do
    socket =
      if socket.assigns.history_refresh_ref do
        socket
      else
        assign(socket, :history_refresh_ref, Process.send_after(self(), :refresh_history, 5_000))
      end

    {:noreply, socket}
  end

  def handle_info(:refresh_history, socket) do
    if socket.assigns.history_refresh_ref, do: Process.cancel_timer(socket.assigns.history_refresh_ref)
    socket = assign(socket, :history_refresh_ref, nil)
    action = fetch_action!(socket.assigns.selected_project.id, socket.assigns.action.run_id, socket.assigns.action.id)
    socket = socket |> assign(:action, action) |> assign(:analytics_key, nil) |> assign(:history_key, nil)
    handle_params(socket.assigns.params, URI.to_string(socket.assigns.uri), socket)
  end

  def handle_info(_, socket), do: {:noreply, socket}

  def patch(assigns, changes) do
    query = Enum.reduce(changes, assigns.uri.query, fn {key, value}, query -> Query.put(query, key, value) end)
    "#{assigns.uri.path}?#{query}"
  end

  def occurrence_path(assigns, action) do
    ~p"/#{assigns.selected_account.name}/#{assigns.selected_project.name}/once/runs/#{action.run_id}/actions/#{action.id}"
  end

  def run_path(assigns),
    do: ~p"/#{assigns.selected_account.name}/#{assigns.selected_project.name}/once/runs/#{assigns.action.run_id}"

  def duration(nil), do: "—"
  def duration(value), do: DateFormatter.format_duration_from_milliseconds(round(number(value)))

  def timestamp(nil, _timezone), do: "—"
  def timestamp(value, timezone), do: DateFormatter.format_with_timezone(value, timezone || "Etc/UTC")

  def cache_rate(%{cache_observations: 0}), do: "—"
  def cache_rate(stats), do: "#{Float.round(stats.hits / stats.cache_observations * 100, 1)}%"

  def chart_series(stats, metric) do
    [
      %{
        name: metric_label(metric),
        data: Enum.map(stats.series, &[NaiveDateTime.to_iso8601(&1.day) <> "Z", metric_value(&1, metric)])
      }
    ]
  end

  def chart_labels(stats), do: Enum.map(stats.series, &NaiveDateTime.to_iso8601(&1.day))
  def chart_type(metric) when metric in ["executions", "failures"], do: "bar"
  def chart_type(_), do: "line"
  def metric_label("executions"), do: dgettext("dashboard_projects", "Executions")
  def metric_label("failures"), do: dgettext("dashboard_projects", "Failures")
  def metric_label("cache"), do: dgettext("dashboard_projects", "Cache hit rate")
  def metric_label(_), do: dgettext("dashboard_projects", "Execution duration")

  def package_fields(package) do
    Enum.reject(
      [
        {dgettext("dashboard_projects", "Ecosystem"), package["ecosystem"]},
        {dgettext("dashboard_projects", "Package"), package["name"]},
        {dgettext("dashboard_projects", "Version"), package["version"]},
        {dgettext("dashboard_projects", "Revision"), package["revision"]},
        {dgettext("dashboard_projects", "Digest"), package["digest"]},
        {dgettext("dashboard_projects", "Origin"), package["origin"]}
      ],
      fn {_label, value} -> value in [nil, ""] end
    )
  end

  defp metric_value(row, "executions"), do: row.executions
  defp metric_value(row, "failures"), do: row.failures
  defp metric_value(%{cache_observations: 0}, "cache"), do: nil
  defp metric_value(row, "cache"), do: Float.round(row.hits / row.cache_observations * 100, 1)
  defp metric_value(row, _duration), do: number(row.duration)
  defp number(nil), do: nil
  defp number(%Decimal{} = value), do: Decimal.to_float(value)
  defp number(value), do: value

  defp load_occurrences(socket, action, opts, {_, tab, page} = history_key) do
    if socket.assigns.history_key != history_key or async_failed?(socket, :occurrences) do
      history_opts =
        opts ++ [page: if(tab == "history", do: page, else: 1), page_size: if(tab == "history", do: 20, else: 6)]

      socket
      |> assign(:history_key, history_key)
      |> assign_async([:occurrences, :history_meta], fn ->
        {rows, meta} = ActionHistory.list_occurrences(action, history_opts)
        {:ok, %{occurrences: rows, history_meta: meta}}
      end)
    else
      socket
    end
  end

  defp async_failed?(socket, key) do
    case socket.assigns[key] do
      %{failed: failed} -> not is_nil(failed)
      _ -> false
    end
  end

  defp integer(value) do
    case Integer.parse(value || "1") do
      {number, ""} when number > 0 -> min(number, 10_000)
      _ -> 1
    end
  end

  defp fetch_action!(project_id, run_id, action_id) do
    case ActionHistory.get_occurrence(project_id, run_id, action_id) do
      {:ok, action} -> action
      {:error, :not_found} -> raise NotFoundError, dgettext("dashboard_projects", "Action not found.")
    end
  end
end
