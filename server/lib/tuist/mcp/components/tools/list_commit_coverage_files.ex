defmodule Tuist.MCP.Components.Tools.ListCommitCoverageFiles do
  @moduledoc """
  A commit's files with their coverage, least covered first.
  """

  use Tuist.MCP.Tool,
    name: "list_commit_coverage_files",
    title: "List Commit Coverage Files",
    read_only_hint: true,
    feature: :coverage,
    authorize: [action: :read, category: :test],
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string", "description" => "The account handle (organization or user)."},
        "project_handle" => %{"type" => "string", "description" => "The project handle."},
        "git_commit_sha" => %{"type" => "string", "description" => "The commit SHA."},
        "page" => %{"type" => "integer", "description" => "Page number (default: 1)."},
        "page_size" => %{"type" => "integer", "description" => "Results per page (default: 20, max: 100)."}
      },
      "required" => ["account_handle", "project_handle", "git_commit_sha"]
    },
    # The formatter orders aliases after `use`, so the schema module cannot be aliased here.
    # credo:disable-for-next-line Credo.Check.Design.AliasUsage
    output_schema: Tuist.MCP.Components.Tools.CoverageSchemas.files_output()

  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.Report

  @impl EMCP.Tool
  def description,
    do:
      "List a commit's product files with their line coverage, least covered first: the union of every run that measured the " <>
        "commit, so a line is covered when any run covered it. Use get_commit_coverage_file for one file's lines, and " <>
        "list_test_run_coverage_files for what a single run measured. " <>
        "The account_handle and project_handle can be extracted from a Tuist dashboard URL: #{Tuist.Environment.app_url()}/{account_handle}/{project_handle}."

  def execute(_conn, %{"git_commit_sha" => sha} = args, project) do
    page = MCPTool.page(args)
    page_size = MCPTool.page_size(args)
    {files, count} = Commits.list_files(project.id, sha, page, page_size)
    total_pages = max(1, ceil(count / page_size))

    {:ok,
     %{
       files: Enum.map(files, &Report.file/1),
       pagination_metadata: %{
         has_next_page: page < total_pages,
         has_previous_page: page > 1,
         total_count: count,
         total_pages: total_pages,
         current_page: page,
         page_size: page_size
       }
     }}
  end
end
