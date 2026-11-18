defmodule Tuist.MCP.Components.Tools.ListBazelInvocationLogs do
  @moduledoc false

  use Tuist.MCP.Tool,
    name: "list_bazel_invocation_logs",
    title: "List Bazel Invocation Logs",
    read_only_hint: true,
    authorize: [action: :read, category: :build],
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string", "description" => "The account handle."},
        "project_handle" => %{"type" => "string", "description" => "The project handle."},
        "invocation_id" => %{"type" => "string", "description" => "The Bazel invocation identifier."},
        "stream" => %{
          "type" => "string",
          "enum" => ["stdout", "stderr"],
          "description" => "Only return chunks from this stream. Test logs are always stdout."
        },
        "source" => %{
          "type" => "string",
          "enum" => ["progress", "test_log"],
          "description" =>
            "Only return Build Event Protocol progress output (`progress`) or test.log artifacts (`test_log`)."
        },
        "target_label" => %{
          "type" => "string",
          "description" =>
            "Only return the test logs of this exact Bazel target label, such as `//foo:bar_test`. Progress output is not attributed to targets."
        },
        "errors" => %{
          "type" => "boolean",
          "description" =>
            "Only return test logs of failed attempts and stderr progress chunks containing a line that Bazel's reporter starts with `ERROR:`, `FAIL:` or `TIMEOUT:`."
        },
        "page" => %{"type" => "integer", "description" => "Page number, defaulting to 1."},
        "page_size" => %{"type" => "integer", "description" => "Results per page, up to 100."}
      },
      "required" => ["account_handle", "project_handle", "invocation_id"]
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "logs" => %{
          "type" => "array",
          "items" => Tuist.MCP.Components.Tools.BazelInvocationLog.schema()
        },
        "pagination_metadata" => Tuist.MCP.Tool.pagination_metadata_schema()
      },
      "required" => ["logs", "pagination_metadata"],
      "additionalProperties" => false
    }

  alias Tuist.Bazel
  alias Tuist.MCP.Components.Tools.BazelInvocationLog
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description do
    "List the sanitized logs captured for a Bazel invocation in execution order: bounded Build Event Protocol progress output and test.log artifacts. Filter by stream, source, test target, or errors. Test logs carry their target label and attempt status; progress output is not attributed to targets, so failed actions' own output, by target, is available from the Bazel build step tools."
  end

  def execute(_conn, %{"invocation_id" => invocation_id} = args, project) do
    {logs, meta} =
      Bazel.list_invocation_logs(
        project.id,
        invocation_id,
        %{
          order_by: [:sequence_number],
          order_directions: [:asc],
          page: MCPTool.page(args),
          page_size: MCPTool.page_size(args)
        },
        stream: Map.get(args, "stream"),
        source: Map.get(args, "source"),
        target_label: Map.get(args, "target_label"),
        errors: Map.get(args, "errors") == true
      )

    {:ok,
     %{
       logs: Enum.map(logs, &BazelInvocationLog.json/1),
       pagination_metadata: MCPTool.pagination_metadata(meta)
     }}
  end
end
