defmodule Tuist.MCP.Components.Tools.ListXcodeBuildFiles do
  @moduledoc """
  List compiled files for a specific Xcode build run. Only available for projects with build_system=xcode. The build_run_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account}/{project}/builds/build-runs/{id}.
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

    field :target, :string, description: "Filter by target name."
    field :type, :string, description: "Filter by file type: swift or c."

    field :sort_by, :string, description: "Sort by field: compilation_duration (default, descending) or path."
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
        Enum.reduce([:target, :type], filters, fn field, acc ->
          case Map.get(arguments, field) do
            nil -> acc
            value -> acc ++ [%{field: field, op: :==, value: value}]
          end
        end)

      {order_by, order_directions} =
        case Map.get(arguments, :sort_by) do
          "path" -> {[:path], [:asc]}
          _ -> {[:compilation_duration], [:desc]}
        end

      page = ToolSupport.page(arguments)
      page_size = ToolSupport.page_size(arguments)

      {files, meta} =
        Builds.list_build_files(%{
          filters: filters,
          order_by: order_by,
          order_directions: order_directions,
          page: page,
          page_size: page_size
        })

      data = %{
        files:
          Enum.map(files, fn file ->
            %{
              type: to_string(file.type),
              target: file.target,
              project: file.project,
              path: file.path,
              compilation_duration: file.compilation_duration
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
