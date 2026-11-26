defmodule Tuist.Tests.Coverage.Query do
  @moduledoc """
  The coverage reads the API (`TuistWeb.API.CoverageController`) and the MCP
  tools share, shaped by `Tuist.Tests.Coverage.Report`: a commit, a branch
  read as its latest complete commit (`History.latest_complete_commit/2`), a
  commit's files and targets a page at a time, one file, and the history
  behind them: a branch's commits and the runs behind a commit or branch, a
  cursor page at a time, and the branches with coverage. Each returns
  `{:ok, data}` or `{:error, message}` when what it reads is not found.
  """

  import Ecto.Query, only: [where: 3]

  alias Tuist.ClickHouseRepo
  alias Tuist.Environment
  alias Tuist.Projects.Project
  alias Tuist.Tests.Coverage
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

  @commit_statuses %{
    "measured" => "measured",
    "any" => "",
    "complete" => "complete",
    "incomplete" => "incomplete",
    "in_progress" => "in-progress",
    "not_measured" => "not-measured"
  }

  @doc """
  One page of the branch's commits, newest first, each with its status, its
  figure and its change from the complete commit before it
  (`History.commit_cursor_page/3`, as the branch page's Commits tab reads
  them); the project's default branch when `branch` is nil or empty.
  `status` (`measured` by default, `any`, `complete`, `incomplete`,
  `in_progress` or `not_measured`) and `search`, the start of a SHA, narrow
  the commits; `after` and `before` take a page's cursors.
  """
  def commits(%Project{} = project, branch, opts \\ []) do
    branch = branch_or_default(project, branch)
    status = Map.get(@commit_statuses, Keyword.get(opts, :status) || "measured", "measured")

    page =
      History.commit_cursor_page(project, branch,
        status: status,
        search: Keyword.get(opts, :search),
        after: Keyword.get(opts, :after),
        before: Keyword.get(opts, :before),
        page_size: Keyword.get(opts, :page_size, 20)
      )

    {:ok, %{branch: branch, commits: Enum.map(page.commits, &Report.commit_row/1), pagination: cursor_pagination(page)}}
  end

  @doc """
  One page of the runs behind a commit's coverage (`git_commit_sha`) or,
  otherwise, those that named a branch (the project's default branch unless
  `branch` says otherwise), newest first (`Commits.run_cursor_page/3`, as the
  Test Runs tab reads them). Runs set up to collect coverage that selective
  testing skipped whole are listed as `partial`, and runs from a dirty
  checkout as `discarded`. `scheme` keeps one scheme's runs; `after` and `before` take a
  page's cursors.
  """
  def runs(%Project{} = project, opts \\ []) do
    scope =
      case Keyword.get(opts, :git_commit_sha) do
        sha when sha not in [nil, ""] -> {:commit, sha}
        _ -> {:branch, branch_or_default(project, Keyword.get(opts, :branch))}
      end

    scheme = Keyword.get(opts, :scheme)

    page =
      Commits.run_cursor_page(project.id, scope,
        scheme: if(scheme in [nil, ""], do: nil, else: {:==, scheme}),
        after: Keyword.get(opts, :after),
        before: Keyword.get(opts, :before),
        page_size: Keyword.get(opts, :page_size, 20),
        dirty: true
      )

    {:ok, %{runs: Enum.map(page.runs, &Report.run_row/1), pagination: cursor_pagination(page)}}
  end

  @doc """
  The branches with coverage: those whose runs never named a pull request,
  the most recently measured first, the default branch leading
  (`History.branches/2`).
  """
  def branches(%Project{} = project) do
    {:ok, %{default_branch: project.default_branch, branches: History.branches(project)}}
  end

  @target_sorts ~w(coverage name files)

  @doc """
  One page of the commit's targets (`page`, `page_size`), least covered first
  unless `sort_by` (`coverage`, `name` or `files`) and `sort_order` say
  otherwise, followed by the targets its runs took from the binary cache
  without coverage counters (`measured: false`), as the Targets tab lists
  them; `search` keeps the names containing it, ignoring case.
  """
  def targets(%Project{} = project, sha, opts) do
    if Commits.measured?(project.id, sha) do
      page = Keyword.fetch!(opts, :page)
      page_size = Keyword.fetch!(opts, :page_size)
      sort_by = if Keyword.get(opts, :sort_by) in @target_sorts, do: Keyword.get(opts, :sort_by), else: "coverage"
      sort_order = Map.get(@sort_orders, Keyword.get(opts, :sort_order), :asc)
      search = opts |> Keyword.get(:search) |> Kernel.||("") |> String.trim() |> String.downcase()
      listed? = fn name -> search == "" or String.contains?(String.downcase(name), search) end

      measured =
        project.id
        |> Commits.targets(sha)
        |> Enum.filter(&listed?.(&1.name))
        |> sort_targets(sort_by, sort_order)
        |> Enum.map(&Report.target_row/1)

      unmeasured =
        for name <- Commits.unmeasured_targets(project.id, sha), listed?.(name), do: Report.unmeasured_target_row(name)

      targets = measured ++ unmeasured

      {:ok,
       %{
         git_commit_sha: sha,
         targets: Enum.slice(targets, (page - 1) * page_size, page_size),
         pagination_metadata: pagination_metadata(page, page_size, length(targets))
       }}
    else
      {:error, commit_not_found(sha)}
    end
  end

  defp sort_targets(targets, "name", direction), do: Enum.sort_by(targets, & &1.name, direction)
  defp sort_targets(targets, "files", direction), do: Enum.sort_by(targets, &{&1.files_count, &1.name}, direction)

  defp sort_targets(targets, "coverage", direction),
    do: Enum.sort_by(targets, &{&1.covered_lines / max(&1.executable_lines, 1), &1.name}, direction)

  @doc """
  A test run's own coverage: whether it was set up to collect coverage,
  whether it ran from a dirty checkout (whose coverage never joins its
  commit's), and the totals it measured (`Tuist.Tests.Coverage.run_totals_query/2`),
  null when it measured nothing.
  """
  def test_run(%{id: id, project_id: project_id} = run) do
    totals =
      project_id
      |> Coverage.run_totals_query()
      |> where([c], c.test_run_id == ^id)
      |> ClickHouseRepo.one(settings: [select_sequential_consistency: 1])

    Report.run_coverage(run, totals)
  end

  defp cursor_pagination(page) do
    %{
      has_next_page: page.has_next_page?,
      has_previous_page: page.has_previous_page?,
      start_cursor: page.start_cursor,
      end_cursor: page.end_cursor
    }
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
