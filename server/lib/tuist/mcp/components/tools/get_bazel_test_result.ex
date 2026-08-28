defmodule Tuist.MCP.Components.Tools.GetBazelTestResult do
  @moduledoc false

  use Tuist.MCP.Tool,
    name: "get_bazel_test_result",
    title: "Get Bazel Test Result",
    read_only_hint: true,
    authorize: [action: :read, category: :build],
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string", "description" => "The account handle."},
        "project_handle" => %{"type" => "string", "description" => "The project handle."},
        "test_result_id" => %{"type" => "string", "description" => "The Bazel test-target result identifier."}
      },
      "required" => ["account_handle", "project_handle", "test_result_id"]
    },
    output_schema: Tuist.MCP.Components.Tools.BazelTestResult.schema()

  alias Tuist.Bazel
  alias Tuist.MCP.Components.Tools.BazelTestResult

  @impl EMCP.Tool
  def description, do: "Get a Bazel test-target result emitted through the Build Event Protocol."

  def execute(_conn, %{"test_result_id" => test_result_id}, project) do
    case Bazel.get_test_result(project.id, test_result_id) do
      {:ok, test_result} -> {:ok, BazelTestResult.json(test_result)}
      {:error, :not_found} -> {:error, "Bazel test result not found: #{test_result_id}"}
    end
  end
end
