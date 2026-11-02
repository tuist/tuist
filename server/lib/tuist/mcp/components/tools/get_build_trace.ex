defmodule Tuist.MCP.Components.Tools.GetBuildTrace do
  @moduledoc "Get a download link for a build's timeline as a Chrome Trace Event JSON file, for Xcode, Gradle, Bazel, and Mix builds. Download it with curl or similar (the link needs no other credentials and expires after an hour), then open it at https://ui.perfetto.dev or query it with Perfetto's trace_processor. Steps are packed into lanes by parallelism, with CPU and memory counters when the build recorded machine metrics. Use list_<build system>_build_steps to page through steps in the conversation instead."
  use Tuist.MCP.Tool,
    name: "get_build_trace",
    title: "Get Build Trace",
    read_only_hint: true,
    authorize: [action: :read, category: :build],
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string", "description" => "The account handle."},
        "project_handle" => %{"type" => "string", "description" => "The project handle."},
        "build_id" => %{
          "type" => "string",
          "description" => "The build run ID (the invocation ID for Bazel), or the build's Tuist dashboard URL."
        }
      },
      "required" => ["account_handle", "project_handle", "build_id"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "trace_url" => %{"type" => "string"},
        "expires_at" => %{"type" => "string"},
        "format" => %{"type" => "string"},
        "build_system" => %{"type" => "string"}
      },
      "required" => ["trace_url", "expires_at", "format", "build_system"],
      "additionalProperties" => false
    }

  alias Tuist.Builds.Trace
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description, do: @moduledoc

  def execute(_conn, args, project) do
    id = MCPTool.resource_id(Map.get(args, "build_id"))

    case Trace.get_build(project, id) do
      {:ok, _build} ->
        {:ok,
         %{
           trace_url: "#{Tuist.Environment.app_url()}/build-traces/#{Trace.sign_token(project, id)}",
           expires_at: DateTime.utc_now() |> DateTime.add(Trace.token_max_age()) |> DateTime.to_iso8601(),
           format: "chrome-trace-event-json",
           build_system: to_string(project.build_system)
         }}

      _ ->
        {:error, "Build not found: #{id}"}
    end
  end
end
