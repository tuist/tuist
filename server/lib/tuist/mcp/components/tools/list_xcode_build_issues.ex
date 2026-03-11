defmodule Tuist.MCP.Components.Tools.ListXcodeBuildIssues do
  @moduledoc """
  List build issues (warnings and errors) for a specific build run. The build_run_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account}/{project}/builds/build-runs/{id}.
  """

  @behaviour EMCP.Tool

  alias Tuist.Builds
  alias Tuist.MCP.Components.ToolSupport

  @authorization_action :read
  @authorization_category :build

  @impl EMCP.Tool
  def name, do: "list_xcode_build_issues"

  @impl EMCP.Tool
  def description,
    do:
      "List build issues (warnings and errors) for a specific build run. The build_run_id can also be a Tuist dashboard URL, e.g. #{Tuist.Environment.app_url()}/{account}/{project}/builds/build-runs/{id}."

  @impl EMCP.Tool
  def input_schema do
    %{
      "type" => "object",
      "properties" => %{
        "build_run_id" => %{
          "type" => "string",
          "description" => "The ID of the build run."
        },
        "type" => %{
          "type" => "string",
          "description" => "Filter by issue type: warning or error."
        },
        "target" => %{
          "type" => "string",
          "description" => "Filter by target name."
        },
        "step_type" => %{
          "type" => "string",
          "description" => "Filter by compilation step type (e.g. swift_compilation, linker)."
        }
      },
      "required" => ["build_run_id"]
    }
  end

  @impl EMCP.Tool
  def call(conn, args) do
    build_run_id = Map.get(args, "build_run_id")

    with {:ok, build} <-
           ToolSupport.load_resource(
             get_build(build_run_id),
             "Build not found: #{build_run_id}"
           ),
         {:ok, _project} <-
           ToolSupport.authorize_project_by_id(
             conn.assigns,
             build.project_id,
             @authorization_action,
             @authorization_category
           ) do
      issues = Builds.list_build_issues(build_run_id)

      issues =
        issues
        |> maybe_filter(:type, Map.get(args, "type"))
        |> maybe_filter(:target, Map.get(args, "target"))
        |> maybe_filter(:step_type, Map.get(args, "step_type"))

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

      ToolSupport.json_response(data)
    else
      {:error, message} -> EMCP.Tool.error(message)
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
