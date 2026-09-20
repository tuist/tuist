defmodule Tuist.MCP.Components.Tools.ListTestCoverageEvidenceFiles do
  @moduledoc """
  The files a test's coverage evidence holds in a run.
  """

  use Tuist.MCP.Tool,
    name: "list_test_coverage_evidence_files",
    title: "List Test Coverage Evidence Files",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "test_run_id" => %{"type" => "string", "description" => "The ID of the test run."},
        "module" => %{"type" => "string", "description" => "The test target."},
        "suite" => %{"type" => "string", "description" => "The test's suite; empty outside any."},
        "name" => %{"type" => "string", "description" => "The test's name, e.g. testExample()."}
      },
      "required" => ["test_run_id", "module", "name"]
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "files" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "path" => %{"type" => "string"},
              "scope" => %{
                "type" => "string",
                "description" => "The narrowest scope that holds the file: test, suite or target."
              },
              "git_blob_id" => %{"type" => "string"}
            },
            "required" => ["path", "scope", "git_blob_id"],
            "additionalProperties" => false
          }
        }
      },
      "required" => ["files"],
      "additionalProperties" => false
    }

  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Tests
  alias Tuist.Tests.Coverage.Evidence

  @impl EMCP.Tool
  def description,
    do:
      "List the files a test executed in a run: the test's own evidence, then what its suite ran around its tests, then " <>
        "the rest of its target's. A test without evidence of its own still gets its suite's and its target's."

  def execute(conn, %{"test_run_id" => test_run_id, "module" => module_name, "name" => name} = args) do
    with {:ok, run, _project} <-
           MCPTool.load_and_authorize(
             Tests.get_test(test_run_id),
             conn.assigns,
             :read,
             :test,
             "Test run not found: #{test_run_id}"
           ) do
      files = Evidence.files(run, module_name, Map.get(args, "suite", ""), name)
      {:ok, %{files: Enum.map(files, &Map.update!(&1, :git_blob_id, fn blob -> blob || "" end))}}
    end
  end
end
