defmodule Tuist.MCP.Components.Tools.ListXcodeBuildIssues do
  @moduledoc """
  List build issues (warnings and errors) for a specific build run. The build_run_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account}/{project}/builds/build-runs/{id}.
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

    field :type, :string, description: "Filter by issue type: warning or error."
    field :target, :string, description: "Filter by target name."
    field :step_type, :string, description: "Filter by compilation step type (e.g. swift_compilation, linker)."
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
      issues = Builds.list_build_issues(build_run_id)

      issues =
        issues
        |> maybe_filter(:type, Map.get(arguments, :type))
        |> maybe_filter(:target, Map.get(arguments, :target))
        |> maybe_filter(:step_type, Map.get(arguments, :step_type))

      data =
        Enum.map(issues, fn issue ->
          %{
            type: to_string(issue.type),
            target: issue.target,
            project: issue.project,
            title: issue.title,
            message: issue.message,
            signature: issue.signature,
            step_type: to_string(issue.step_type),
            path: issue.path,
            starting_line: issue.starting_line,
            ending_line: issue.ending_line,
            starting_column: issue.starting_column,
            ending_column: issue.ending_column
          }
        end)

      {:reply, Response.json(Response.tool(), data), frame}
    end
  end

  defp get_build(id) do
    case Builds.get_build(id) do
      nil -> {:error, :not_found}
      build -> {:ok, build}
    end
  end

  defp maybe_filter(items, _field, nil), do: items

  defp maybe_filter(items, field, value) do
    Enum.filter(items, fn item -> to_string(Map.get(item, field)) == value end)
  end
end
