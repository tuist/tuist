defmodule Tuist.MCP.Components.Tools.ListBazelRemoteActions do
  @moduledoc false

  use Tuist.MCP.Tool,
    name: "list_bazel_remote_actions",
    title: "List Bazel Remote Actions",
    read_only_hint: true,
    authorize: [action: :read, category: :build],
    schema:
      Tuist.MCP.Components.Tools.BazelRemoteAction.input(%{
        "sort_by" => %{
          "type" => "string",
          "enum" => ["duration", "queued_at"],
          "description" => "Longest first (default), or earliest queued first."
        },
        "failed" => %{
          "type" => "boolean",
          "description" => "Only actions that exited non-zero or whose execution failed."
        },
        "mnemonic" => %{"type" => "string", "description" => "Only actions with this mnemonic, such as `CppCompile`."},
        "page" => %{"type" => "integer", "description" => "Page number, defaulting to 1."},
        "page_size" => %{"type" => "integer", "description" => "Results per page, up to 100."}
      }),
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "actions" => %{"type" => "array", "items" => Tuist.MCP.Components.Tools.BazelRemoteAction.summary_schema()},
        "pagination_metadata" => Tuist.MCP.Tool.pagination_metadata_schema()
      },
      "required" => ["actions", "pagination_metadata"],
      "additionalProperties" => false
    }

  alias Tuist.Bazel
  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.RemoteExecution.Actions

  @impl EMCP.Tool
  def description do
    "List the actions Tuist remote execution ran for a Bazel invocation, as the execution gateway recorded them: mnemonic, target, action digest, exit code, worker path and queue, input fetch, execution and output upload milliseconds. Use get_bazel_remote_action for an action's command, environment, output and a snippet to reproduce it locally. Records are best effort and kept for 90 days; a missing action does not prove it did not run remotely."
  end

  def execute(_conn, %{"invocation_id" => invocation_id} = args, project) do
    case Bazel.get_invocation(project.id, invocation_id, include_cache_summary: false) do
      {:ok, invocation} ->
        {actions, meta} =
          Actions.list(project.id, invocation.invocation_id, %{
            page: MCPTool.page(args),
            page_size: MCPTool.page_size(args),
            sort_by: Map.get(args, "sort_by"),
            failed: Map.get(args, "failed") == true,
            mnemonic: Map.get(args, "mnemonic")
          })

        {:ok,
         %{
           actions: Enum.map(actions, &Actions.summary_json/1),
           pagination_metadata: MCPTool.pagination_metadata(meta)
         }}

      {:error, :not_found} ->
        {:error, "Bazel invocation not found: #{invocation_id}"}
    end
  end
end
