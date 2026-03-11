defmodule Tuist.MCP.Components.Tools.ListXcodeBuildCacheTasks do
  @moduledoc """
  List cacheable tasks (cache hits/misses) for a specific Xcode build run. Only available for projects with build_system=xcode. The build_run_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account}/{project}/builds/build-runs/{id}.
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

    field :status, :string, description: "Filter by cache status: hit_local, hit_remote, or miss."

    field :type, :string, description: "Filter by task type: clang or swift."
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
        Enum.reduce([:status, :type], filters, fn field, acc ->
          case Map.get(arguments, field) do
            nil -> acc
            value -> acc ++ [%{field: field, op: :==, value: value}]
          end
        end)

      page = ToolSupport.page(arguments)
      page_size = ToolSupport.page_size(arguments)

      {tasks, meta} =
        Builds.list_cacheable_tasks(%{
          filters: filters,
          order_by: [:inserted_at],
          order_directions: [:desc],
          page: page,
          page_size: page_size
        })

      data = %{
        tasks:
          Enum.map(tasks, fn task ->
            %{
              type: to_string(task.type),
              status: to_string(task.status),
              key: task.key,
              read_duration: task.read_duration,
              write_duration: task.write_duration,
              description: task.description,
              cas_output_node_ids: task.cas_output_node_ids
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
