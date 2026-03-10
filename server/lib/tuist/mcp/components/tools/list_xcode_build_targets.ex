defmodule Tuist.MCP.Components.Tools.ListXcodeBuildTargets do
  @moduledoc """
  List build targets for a specific Xcode build run. Only available for projects with build_system=xcode. The project is derived from the build run, so no account or project handle is needed. The build_run_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account}/{project}/builds/build-runs/{id}.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Tuist.Builds
  alias Tuist.MCP.Components.ToolSupport

  @authorization_action :read
  @authorization_category :build

  schema do
    field :build_run_id, :string,
      required: true,
      description: "The ID of the build run."

    field :status, :string, description: "Filter by target status: success or failure."
    field :page, :integer, description: "Page number (default: 1)."
    field :page_size, :integer, description: "Results per page (default: 20, max: 100)."
  end

  @impl true
  def execute(%{build_run_id: build_run_id} = arguments, frame) do
    with {:ok, build} <-
           ToolSupport.load_resource(
             get_build(build_run_id),
             "Build not found: #{build_run_id}",
             frame
           ),
         {:ok, _project} <-
           ToolSupport.authorize_project_by_id(
             frame,
             build.project_id,
             @authorization_action,
             @authorization_category
           ) do
      filters = [%{field: :build_run_id, op: :==, value: build_run_id}]

      filters =
        case Map.get(arguments, :status) do
          nil -> filters
          status -> filters ++ [%{field: :status, op: :==, value: status}]
        end

      page = ToolSupport.page(arguments)
      page_size = ToolSupport.page_size(arguments)

      {targets, meta} =
        Builds.list_build_targets(%{
          filters: filters,
          order_by: [:build_duration],
          order_directions: [:desc],
          page: page,
          page_size: page_size
        })

      data = %{
        targets:
          Enum.map(targets, fn target ->
            %{
              name: target.name,
              project: target.project,
              build_duration: target.build_duration,
              compilation_duration: target.compilation_duration,
              status: to_string(target.status)
            }
          end),
        pagination_metadata: ToolSupport.pagination_metadata(meta)
      }

      {:reply, Response.json(Response.tool(), data), frame}
    end
  end

  defp get_build(id) do
    case Builds.get_build(id) do
      nil -> {:error, :not_found}
      build -> {:ok, build}
    end
  end
end
