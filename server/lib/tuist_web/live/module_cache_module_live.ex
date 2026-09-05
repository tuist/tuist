defmodule TuistWeb.ModuleCacheModuleLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.Skeleton

  alias Tuist.Builds.Analytics
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query
  alias TuistWeb.Utilities.SHA

  def mount(
        %{"module" => module_name},
        _session,
        %{assigns: %{selected_project: project, selected_account: account}} = socket
      ) do
    slug = "#{account.name}/#{project.name}"

    socket =
      socket
      |> assign(:module_name, module_name)
      |> assign(:head_title, "#{module_name} · #{dgettext("dashboard_cache", "Module Cache")} · #{slug} · Tuist")
      |> assign(OpenGraph.og_image_assigns("module-cache"))

    {:ok, socket}
  end

  def handle_params(_params, uri, socket) do
    params = Query.query_params(uri)

    uri =
      URI.new!(
        "?" <>
          URI.encode_query(
            Map.take(params, [
              "analytics-selected-widget",
              "miss-reason",
              "analytics-environment",
              "after",
              "before",
              "builds-branch",
              "builds-commit",
              "builds-reason",
              "builds-order",
              "analytics-date-range",
              "analytics-start-date",
              "analytics-end-date"
            ])
          )
      )

    {:noreply,
     socket
     |> assign(:uri, uri)
     |> assign_module(params)}
  end

  def handle_event(
        "analytics_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        %{assigns: %{selected_account: account, selected_project: project, module_name: module_name}} = socket
      ) do
    query_params =
      if preset == "custom" do
        socket.assigns.uri.query
        |> Query.put("analytics-date-range", "custom")
        |> Query.put("analytics-start-date", start_date)
        |> Query.put("analytics-end-date", end_date)
      else
        Query.put(socket.assigns.uri.query, "analytics-date-range", preset)
      end

    {:noreply,
     push_patch(socket,
       to: "/#{account.name}/#{project.name}/module-cache/modules/#{module_name}?#{query_params}"
     )}
  end

  def handle_event("select_widget", %{"widget" => widget}, socket) do
    query = Query.put(socket.assigns.uri.query, "analytics-selected-widget", widget)

    {:noreply,
     socket
     |> assign(:analytics_selected_widget, widget)
     |> assign(:uri, URI.new!("?" <> query))
     |> push_event("replace-url", %{url: "?" <> query})}
  end

  def handle_event("select_miss_reason", %{"type" => type}, socket) when type in ~w(all changed upstream cold) do
    query = Query.put(socket.assigns.uri.query, "miss-reason", type)

    {:noreply,
     socket
     |> assign(:selected_miss_reason, type)
     |> assign(:uri, URI.new!("?" <> query))
     |> push_event("replace-url", %{url: "?" <> query})}
  end

  def handle_event(
        "search_builds",
        %{"commit" => commit},
        %{assigns: %{selected_account: account, selected_project: project, module_name: name}} = socket
      ) do
    {:noreply,
     push_patch(socket,
       to:
         "/#{account.name}/#{project.name}/module-cache/modules/#{name}#{builds_filter_patch(socket.assigns.uri, "builds-commit", commit)}"
     )}
  end

  def handle_info(_event, socket), do: {:noreply, socket}

  # The hit rate chart is derived from the same daily counts rather than a
  # second query: a day with no builds has no rate, so it plots as 0.
  defp with_hit_rates(timeseries) do
    hit_rates =
      Enum.zip_with(timeseries.invalidations, timeseries.reuses, fn misses, hits ->
        case misses + hits do
          0 -> 0.0
          total -> Float.round(hits / total * 100, 1)
        end
      end)

    Map.put(timeseries, :hit_rates, hit_rates)
  end

  defp assign_module(%{assigns: %{module_name: name}} = socket, params) do
    analytics_environment = params["analytics-environment"] || "any"
    analytics_selected_widget = params["analytics-selected-widget"] || "cache_activity"
    selected_miss_reason = params["miss-reason"] || "all"

    %{preset: preset, period: period} = DatePicker.date_picker_params(params, "analytics")

    socket =
      socket
      |> assign(:analytics_preset, preset)
      |> assign(:analytics_period, period)
      |> assign(:analytics_environment, analytics_environment)
      |> assign(:analytics_selected_widget, analytics_selected_widget)
      |> assign(:selected_miss_reason, selected_miss_reason)

    opts = analytics_opts(socket.assigns)

    socket = assign(socket, builds_filters(params))
    history_opts = build_history_opts(opts, name, params, socket.assigns)

    project_id = socket.assigns.selected_project.id
    {start_datetime, end_datetime} = period

    socket =
      assign_async(socket, [:build_history, :cache_branches], fn ->
        {:ok,
         %{
           build_history: Analytics.module_build_history(history_opts),
           cache_branches:
             Analytics.cache_branches(
               project_id: project_id,
               start_datetime: start_datetime,
               end_datetime: end_datetime
             )
         }}
      end)

    assign_async(
      socket,
      [:module, :timeseries, :dependents_series, :miss_reasons_series],
      fn ->
        # Fetching the top N by miss count and looking this module up in it
        # loses the page's own module once the project has more modules than
        # the cutoff, so ask for it by name.
        row = opts |> Keyword.put(:name, name) |> Analytics.module_invalidations() |> List.first()

        timeseries =
          opts
          |> Keyword.put(:name, name)
          |> Analytics.module_invalidation_timeseries()
          |> with_hit_rates()

        module = build_module(row, name, timeseries, opts)

        dependents_series =
          Analytics.module_dependents_timeseries(Keyword.put(opts, :name, name))

        miss_reasons_series =
          Analytics.module_miss_reasons_timeseries(Keyword.put(opts, :name, name))

        {:ok,
         %{
           module: module,
           timeseries: timeseries,
           dependents_series: dependents_series,
           miss_reasons_series: miss_reasons_series
         }}
      end
    )
  end

  # When a module has invalidations its row exists; otherwise synthesize a
  # zeroed row from the time series so the page still renders (e.g. a module
  # that only ever reused from cache in the window).
  defp build_module(nil, name, timeseries, opts) do
    invalidations = Enum.sum(timeseries.invalidations)
    reuses = Enum.sum(timeseries.reuses)
    appearances = invalidations + reuses

    %{
      name: name,
      product: "",
      invalidations: invalidations,
      reuses: reuses,
      appearances: appearances,
      invalidation_rate: rate(invalidations, appearances),
      hit_rate: rate(reuses, appearances),
      self_changes: 0,
      dependency_induced: 0,
      unclassified: invalidations,
      # A module with no misses still has dependents; the graph knows them even
      # though there is no invalidation row to read them from.
      blast_radius: Analytics.module_dependents_count(Keyword.put(opts, :name, name))
    }
  end

  defp build_module(row, _name, timeseries, _opts) do
    reuses = Enum.sum(timeseries.reuses)

    row
    |> Map.put(:reuses, reuses)
    |> Map.put(:hit_rate, rate(reuses, row.invalidations + reuses))
  end

  defp rate(_invalidations, 0), do: 0.0
  defp rate(invalidations, appearances), do: Float.round(invalidations / appearances * 100, 1)

  defp analytics_opts(%{
         selected_project: project,
         analytics_period: {start_datetime, end_datetime},
         analytics_environment: env
       }) do
    opts = [project_id: project.id, start_datetime: start_datetime, end_datetime: end_datetime]

    case env do
      "ci" -> Keyword.put(opts, :is_ci, true)
      "local" -> Keyword.put(opts, :is_ci, false)
      _ -> opts
    end
  end

  defp builds_filters(params) do
    %{
      builds_branch: params["builds-branch"] || "any",
      builds_commit: params["builds-commit"] || "",
      builds_reason: params["builds-reason"] || "any",
      builds_order: if(params["builds-order"] == "asc", do: "asc", else: "desc")
    }
  end

  defp build_history_opts(opts, name, params, assigns) do
    Keyword.merge(opts,
      name: name,
      after: params["after"],
      before: params["before"],
      commit_sha: assigns.builds_commit,
      order: assigns.builds_order,
      git_branch: unless_any(assigns.builds_branch),
      reason: unless_any(assigns.builds_reason)
    )
  end

  defp unless_any("any"), do: nil
  defp unless_any(value), do: value

  def builds_filter_patch(uri, key, value) do
    query =
      uri.query
      |> Query.put(key, value)
      |> Query.drop("after")
      |> Query.drop("before")

    "?#{query}"
  end

  @doc """
  Patch for the Ran at header, which is the only thing the builds table sorts by.
  """
  def builds_order_patch(%{uri: uri, builds_order: order}) do
    builds_filter_patch(uri, "builds-order", if(order == "asc", do: "desc", else: "asc"))
  end

  def builds_branch_label("any"), do: dgettext("dashboard_cache", "Any")
  def builds_branch_label(branch), do: branch

  def builds_reason_label("hit"), do: dgettext("dashboard_cache", "Cached")
  def builds_reason_label("changed"), do: dgettext("dashboard_cache", "Changed")
  def builds_reason_label("upstream"), do: dgettext("dashboard_cache", "Upstream")
  def builds_reason_label("cold"), do: dgettext("dashboard_cache", "Cold")
  def builds_reason_label(_), do: dgettext("dashboard_cache", "Any")

  def miss_reason_value(module, "changed"), do: module.self_changes
  def miss_reason_value(module, "upstream"), do: module.dependency_induced
  def miss_reason_value(module, "cold"), do: module.unclassified
  def miss_reason_value(module, _all), do: module.invalidations

  def miss_reason_title("changed"), do: dgettext("dashboard_cache", "Changed misses")
  def miss_reason_title("upstream"), do: dgettext("dashboard_cache", "Upstream misses")
  def miss_reason_title("cold"), do: dgettext("dashboard_cache", "Cold misses")
  def miss_reason_title(_all), do: dgettext("dashboard_cache", "Misses")

  def miss_reason_legend("changed"), do: "primary"
  def miss_reason_legend("upstream"), do: "secondary"
  def miss_reason_legend("cold"), do: "tertiary"
  def miss_reason_legend(_all), do: "destructive"

  def build_reason_label("changed"), do: dgettext("dashboard_cache", "Changed")
  def build_reason_label("upstream"), do: dgettext("dashboard_cache", "Upstream")
  def build_reason_label("cold"), do: dgettext("dashboard_cache", "Cold")
  def build_reason_label(_), do: dgettext("dashboard_cache", "Cached")

  # The colours the miss-reason widget and its chart already use, so a row reads
  # the same way as the breakdown above it.
  def build_reason_color("changed"), do: "primary"
  def build_reason_color("upstream"), do: "secondary"
  def build_reason_color("cold"), do: "attention"
  def build_reason_color(_), do: "neutral"

  defp environment_label("local"), do: dgettext("dashboard_cache", "Local")
  defp environment_label("ci"), do: dgettext("dashboard_cache", "CI")
  defp environment_label(_), do: dgettext("dashboard_cache", "Any")
end
