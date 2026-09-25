defmodule Tuist.MCP.Components.Tools.GetCommitCoverageFile do
  @moduledoc """
  One file's coverage at a commit, line by line.
  """

  use Tuist.MCP.Tool,
    name: "get_commit_coverage_file",
    title: "Get Commit Coverage File",
    read_only_hint: true,
    feature: :coverage,
    authorize: [action: :read, category: :test],
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string", "description" => "The account handle (organization or user)."},
        "project_handle" => %{"type" => "string", "description" => "The project handle."},
        "git_commit_sha" => %{"type" => "string", "description" => "The commit SHA."},
        "path" => %{"type" => "string", "description" => "The file's repository-relative path."}
      },
      "required" => ["account_handle", "project_handle", "git_commit_sha", "path"]
    },
    # The formatter orders aliases after `use`, so the schema module cannot be aliased here.
    # credo:disable-for-next-line Credo.Check.Design.AliasUsage
    output_schema: Tuist.MCP.Components.Tools.CoverageSchemas.file_detail()

  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.Report

  @impl EMCP.Tool
  def description,
    do:
      "Get one file's coverage at a commit: every executable line with its execution count across the runs that measured the " <>
        "commit, the ranges of lines no test ran, and its functions. Test code is not reported. " <>
        "The account_handle and project_handle can be extracted from a Tuist dashboard URL: #{Tuist.Environment.app_url()}/{account_handle}/{project_handle}."

  def execute(_conn, %{"git_commit_sha" => sha, "path" => path}, project) do
    case Commits.file_detail(project.id, sha, path) do
      nil -> {:error, "Commit #{sha} has no coverage for #{path}"}
      detail -> {:ok, Report.file_detail(detail)}
    end
  end
end
