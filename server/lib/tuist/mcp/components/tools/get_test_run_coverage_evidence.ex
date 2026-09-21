defmodule Tuist.MCP.Components.Tools.GetTestRunCoverageEvidence do
  @moduledoc """
  How much of a test run has per-test coverage evidence, and its scopes.
  """

  use Tuist.MCP.Tool,
    name: "get_test_run_coverage_evidence",
    title: "Get Test Run Coverage Evidence",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "test_run_id" => %{"type" => "string", "description" => "The ID of the test run."},
        "kind" => %{
          "type" => "string",
          "enum" => ["test", "suite", "target"],
          "description" => "The scopes to list (default: test)."
        },
        "page" => %{"type" => "integer", "description" => "Page number (default: 1)."},
        "page_size" => %{"type" => "integer", "description" => "Results per page (default: 20, max: 100)."}
      },
      "required" => ["test_run_id"]
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "summary" => %{
          "type" => "object",
          "properties" => %{
            "tests" => %{"type" => "integer", "description" => "Tests with evidence of their own."},
            "tests_without_evidence" => %{
              "type" => "integer",
              "description" => "Tests that ran without evidence of their own; their target's evidence is all they have."
            },
            "suites" => %{"type" => "integer"},
            "targets" => %{"type" => "integer"},
            "files" => %{"type" => "integer", "description" => "Files some scope covers."},
            "median_files_per_test" => %{"type" => "integer"},
            "max_files_per_test" => %{"type" => "integer"}
          },
          "required" => [
            "tests",
            "tests_without_evidence",
            "suites",
            "targets",
            "files",
            "median_files_per_test",
            "max_files_per_test"
          ],
          "additionalProperties" => false
        },
        "scopes" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "kind" => %{"type" => "string"},
              "scope_id" => %{
                "type" => "string",
                "description" =>
                  "The scope spelled for reading: Module/Suite/name for a test, Module/Suite for a suite, Module for a target. Not to be split (a module or a name may hold slashes); use module, suite and name."
              },
              "module" => %{"type" => "string"},
              "suite" => %{"type" => "string"},
              "name" => %{"type" => "string"},
              "files_count" => %{"type" => "integer"}
            },
            "required" => ["kind", "scope_id", "module", "suite", "name", "files_count"],
            "additionalProperties" => false
          }
        },
        "total_count" => %{"type" => "integer", "description" => "Scopes of the kind in the run."}
      },
      "required" => ["summary", "scopes", "total_count"],
      "additionalProperties" => false
    }

  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Tests
  alias Tuist.Tests.Coverage.Evidence

  @impl EMCP.Tool
  def description,
    do:
      "Get a test run's per-test coverage evidence: which files each test executed, as the client's coverage observer " <>
        "recorded it (what test selection plans over). Returns how much of the run has evidence and a page of its " <>
        "scopes of one kind, those covering most files first. Use list_test_coverage_evidence_files for one test's " <>
        "files and list_tests_covering_file for the tests behind a file."

  def execute(conn, %{"test_run_id" => test_run_id} = args) do
    with {:ok, run, project} <-
           MCPTool.load_and_authorize(
             Tests.get_test(test_run_id),
             conn.assigns,
             :read,
             :test,
             "Test run not found: #{test_run_id}"
           ),
         :ok <- MCPTool.require_feature(project, :coverage) do
      case Evidence.summary(run) do
        nil ->
          {:error, "The test run gathered no coverage evidence: #{test_run_id}"}

        summary ->
          {scopes, count} =
            Evidence.list_scopes(run,
              kind: Map.get(args, "kind", "test"),
              page: MCPTool.page(args),
              page_size: MCPTool.page_size(args)
            )

          {:ok,
           %{
             summary: summary,
             scopes: Enum.map(scopes, &Evidence.scope_payload/1),
             total_count: count
           }}
      end
    end
  end
end
