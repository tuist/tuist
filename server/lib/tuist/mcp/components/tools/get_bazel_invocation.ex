defmodule Tuist.MCP.Components.Tools.GetBazelInvocation do
  @moduledoc false

  use Tuist.MCP.Tool,
    name: "get_bazel_invocation",
    title: "Get Bazel Invocation",
    read_only_hint: true,
    authorize: [action: :read, category: :build],
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string", "description" => "The account handle."},
        "project_handle" => %{"type" => "string", "description" => "The project handle."},
        "invocation_id" => %{"type" => "string", "description" => "The Bazel invocation identifier."}
      },
      "required" => ["account_handle", "project_handle", "invocation_id"]
    },
    output_schema: Tuist.MCP.Components.Tools.BazelInvocation.schema()

  alias Tuist.Bazel
  alias Tuist.MCP.Components.Tools.BazelInvocation

  @impl EMCP.Tool
  def description, do: "Get a completed Bazel invocation and its correlated remote-cache totals."

  def execute(_conn, %{"invocation_id" => invocation_id}, project) do
    case Bazel.get_invocation(project.id, invocation_id) do
      {:ok, invocation} -> {:ok, BazelInvocation.json(invocation)}
      {:error, :not_found} -> {:error, "Bazel invocation not found: #{invocation_id}"}
    end
  end
end
