defmodule Tuist.MCP.Components.Tools.GetBazelInvocationLog do
  @moduledoc false

  use Tuist.MCP.Tool,
    name: "get_bazel_invocation_log",
    title: "Get Bazel Invocation Log",
    read_only_hint: true,
    authorize: [action: :read, category: :build],
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string", "description" => "The account handle."},
        "project_handle" => %{"type" => "string", "description" => "The project handle."},
        "invocation_id" => %{"type" => "string", "description" => "The Bazel invocation identifier."},
        "invocation_log_id" => %{"type" => "string", "description" => "The invocation log identifier."}
      },
      "required" => ["account_handle", "project_handle", "invocation_id", "invocation_log_id"]
    },
    output_schema: Tuist.MCP.Components.Tools.BazelInvocationLog.schema()

  alias Tuist.Bazel
  alias Tuist.MCP.Components.Tools.BazelInvocationLog

  @impl EMCP.Tool
  def description, do: "Get one sanitized log captured for a Bazel invocation."

  def execute(_conn, %{"invocation_id" => invocation_id, "invocation_log_id" => invocation_log_id}, project) do
    case Bazel.get_invocation_log(project.id, invocation_id, invocation_log_id) do
      {:ok, log} -> {:ok, BazelInvocationLog.json(log)}
      {:error, :not_found} -> {:error, "Bazel invocation log not found: #{invocation_log_id}"}
    end
  end
end
