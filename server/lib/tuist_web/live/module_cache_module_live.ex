defmodule TuistWeb.ModuleCacheModuleLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.ModuleInvalidationsTable, only: [why_split: 1]
  import TuistWeb.Components.Skeleton

  alias Tuist.Builds.Analytics
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

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
              "analytics-environment",
              "analytics-branch",
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

  def handle_info(_event, socket), do: {:noreply, socket}

  defp assign_module(%{assigns: %{module_name: name}} = socket, params) do
    analytics_environment = params["analytics-environment"] || "any"
    analytics_branch = params["analytics-branch"] || "any"
    %{preset: preset, period: period} = DatePicker.date_picker_params(params, "analytics")

    socket =
      socket
      |> assign(:analytics_preset, preset)
      |> assign(:analytics_period, period)
      |> assign(:analytics_environment, analytics_environment)
      |> assign(:analytics_branch, analytics_branch)

    {start_datetime, end_datetime} = period
    project_id = socket.assigns.selected_project.id
    opts = analytics_opts(socket.assigns)

    assign_async(socket, [:module, :timeseries, :invalidated_by, :invalidates, :cache_branches], fn ->
      all_modules = opts |> Keyword.put(:limit, 1000) |> Analytics.module_invalidations()
      index = Map.new(all_modules, &{&1.name, &1})
      %{edges: edges} = Analytics.module_dependency_graph(opts)
      timeseries = Analytics.module_invalidation_timeseries(Keyword.put(opts, :name, name))

      module = build_module(index[name], name, timeseries)

      invalidated_by =
        (edges[name] || [])
        |> Enum.map(fn dep -> %{name: dep, self_changes: index[dep][:self_changes] || 0} end)
        |> Enum.sort_by(& &1.self_changes, :desc)

      invalidates =
        edges
        |> Analytics.module_transitive_dependents(name)
        |> Enum.map(fn dependent ->
          %{name: dependent, invalidations: index[dependent][:invalidations] || 0}
        end)
        |> Enum.sort_by(& &1.invalidations, :desc)

      branches =
        Analytics.cache_branches(
          project_id: project_id,
          start_datetime: start_datetime,
          end_datetime: end_datetime
        )

      {:ok,
       %{
         module: module,
         timeseries: timeseries,
         invalidated_by: invalidated_by,
         invalidates: invalidates,
         cache_branches: branches
       }}
    end)
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
      self_changes: 0,
      dependency_induced: 0,
      unclassified: invalidations,
      blast_radius: nil
    }
  end

  defp build_module(row, _name, timeseries) do
    Map.put(row, :reuses, Enum.sum(timeseries.reuses))
  end

  defp rate(_invalidations, 0), do: 0.0
  defp rate(invalidations, appearances), do: Float.round(invalidations / appearances * 100, 1)

  defp analytics_opts(%{
         selected_project: project,
         analytics_period: {start_datetime, end_datetime},
         analytics_environment: env,
         analytics_branch: branch
       }) do
    opts = [project_id: project.id, start_datetime: start_datetime, end_datetime: end_datetime]

    opts =
      case env do
        "ci" -> Keyword.put(opts, :is_ci, true)
        "local" -> Keyword.put(opts, :is_ci, false)
        _ -> opts
      end

    case branch do
      "any" -> opts
      branch -> Keyword.put(opts, :git_branch, branch)
    end
  end

  defp environment_label("local"), do: dgettext("dashboard_cache", "Local")
  defp environment_label("ci"), do: dgettext("dashboard_cache", "CI")
  defp environment_label(_), do: dgettext("dashboard_cache", "Any")

  defp branch_label("any"), do: dgettext("dashboard_cache", "Any")
  defp branch_label(branch), do: branch
end
