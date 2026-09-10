defmodule Tuist.MCP.Components.Tools.ListXcodeBuildSteps do
  @moduledoc "List recorded Xcode build steps without logs. Page size defaults to 20 (max 100). Times are milliseconds from build start; time filters select overlaps with an exclusive end_ms. Steps expire after 90 days; unavailable means not recorded or expired. Use get_xcode_build_step to inspect a log."
  use Tuist.MCP.Tool,
    name: "list_xcode_build_steps",
    title: "List Xcode Build Steps",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "build_run_id" => %{"type" => "string", "description" => "Build UUID or Tuist build dashboard URL."},
        "page" => %{"type" => "integer", "minimum" => 1, "maximum" => 100_000},
        "page_size" => %{"type" => "integer", "minimum" => 1, "maximum" => 100},
        "search" => %{
          "type" => "string",
          "maxLength" => 512,
          "description" => "Case-insensitive title, project, or target search."
        },
        "project" => %{"type" => "string", "maxLength" => 512},
        "target" => %{"type" => "string", "maxLength" => 512},
        "category" => %{
          "type" => "string",
          "maxLength" => 128,
          "description" => "Exact recorded category, e.g. swiftCompilation."
        },
        "status" => %{"type" => "string", "enum" => ["success", "failure"]},
        "start_ms" => %{"type" => "number", "minimum" => 0},
        "end_ms" => %{"type" => "number", "minimum" => 0},
        "sort_by" => %{
          "type" => "string",
          "enum" => ["duration_ms", "start_ms"],
          "description" => "Duration descending (default) or start ascending, with step-ID tie breaking."
        }
      },
      "required" => ["build_run_id"]
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "steps" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "string"},
              "title" => %{"type" => "string"},
              "project" => %{"type" => "string"},
              "target" => %{"type" => "string"},
              "category" => %{"type" => "string"},
              "status" => %{"type" => "string"},
              "start_ms" => %{"type" => "number"},
              "duration_ms" => %{"type" => "number"}
            },
            "required" => ["id", "title", "project", "target", "category", "status", "start_ms", "duration_ms"],
            "additionalProperties" => false
          }
        },
        "availability" => %{"type" => "string", "enum" => ["available", "processing", "unavailable"]},
        "pagination_metadata" => Tuist.MCP.Tool.pagination_metadata_schema()
      },
      "required" => ["steps", "availability", "pagination_metadata"],
      "additionalProperties" => false
    }

  alias Tuist.Builds
  alias Tuist.Builds.Steps
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description, do: @moduledoc

  def execute(conn, args) do
    id = MCPTool.resource_id(Map.get(args, "build_run_id"))

    with {:ok, build, _project} <-
           MCPTool.load_and_authorize(Builds.get_build(id), conn.assigns, :read, :build, "Build not found: #{id}"),
         {:ok, result} <- Steps.list(build, args) do
      {:ok, result}
    else
      {:error, :not_found} -> {:error, "Build step not found."}
      {:error, reason} when is_atom(reason) -> {:error, "Invalid step ID, filters, or time range."}
      error -> error
    end
  end
end
