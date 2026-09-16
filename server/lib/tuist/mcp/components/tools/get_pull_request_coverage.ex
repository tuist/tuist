defmodule Tuist.MCP.Components.Tools.GetPullRequestCoverage do
  @moduledoc """
  A pull request's coverage against its baseline.
  """

  use Tuist.MCP.Tool,
    name: "get_pull_request_coverage",
    title: "Get Pull Request Coverage",
    read_only_hint: true,
    authorize: [action: :read, category: :test],
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string", "description" => "The account handle (organization or user)."},
        "project_handle" => %{"type" => "string", "description" => "The project handle."},
        "pull_request_number" => %{"type" => "integer", "description" => "The pull request number."},
        "test_run_id" => %{"type" => "string", "description" => "The run to compare; the newest by default."}
      },
      "required" => ["account_handle", "project_handle", "pull_request_number"]
    },
    # The formatter orders aliases after `use`, so the schema module cannot be aliased here.
    # credo:disable-for-next-line Credo.Check.Design.AliasUsage
    output_schema: Tuist.MCP.Components.Tools.CoverageSchemas.pull_request_output()

  alias Tuist.Tests
  alias Tuist.Tests.Coverage.Comparison
  alias Tuist.Tests.Coverage.History
  alias Tuist.Tests.Coverage.Report

  @impl EMCP.Tool
  def description,
    do:
      "Get a pull request's code coverage: every run of it that gathered coverage, newest first, and the comparison of one of them " <>
        "(the newest, or test_run_id) with its baseline: total delta, per-target and per-file deltas, patch coverage of the changed " <>
        "lines, and the gaps. The account_handle and project_handle can be extracted from a Tuist dashboard URL: " <>
        "#{Tuist.Environment.app_url()}/{account_handle}/{project_handle}."

  def execute(_conn, %{"pull_request_number" => number} = args, project) do
    runs = History.pull_request_runs(project.id, number)
    selected = Enum.find(runs, List.first(runs), &(&1.test_run_id == Map.get(args, "test_run_id")))

    with false <- is_nil(selected),
         {:ok, run} <- Tests.get_test(selected.test_run_id) do
      summary = %{
        partial: selected.partial,
        covered_lines: selected.covered_lines,
        executable_lines: selected.executable_lines
      }

      {:ok,
       %{
         pull_request_number: number,
         runs: Enum.map(runs, &Report.pull_request_run/1),
         comparison: Report.comparison(Comparison.compare(project, run, run_summary: summary))
       }}
    else
      _ -> {:error, "No test run of pull request ##{number} gathered coverage"}
    end
  end
end
