defmodule TuistWeb.MixBuildRunsLive do
  @moduledoc false
  use TuistWeb, :live_view
  use Noora

  import TuistWeb.Components.EmptyCardSection
  import TuistWeb.Runs.ProjectWithTags
  import TuistWeb.Runs.RanByBadge

  alias Tuist.Mix
  alias Tuist.Repo
  alias TuistWeb.Utilities.Query
  alias TuistWeb.Utilities.SHA

  @page_size 20

  def assign_mount(socket), do: socket

  def assign_handle_params(socket, params) do
    sort_by = params["build-runs-sort-by"] || "ran-at"
    # Query parameters are the visitor's to type, so anything unexpected
    # falls back to the default rather than raising.
    sort_order = if params["build-runs-sort-order"] == "asc", do: "asc", else: "desc"

    page =
      case Integer.parse(params["page"] || "1") do
        {number, ""} when number > 0 -> number
        _ -> 1
      end

    {builds, meta} =
      Mix.list_builds(socket.assigns.selected_project.id, %{
        page: page,
        page_size: @page_size,
        order_by: [sort_field(sort_by)],
        order_directions: [if(sort_order == "asc", do: :asc, else: :desc)]
      })

    socket
    |> assign(:uri, URI.new!("?" <> URI.encode_query(params)))
    |> assign(:current_params, params)
    |> assign(:build_runs_sort_by, sort_by)
    |> assign(:build_runs_sort_order, sort_order)
    |> assign(:build_runs, Repo.preload(builds, :ran_by_account))
    |> assign(:build_runs_page, page)
    |> assign(:build_runs_page_count, meta.total_pages)
  end

  def column_patch_sort(%{uri: uri, build_runs_sort_by: sort_by, build_runs_sort_order: order}, column) do
    next_order = if sort_by == column and order == "desc", do: "asc", else: "desc"

    "?#{uri.query |> Query.put("build-runs-sort-by", column) |> Query.put("build-runs-sort-order", next_order)}"
  end

  defp sort_field("duration"), do: :duration_ms
  defp sort_field(_), do: :inserted_at

  @doc false
  def format_sha(sha), do: SHA.format_commit_sha(sha)
end
