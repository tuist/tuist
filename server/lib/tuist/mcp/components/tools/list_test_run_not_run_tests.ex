defmodule Tuist.MCP.Components.Tools.ListTestRunNotRunTests do
  @moduledoc """
  The tests a run could have executed and left out.
  """

  use Tuist.MCP.Tool,
    name: "list_test_run_not_run_tests",
    title: "List Test Run Not Run Tests",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "test_run_id" => %{"type" => "string", "description" => "The ID of the test run."},
        "page" => %{"type" => "integer", "description" => "Page number (default: 1)."},
        "page_size" => %{"type" => "integer", "description" => "Results per page (default: 20, max: 100)."}
      },
      "required" => ["test_run_id"]
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "enumerated_test_count" => %{"type" => "integer", "description" => "Tests the run could have executed."},
        "enabled_test_count" => %{"type" => "integer", "description" => "Those the scheme or test plan enables."},
        "not_run_test_count" => %{"type" => "integer", "description" => "Enabled tests the run left out."},
        "tests" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "test_case_id" => %{"type" => "string"},
              "module_name" => %{"type" => "string"},
              "suite_name" => %{"type" => "string"},
              "name" => %{"type" => "string"}
            },
            "required" => ["test_case_id", "module_name", "suite_name", "name"],
            "additionalProperties" => false
          }
        }
      },
      "required" => ["enumerated_test_count", "enabled_test_count", "not_run_test_count", "tests"],
      "additionalProperties" => false
    }

  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Tests
  alias Tuist.Tests.Enumeration

  @impl EMCP.Tool
  def description,
    do:
      "List the tests a test run could have executed and left out. The client lists a run's candidate tests without " <>
        "running any, whatever the run's filters were, so on a selective run this is what the selection skipped. " <>
        "Fails when the run's client did not enumerate its tests."

  def execute(conn, %{"test_run_id" => test_run_id} = args) do
    with {:ok, run, _project} <-
           MCPTool.load_and_authorize(
             Tests.get_test(test_run_id),
             conn.assigns,
             :read,
             :test,
             "Test run not found: #{test_run_id}"
           ) do
      case Enumeration.summary(run) do
        nil ->
          {:error, "The tests of run #{test_run_id} were not enumerated."}

        summary ->
          tests = Enumeration.list_not_run(run, page: MCPTool.page(args), page_size: MCPTool.page_size(args))
          {:ok, Enumeration.payload(summary, tests)}
      end
    end
  end
end
