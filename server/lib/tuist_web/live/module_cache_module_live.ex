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
              "cache-count",
              "miss-reason",
              "analytics-environment",
              "after",
              "before",
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

  def handle_event("select_cache_count", %{"type" => type}, socket) when type in ["hits", "misses"] do
    query = Query.put(socket.assigns.uri.query, "cache-count", type)

    {:noreply,
     socket
     |> assign(:selected_cache_count, type)
     |> assign(:uri, URI.new!("?" <> query))
     |> push_event("replace-url", %{url: "?" <> query})}
  end

  def handle_event("select_miss_reason", %{"type" => type}, socket) when type in ["changed", "upstream", "cold"] do
    query = Query.put(socket.assigns.uri.query, "miss-reason", type)

    {:noreply,
     socket
     |> assign(:selected_miss_reason, type)
     |> assign(:uri, URI.new!("?" <> query))
     |> push_event("replace-url", %{url: "?" <> query})}
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
    selected_cache_count = params["cache-count"] || "hits"
    selected_miss_reason = params["miss-reason"] || "changed"

    %{preset: preset, period: period} = DatePicker.date_picker_params(params, "analytics")

    socket =
      socket
      |> assign(:analytics_preset, preset)
      |> assign(:analytics_period, period)
      |> assign(:analytics_environment, analytics_environment)
      |> assign(:analytics_selected_widget, analytics_selected_widget)
      |> assign(:selected_cache_count, selected_cache_count)
      |> assign(:selected_miss_reason, selected_miss_reason)

    opts = analytics_opts(socket.assigns)

    socket =
      assign_async(socket, [:build_history], fn ->
        {:ok,
         %{
           build_history:
             opts
             |> Keyword.merge(name: name, after: params["after"], before: params["before"])
             |> Analytics.module_build_history()
         }}
      end)

    assign_async(
      socket,
      [:module, :timeseries, :dependents_series, :miss_reasons_series],
      fn ->
        all_modules = opts |> Keyword.put(:limit, 1000) |> Analytics.module_invalidations()
        index = Map.new(all_modules, &{&1.name, &1})

        timeseries =
          opts
          |> Keyword.put(:name, name)
          |> Analytics.module_invalidation_timeseries()
          |> with_hit_rates()

        module = build_module(index[name], name, timeseries)

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
  defp build_module(nil, name, timeseries) do
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
      blast_radius: nil
    }
  end

  defp build_module(row, _name, timeseries) do
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
