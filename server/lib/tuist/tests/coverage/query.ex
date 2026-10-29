defmodule Tuist.Tests.Coverage.Query do
  @moduledoc """
  The coverage reads the API (`TuistWeb.API.CoverageController`) and the MCP
  tools share, shaped by `Tuist.Tests.Coverage.Report`: a commit, a branch
  read as its latest complete commit (`History.latest_complete_commit/2`), a
  commit's files a page at a time, and one file. Each returns `{:ok, data}`
  or `{:error, message}` when what it reads is not found.
  """

  alias Tuist.Environment
  alias Tuist.Projects.Project
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.Coverage.History
  alias Tuist.Tests.Coverage.Report

  @file_sorts %{"coverage" => :coverage, "path" => :path}
  @sort_orders %{"asc" => :asc, "desc" => :desc}

  @doc "The commit's coverage with its targets."
  def commit(%Project{} = project, sha) do
    case Commits.summary(project.id, sha) do
      nil -> {:error, commit_not_found(sha)}
      summary -> {:ok, Report.commit(summary, Commits.targets(project.id, sha))}
    end
  end

  @doc """
  The coverage of the branch's latest complete commit, with the branch; the
  project's default branch when `branch` is nil or empty.
  """
  def branch(%Project{} = project, branch) do
    branch = branch_or_default(project, branch)

    with {:ok, sha} <- latest_complete_commit(project, branch),
         {:ok, coverage} <- commit(project, sha) do
      {:ok, Map.put(coverage, :branch, branch)}
    end
  end

  @doc """
  The commit a read is about: `git_commit_sha` when given, otherwise the
  latest complete commit of `branch` or of the project's default branch.
  """
  def resolve_commit(%Project{} = project, opts) do
    case Keyword.get(opts, :git_commit_sha) do
      sha when sha not in [nil, ""] -> {:ok, sha}
      _ -> latest_complete_commit(project, branch_or_default(project, Keyword.get(opts, :branch)))
    end
  end

  @doc """
  One page of the commit's files (`page`, `page_size`), least covered first
  unless `sort_by` (`coverage` or `path`) and `sort_order` (`asc` or `desc`)
  say otherwise; `search` keeps the paths containing it, ignoring case.
  """
  def files(%Project{} = project, sha, opts) do
    page = Keyword.fetch!(opts, :page)
    page_size = Keyword.fetch!(opts, :page_size)

    sort =
      {Map.get(@file_sorts, Keyword.get(opts, :sort_by), :coverage),
       Map.get(@sort_orders, Keyword.get(opts, :sort_order), :asc)}

    if Commits.measured?(project.id, sha) do
      {rows, count} =
        Commits.list_files(project.id, sha, page, page_size,
          search: String.trim(Keyword.get(opts, :search) || ""),
          sort: sort
        )

      {:ok,
       %{
         git_commit_sha: sha,
         files: Enum.map(rows, &Report.file_row/1),
         pagination_metadata: pagination_metadata(page, page_size, count)
       }}
    else
      {:error, commit_not_found(sha)}
    end
  end

  @doc """
  The file's coverage at the commit, its per-line counts with
  `include_lines: true`. Per-file coverage expires before the commit's
  figures do, so a commit can be found while its file is not.
  """
  def file(%Project{} = project, sha, path, opts \\ []) do
    if Commits.measured?(project.id, sha) do
      case Commits.file_detail(project.id, sha, path) do
        nil -> {:error, file_not_found(sha, path)}
        detail -> {:ok, Report.file(sha, detail, include_lines: Keyword.get(opts, :include_lines, false))}
      end
    else
      {:error, commit_not_found(sha)}
    end
  end

  defp latest_complete_commit(project, branch) do
    case History.latest_complete_commit(project, branch) do
      nil -> {:error, "No complete commit on branch #{branch} gathered coverage."}
      sha -> {:ok, sha}
    end
  end

  defp branch_or_default(project, branch) when branch in [nil, ""], do: project.default_branch
  defp branch_or_default(_project, branch), do: branch

  defp pagination_metadata(page, page_size, count) do
    total_pages = div(count + page_size - 1, page_size)

    %{
      current_page: page,
      page_size: page_size,
      total_count: count,
      total_pages: total_pages,
      has_next_page: page < total_pages,
      has_previous_page: page > 1
    }
  end

  defp commit_not_found(sha), do: "No run of commit #{sha} gathered coverage."

  defp file_not_found(sha, path),
    do:
      "No coverage of #{path} is kept for commit #{sha}. Either no run of the commit measured the file, or its per-file coverage expired: it is kept for #{Environment.coverage_retention_days().files} days."
end
