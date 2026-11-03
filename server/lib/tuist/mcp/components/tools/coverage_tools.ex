defmodule Tuist.MCP.Components.Tools.CoverageTools do
  @moduledoc """
  What the code coverage tools share: their arguments, and the flag check
  that follows the project's authorization. The reads and their shapes are
  the API's (`Tuist.Tests.Coverage.Query`).
  """

  alias Tuist.FeatureFlags

  @not_enabled "Code coverage is in early access and is not enabled for this account."

  def project_properties do
    %{
      "account_handle" => %{"type" => "string", "description" => "The account handle (organization or user)."},
      "project_handle" => %{"type" => "string", "description" => "The project handle."}
    }
  end

  def commit_properties do
    %{
      "git_commit_sha" => %{
        "type" => "string",
        "description" => "The commit to read. Takes precedence over branch."
      },
      "branch" => %{
        "type" => "string",
        "description" =>
          "The branch to read, as its latest complete commit (the newest one whose coverage pipeline signalled it finished, with a whole figure). The project's default branch when neither git_commit_sha nor branch is given."
      }
    }
  end

  def commit_options(args), do: [git_commit_sha: Map.get(args, "git_commit_sha"), branch: Map.get(args, "branch")]

  def with_coverage(project, fun) do
    if FeatureFlags.coverage_enabled?(project.account, project), do: fun.(), else: {:error, @not_enabled}
  end
end

defmodule Tuist.MCP.Components.Tools.GetCoverage do
  @moduledoc false
  use Tuist.MCP.Tool,
    name: "get_coverage",
    title: "Get Coverage",
    read_only_hint: true,
    authorize: [action: :read, category: :test],
    schema: %{
      "type" => "object",
      "properties" =>
        Map.merge(
          Tuist.MCP.Components.Tools.CoverageTools.project_properties(),
          Tuist.MCP.Components.Tools.CoverageTools.commit_properties()
        ),
      "required" => ["account_handle", "project_handle"]
    },
    output_schema:
      Tuist.MCP.Tool.json_schema(%{
        Tuist.Tests.Coverage.Schemas.branch()
        | required: Tuist.Tests.Coverage.Schemas.commit().required
      })

  alias Tuist.MCP.Components.Tools.CoverageTools
  alias Tuist.Tests.Coverage.Query

  @impl EMCP.Tool
  def description,
    do:
      "Get a project's code coverage: a commit's, or a branch's latest complete commit's (the default branch unless one is given), with its targets and measured set. `branch` is set when the coverage was read through a branch."

  def execute(_conn, args, project) do
    CoverageTools.with_coverage(project, fn ->
      case Map.get(args, "git_commit_sha") do
        sha when sha not in [nil, ""] -> Query.commit(project, sha)
        _ -> Query.branch(project, Map.get(args, "branch"))
      end
    end)
  end
end

defmodule Tuist.MCP.Components.Tools.ListCoverageFiles do
  @moduledoc false
  use Tuist.MCP.Tool,
    name: "list_coverage_files",
    title: "List Coverage Files",
    read_only_hint: true,
    authorize: [action: :read, category: :test],
    schema: %{
      "type" => "object",
      "properties" =>
        Tuist.MCP.Components.Tools.CoverageTools.project_properties()
        |> Map.merge(Tuist.MCP.Components.Tools.CoverageTools.commit_properties())
        |> Map.merge(%{
          "page" => %{"type" => "integer", "description" => "Page number (default: 1)."},
          "page_size" => %{"type" => "integer", "description" => "Results per page (default: 20, max: 100)."},
          "search" => %{"type" => "string", "description" => "Keeps the files whose path contains it, ignoring case."},
          "sort_by" => %{
            "type" => "string",
            "enum" => ["coverage", "path"],
            "description" => "What to sort the files by (default: coverage)."
          },
          "sort_order" => %{
            "type" => "string",
            "enum" => ["asc", "desc"],
            "description" => "The order to sort the files in (default: asc, least covered first)."
          }
        }),
      "required" => ["account_handle", "project_handle"]
    },
    output_schema:
      Tuist.MCP.Tool.json_schema(Tuist.Tests.Coverage.Schemas.files(Tuist.MCP.Tool.pagination_metadata_schema()))

  alias Tuist.MCP.Components.Tools.CoverageTools
  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Tests.Coverage.Query

  @impl EMCP.Tool
  def description,
    do:
      "List the product files a commit's code coverage measured, with their line coverage, least covered first by default. Reads a commit, or a branch's latest complete commit (the default branch unless one is given)."

  def execute(_conn, args, project) do
    CoverageTools.with_coverage(project, fn ->
      with {:ok, sha} <- Query.resolve_commit(project, CoverageTools.commit_options(args)) do
        Query.files(project, sha,
          page: MCPTool.page(args),
          page_size: MCPTool.page_size(args),
          search: Map.get(args, "search"),
          sort_by: Map.get(args, "sort_by"),
          sort_order: Map.get(args, "sort_order")
        )
      end
    end)
  end
end

defmodule Tuist.MCP.Components.Tools.GetCoverageFile do
  @moduledoc false
  use Tuist.MCP.Tool,
    name: "get_coverage_file",
    title: "Get Coverage File",
    read_only_hint: true,
    authorize: [action: :read, category: :test],
    schema: %{
      "type" => "object",
      "properties" =>
        Tuist.MCP.Components.Tools.CoverageTools.project_properties()
        |> Map.merge(Tuist.MCP.Components.Tools.CoverageTools.commit_properties())
        |> Map.merge(%{
          "path" => %{"type" => "string", "description" => "The file's path, relative to the repository's root."},
          "include_lines" => %{
            "type" => "boolean",
            "description" => "Whether to include every executable line and how many times it ran (default: false)."
          }
        }),
      "required" => ["account_handle", "project_handle", "path"]
    },
    output_schema: Tuist.MCP.Tool.json_schema(Tuist.Tests.Coverage.Schemas.file())

  alias Tuist.MCP.Components.Tools.CoverageTools
  alias Tuist.Tests.Coverage.Query

  @impl EMCP.Tool
  def description,
    do:
      "Get a file's code coverage at a commit, or at a branch's latest complete commit (the default branch unless one is given): its figures and functions, and its per-line execution counts with include_lines. Per-file coverage expires before a commit's figures do."

  def execute(_conn, args, project) do
    CoverageTools.with_coverage(project, fn ->
      with {:ok, sha} <- Query.resolve_commit(project, CoverageTools.commit_options(args)) do
        Query.file(project, sha, args["path"], include_lines: Map.get(args, "include_lines", false))
      end
    end)
  end
end
