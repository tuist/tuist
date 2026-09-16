defmodule Tuist.Tests.Coverage.History do
  @moduledoc """
  Coverage over the project's history: the coverage of a branch commit by
  commit, the newest coverage of every branch, and the pull requests that
  gathered coverage.

  Only full runs make a branch's figure; a partial run describes the tests
  it ran and nothing else. A commit with several full runs of a scheme is
  represented by the newest, and figures are always per scheme, since two
  schemes compile different sets of files and pooling them counts shared
  files twice.
  """

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.Projects.Project
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Test

  @doc """
  The schemes with full runs on the branch in the period, most runs first,
  each with its run count.
  """
  def schemes(project_id, branch, opts \\ []) do
    ClickHouseRepo.all(
      from(c in subquery(Coverage.full_run_totals_query(project_id)),
        join: t in subquery(runs_query(project_id, branch, opts)),
        on: t.id == c.test_run_id,
        group_by: c.scheme,
        select: %{scheme: c.scheme, runs_count: count(c.test_run_id)},
        order_by: [desc: count(c.test_run_id), asc: c.scheme]
      )
    )
  end

  @doc "The branches with a full run in the period, the most recently run first."
  def branch_names(project_id, opts \\ []) do
    ClickHouseRepo.all(
      from(c in subquery(Coverage.full_run_totals_query(project_id)),
        join: t in subquery(runs_query(project_id, nil, opts)),
        on: t.id == c.test_run_id,
        group_by: t.git_branch,
        select: t.git_branch,
        order_by: [desc: max(t.ran_at)]
      )
    )
  end

  @doc """
  One point per commit of the branch with a full run of the scheme in the
  period, oldest first: the commit, the newest run's id and time, and the
  totals. `since` and `until` bound the period (`NaiveDateTime`).
  """
  def branch_points(project_id, branch, scheme, opts \\ []) do
    project_id
    |> points_query(branch, scheme, opts)
    |> order_by([c, t], asc: max(t.ran_at))
    |> ClickHouseRepo.all()
    |> Enum.map(&with_coverage/1)
  end

  @doc "The newest full run of the scheme on the branch, with its totals, or nil."
  def latest(project_id, branch, scheme, opts \\ []) do
    project_id
    |> points_query(branch, scheme, opts)
    |> order_by([c, t], desc: max(t.ran_at))
    |> limit(1)
    |> ClickHouseRepo.one()
    |> case do
      nil -> nil
      point -> with_coverage(point)
    end
  end

  @doc """
  Every branch with a full run of the scheme in the period, newest run
  first, with that run's totals and the branch's difference from the
  project's default branch (`delta`, nil when the default branch has none).
  """
  def branches(%Project{id: project_id, default_branch: default_branch}, scheme, opts \\ []) do
    branches =
      from(p in subquery(points_query(project_id, nil, scheme, opts)),
        group_by: p.git_branch,
        select: %{
          git_branch: p.git_branch,
          test_run_id: type(fragment("argMax(?, ?)", p.test_run_id, p.ran_at), Ecto.UUID),
          git_commit_sha: fragment("argMax(?, ?)", p.git_commit_sha, p.ran_at),
          ran_at: max(p.ran_at),
          covered_lines: fragment("argMax(?, ?)", p.covered_lines, p.ran_at),
          executable_lines: fragment("argMax(?, ?)", p.executable_lines, p.ran_at)
        },
        order_by: [desc: max(p.ran_at)]
      )
      |> ClickHouseRepo.all()
      |> Enum.map(&with_coverage/1)

    default = Enum.find(branches, &(&1.git_branch == default_branch))

    Enum.map(branches, fn branch ->
      Map.put(branch, :delta, if(default, do: Float.round(branch.coverage - default.coverage, 1)))
    end)
  end

  @doc """
  The pull requests with a run that gathered coverage in the period, newest
  run first: one row per pull request and scheme, with the newest run's
  totals, whether it was partial, and the run's base branch. Paginated with
  `page` and `page_size`; returns `{rows, total_count}`.
  """
  def pull_requests(project_id, opts \\ []) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 20)

    runs =
      from(t in runs_query(project_id, nil, opts),
        where: t.is_pull_request == true
      )

    grouped =
      from(c in subquery(Coverage.run_totals_query(project_id)),
        join: t in subquery(runs),
        on: t.id == c.test_run_id,
        group_by: [t.pull_request_number, t.scheme],
        select: %{
          pull_request_number: t.pull_request_number,
          scheme: t.scheme,
          test_run_id: type(fragment("argMax(?, ?)", c.test_run_id, t.ran_at), Ecto.UUID),
          git_branch: fragment("argMax(?, ?)", t.git_branch, t.ran_at),
          base_branch: fragment("argMax(?, ?)", t.base_branch, t.ran_at),
          git_commit_sha: fragment("argMax(?, ?)", t.git_commit_sha, t.ran_at),
          ran_at: max(t.ran_at),
          partial: fragment("argMax(?, ?)", c.partial, t.ran_at),
          covered_lines: fragment("argMax(?, ?)", c.covered_lines, t.ran_at),
          executable_lines: fragment("argMax(?, ?)", c.executable_lines, t.ran_at)
        }
      )

    [rows, count] =
      Tuist.Tasks.parallel_tasks([
        fn ->
          from(r in subquery(grouped),
            order_by: [desc: r.ran_at, asc: r.pull_request_number, asc: r.scheme],
            limit: ^page_size,
            offset: ^((page - 1) * page_size)
          )
          |> ClickHouseRepo.all()
          |> Enum.map(&with_coverage/1)
        end,
        fn -> ClickHouseRepo.one(from(r in subquery(grouped), select: count(r.test_run_id))) || 0 end
      ])

    {rows, count}
  end

  @doc """
  The runs of one pull request that gathered coverage, newest first, across
  schemes: what its page lists.
  """
  def pull_request_runs(project_id, pull_request_number, opts \\ []) do
    runs =
      from(t in runs_query(project_id, nil, opts),
        where: t.is_pull_request == true and t.pull_request_number == ^pull_request_number
      )

    from(c in subquery(Coverage.run_totals_query(project_id)),
      join: t in subquery(runs),
      on: t.id == c.test_run_id,
      select: %{
        test_run_id: c.test_run_id,
        scheme: t.scheme,
        git_branch: t.git_branch,
        base_branch: t.base_branch,
        git_commit_sha: t.git_commit_sha,
        ran_at: t.ran_at,
        partial: c.partial,
        covered_lines: c.covered_lines,
        executable_lines: c.executable_lines
      },
      order_by: [desc: t.ran_at]
    )
    |> ClickHouseRepo.all()
    |> Enum.map(&with_coverage/1)
  end

  # The newest full run of the scheme per commit, on one branch or on every
  # branch (`nil`).
  defp points_query(project_id, branch, scheme, opts) do
    from(c in subquery(Coverage.full_run_totals_query(project_id)),
      join: t in subquery(runs_query(project_id, branch, opts)),
      on: t.id == c.test_run_id,
      where: c.scheme == ^scheme,
      group_by: [t.git_branch, t.git_commit_sha],
      select: %{
        git_branch: t.git_branch,
        git_commit_sha: t.git_commit_sha,
        test_run_id: type(fragment("argMax(?, ?)", c.test_run_id, t.ran_at), Ecto.UUID),
        ran_at: max(t.ran_at),
        covered_lines: fragment("argMax(?, ?)", c.covered_lines, t.ran_at),
        executable_lines: fragment("argMax(?, ?)", c.executable_lines, t.ran_at)
      }
    )
  end

  # One row per run, whatever the history rewrites added: `test_runs` keeps
  # a row per update and the newest carries the run's current history.
  defp runs_query(project_id, branch, opts) do
    query =
      from(t in Test,
        where: t.project_id == ^project_id,
        group_by: t.id,
        select: %{
          id: t.id,
          git_branch: fragment("any(?)", t.git_branch),
          git_commit_sha: fragment("any(?)", t.git_commit_sha),
          scheme: fragment("any(?)", t.scheme),
          ran_at: min(t.ran_at),
          is_pull_request: fragment("argMax(?, ?)", t.is_pull_request, t.inserted_at),
          pull_request_number: fragment("argMax(?, ?)", t.pull_request_number, t.inserted_at),
          base_branch: fragment("argMax(?, ?)", t.base_branch, t.inserted_at)
        }
      )

    query = if branch, do: where(query, [t], t.git_branch == ^branch), else: query

    query =
      case Keyword.get(opts, :since) do
        nil -> query
        since -> where(query, [t], t.ran_at >= ^since)
      end

    case Keyword.get(opts, :until) do
      nil -> query
      until -> where(query, [t], t.ran_at <= ^until)
    end
  end

  defp with_coverage(row), do: Map.put(row, :coverage, Coverage.percentage(row.covered_lines, row.executable_lines))
end
