defmodule TuistWeb.CargoBuildRunsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import Noora.Filter
  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Runs.RanByBadge

  alias Noora.Filter
  alias Tuist.Cargo
  alias Tuist.Repo
  alias Tuist.Utilities.DateFormatter
  alias TuistWeb.Utilities.Query
  alias TuistWeb.Utilities.SHA
  alias TuistWeb.XcodeBuildRunsLive

  def assign_mount(socket) do
    options = Cargo.build_options(socket.assigns.selected_project.id)

    assign(socket, :available_filters, [
      %Filter.Filter{
        id: "command",
        field: :command,
        display_name: dgettext("dashboard_builds", "Command"),
        type: :option,
        options: options.command,
        options_display_names: Map.new(options.command, &{&1, "cargo #{&1}"}),
        operator: :==
      },
      %Filter.Filter{
        id: "status",
        field: :status,
        display_name: dgettext("dashboard_builds", "Status"),
        type: :option,
        options: ["success", "failure"],
        options_display_names: %{
          "success" => dgettext("dashboard_builds", "Passed"),
          "failure" => dgettext("dashboard_builds", "Failed")
        },
        operator: :==
      },
      %Filter.Filter{
        id: "git_branch",
        field: :git_branch,
        display_name: dgettext("dashboard_builds", "Branch"),
        type: :text,
        operator: :=~,
        value: ""
      },
      %Filter.Filter{
        id: "rust_version",
        field: :rust_version,
        display_name: dgettext("dashboard_builds", "Rust version"),
        type: :text,
        operator: :=~,
        value: ""
      },
      %Filter.Filter{
        id: "is_ci",
        field: :is_ci,
        display_name: dgettext("dashboard_builds", "Environment"),
        type: :option,
        options: [true, false],
        options_display_names: %{true => "CI", false => dgettext("dashboard_builds", "Local")},
        operator: :==
      }
    ])
  end

  def assign_handle_params(socket, params) do
    params = Query.clear_cursors_on_initial_load(params, socket.assigns)
    filters = Filter.Operations.decode_filters_from_query(params, socket.assigns.available_filters)
    sort_by = if params["build-runs-sort-by"] == "duration", do: "duration", else: "ran-at"
    sort_order = if params["build-runs-sort-order"] == "asc", do: "asc", else: "desc"
    field = if sort_by == "duration", do: :duration_ms, else: :inserted_at
    direction = if sort_order == "asc", do: :asc, else: :desc

    options = %{
      filters: Filter.Operations.convert_filters_to_flop(filters),
      order_by: [field, :id],
      order_directions: [direction, direction]
    }

    options =
      cond do
        params["before"] -> Map.merge(options, %{last: 20, before: params["before"]})
        params["after"] -> Map.merge(options, %{first: 20, after: params["after"]})
        true -> Map.put(options, :first, 20)
      end

    project_id = socket.assigns.selected_project.id
    uri = URI.new!("?" <> URI.encode_query(params))

    socket
    |> assign(
      uri: uri,
      current_params: params,
      active_filters: filters,
      build_runs_sort_by: sort_by,
      build_runs_sort_order: sort_order
    )
    |> assign_async(:cargo_build_runs, fn ->
      {builds, meta} = Cargo.list_builds(project_id, options)
      {:ok, %{cargo_build_runs: %{builds: Repo.preload(builds, :ran_by_account), meta: meta, uri: uri}}}
    end)
  end

  def handle_event("add_filter", %{"value" => value}, socket),
    do: {:noreply, XcodeBuildRunsLive.handle_event_add_filter(value, socket)}

  def handle_event("update_filter", params, socket),
    do: {:noreply, XcodeBuildRunsLive.handle_event_update_filter(params, socket)}

  def column_patch_sort(assigns, column), do: XcodeBuildRunsLive.column_patch_sort(assigns, column)
end
