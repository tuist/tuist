defmodule Tuist.MCP.Components.Tools.ListXcodeBuildIssues do
  @moduledoc """
  List build issues (warnings and errors) for a specific Xcode build run. The build_run_id can also be a Tuist dashboard URL, e.g. https://tuist.dev/{account}/{project}/builds/build-runs/{id}.
  """

  use Tuist.MCP.Tool,
    name: "list_xcode_build_issues",
    title: "List Xcode Build Issues",
    schema: %{
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
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "issues" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "type" => %{"type" => "string", "enum" => ["warning", "error"]},
              "target" => %{"type" => "string"},
              "project" => %{"type" => "string"},
              "title" => %{"type" => "string"},
              "message" => %{"type" => ["string", "null"]},
              "signature" => %{"type" => ["string", "null"]},
              "step_type" => %{
                "type" => "string",
                "enum" => [
                  "c_compilation",
                  "swift_compilation",
                  "script_execution",
                  "create_static_library",
                  "linker",
                  "copy_swift_libs",
                  "compile_assets_catalog",
                  "compile_storyboard",
                  "write_auxiliary_file",
                  "link_storyboards",
                  "copy_resource_file",
                  "merge_swift_module",
                  "xib_compilation",
                  "swift_aggregated_compilation",
                  "precompile_bridging_header",
                  "other",
                  "validate_embedded_binary",
                  "validate"
                ]
              },
              "path" => %{"type" => ["string", "null"]},
              "starting_line" => %{"type" => "integer"},
              "ending_line" => %{"type" => "integer"},
              "starting_column" => %{"type" => "integer"},
              "ending_column" => %{"type" => "integer"}
            },
            "required" => [
              "type",
              "target",
              "project",
              "title",
              "message",
              "signature",
              "step_type",
              "path",
              "starting_line",
              "ending_line",
              "starting_column",
              "ending_column"
            ],
            "additionalProperties" => false
          }
        }
      },
      "required" => ["issues"],
      "additionalProperties" => false
    }

  alias Tuist.Builds
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description,
    do:
      "List build issues (warnings and errors) for a specific Xcode build run. The build_run_id can also be a Tuist dashboard URL, e.g. #{Tuist.Environment.app_url()}/{account}/{project}/builds/build-runs/{id}."

  def execute(conn, args) do
    build_run_id = Map.get(args, "build_run_id")

    with {:ok, _build, _project} <-
           MCPTool.load_and_authorize(
             Builds.get_build(build_run_id),
             conn.assigns,
             :read,
             :build,
             "Build not found: #{build_run_id}"
           ) do
      issues = Builds.list_build_issues(build_run_id)

      issues =
        issues
        |> maybe_filter(:type, Map.get(args, "type"))
        |> maybe_filter(:target, Map.get(args, "target"))
        |> maybe_filter(:step_type, Map.get(args, "step_type"))

      {:ok,
       %{
         issues:
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
       }}
    end
  end

  defp maybe_filter(items, _field, nil), do: items

  defp maybe_filter(items, field, value) do
    Enum.filter(items, fn item -> to_string(Map.get(item, field)) == value end)
  end
end
