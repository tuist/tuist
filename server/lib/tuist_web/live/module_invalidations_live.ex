defmodule TuistWeb.ModuleInvalidationsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Components.ModuleInvalidationsTable
  import TuistWeb.Components.Skeleton

  alias Tuist.Builds.Analytics
  alias TuistWeb.Helpers.DatePicker
  alias TuistWeb.Helpers.OpenGraph
  alias TuistWeb.Utilities.Query

  @sort_options ~w(invalidations invalidation_rate blast_radius self_changes dependency_induced)

  def mount(_params, _session, %{assigns: %{selected_project: project, selected_account: account}} = socket) do
    slug = "#{account.name}/#{project.name}"

    socket =
      socket
      |> assign(:head_title, "#{dgettext("dashboard_cache", "Module invalidations")} · #{slug} · Tuist")
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
              "analytics-end-date",
              "sort-by"
            ])
          )
      )

    {:noreply,
     socket
     |> assign(:uri, uri)
     |> assign_modules(params)}
  end

  def handle_event(
        "analytics_period_changed",
        %{"value" => %{"start" => start_date, "end" => end_date}, "preset" => preset},
        %{assigns: %{selected_account: account, selected_project: project}} = socket
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

    {:noreply, push_patch(socket, to: "/#{account.name}/#{project.name}/module-cache/modules?#{query_params}")}
  end

  def handle_info(_event, socket), do: {:noreply, socket}

  defp assign_modules(%{assigns: %{selected_project: project}} = socket, params) do
    analytics_environment = params["analytics-environment"] || "any"
    analytics_branch = params["analytics-branch"] || "any"
    sort_by = if params["sort-by"] in @sort_options, do: params["sort-by"], else: "invalidations"
    %{preset: preset, period: period} = DatePicker.date_picker_params(params, "analytics")

    socket =
      socket
      |> assign(:analytics_preset, preset)
      |> assign(:analytics_period, period)
      |> assign(:analytics_environment, analytics_environment)
      |> assign(:analytics_branch, analytics_branch)
      |> assign(:sort_by, sort_by)

    {start_datetime, end_datetime} = period
    opts = analytics_opts(socket.assigns)

    assign_async(socket, [:modules, :cache_branches], fn ->
      modules = opts |> Keyword.put(:limit, 1000) |> Analytics.module_invalidations() |> sort_modules(sort_by)

      branches =
        Analytics.cache_branches(
          project_id: project.id,
          start_datetime: start_datetime,
          end_datetime: end_datetime
        )

      {:ok, %{modules: modules, cache_branches: branches}}
    end)
  end

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

  defp sort_modules(modules, "blast_radius"), do: Enum.sort_by(modules, &(&1.blast_radius || -1), :desc)
  defp sort_modules(modules, field), do: Enum.sort_by(modules, &Map.fetch!(&1, String.to_existing_atom(field)), :desc)

  def sort_label("invalidation_rate"), do: dgettext("dashboard_cache", "Rate")
  def sort_label("blast_radius"), do: dgettext("dashboard_cache", "Blast radius")
  def sort_label("self_changes"), do: dgettext("dashboard_cache", "Self-changes")
  def sort_label("dependency_induced"), do: dgettext("dashboard_cache", "Dependency-induced")
  def sort_label(_), do: dgettext("dashboard_cache", "Invalidations")

  defp environment_label("local"), do: dgettext("dashboard_cache", "Local")
  defp environment_label("ci"), do: dgettext("dashboard_cache", "CI")
  defp environment_label(_), do: dgettext("dashboard_cache", "Any")

  defp branch_label("any"), do: dgettext("dashboard_cache", "Any")
  defp branch_label(branch), do: branch
end
