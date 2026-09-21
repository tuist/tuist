defmodule Tuist.MCP.Components.Tools.ListTestsCoveringFile do
  @moduledoc """
  The tests of a run whose coverage evidence holds a file.
  """

  use Tuist.MCP.Tool,
    name: "list_tests_covering_file",
    title: "List Tests Covering File",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "test_run_id" => %{"type" => "string", "description" => "The ID of the test run."},
        "path" => %{"type" => "string", "description" => "The file's repository-relative path."},
        "line" => %{
          "type" => "integer",
          "description" =>
            "Only the tests that ran this line. A test whose evidence only knows the file stays, since it may have."
        }
      },
      "required" => ["test_run_id", "path"]
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "tests" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "test_case_id" => %{"type" => "string"},
              "module_name" => %{"type" => "string"},
              "suite_name" => %{"type" => "string"},
              "name" => %{"type" => "string"},
              "lines" => %{
                "type" => ["array", "null"],
                "items" => %{"type" => "array", "items" => %{"type" => "integer"}},
                "description" =>
                  "The lines the test ran in the file, as [first, last] ranges; null when its evidence only knows the file."
              }
            },
            "required" => ["test_case_id", "module_name", "suite_name", "name", "lines"],
            "additionalProperties" => false
          }
        },
        "suites" => %{"type" => "array", "items" => %{"type" => "string"}},
        "targets" => %{"type" => "array", "items" => %{"type" => "string"}}
      },
      "required" => ["tests", "suites", "targets"],
      "additionalProperties" => false
    }

  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Tests
  alias Tuist.Tests.Coverage.Evidence

  @impl EMCP.Tool
  def description,
    do:
      "List the tests of a run that executed a file, by their own coverage evidence: the tests to run when the file " <>
        "changes. `suites` and `targets` name the wider scopes that hold the file; every test of those may depend on it too."

  def execute(conn, %{"test_run_id" => test_run_id, "path" => path} = args) do
    with {:ok, run, project} <-
           MCPTool.load_and_authorize(
             Tests.get_test(test_run_id),
             conn.assigns,
             :read,
             :test,
             "Test run not found: #{test_run_id}"
           ),
         :ok <- MCPTool.require_feature(project, :coverage) do
      {:ok, Evidence.covering(run, path, line: args["line"])}
    end
  end
end
