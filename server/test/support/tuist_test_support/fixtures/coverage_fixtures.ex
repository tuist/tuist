defmodule TuistTestSupport.Fixtures.CoverageFixtures do
  @moduledoc """
  Test runs with code coverage, and the repository graph they sit in, for
  the tests of the coverage surfaces.
  """

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.GitHistory
  alias Tuist.GitHistory.CommitListing
  alias Tuist.GitHistory.CommitParent
  alias Tuist.GitHistory.Ref
  alias Tuist.Projects
  alias Tuist.Repo
  alias Tuist.Tests
  alias Tuist.Tests.Coverage
  alias Tuist.Tests.Coverage.Commits
  alias Tuist.Tests.CoverageFile
  alias Tuist.Tests.CoverageRun
  alias Tuist.Tests.EnumeratedTest
  alias Tuist.Tests.TestRunChangedFile

  @remote_url "https://github.com/tuist/app"

  @doc "The remote every fixture run reports, so they share one repository per account."
  def remote_url, do: @remote_url

  @doc "The account's repository for the fixture remote, created on first use."
  def repository_id(account, url \\ @remote_url), do: GitHistory.repository_id(account.id, url)

  @doc """
  A commit for `seed_history/2`: `minutes` after a fixed epoch, so a list
  reads oldest to newest.
  """
  def commit(sha, parents, minutes) do
    %{sha: sha, parents: parents, committed_at: DateTime.add(~U[2026-09-01 00:00:00Z], minutes * 60, :second)}
  end

  @doc "Stores commits (`commit/3`) in the account's fixture repository and returns its id."
  def seed_history(account, commits, opts \\ []) do
    repository_id = repository_id(account)
    GitHistory.record_commits(repository_id, Keyword.get(opts, :object_format, "sha1"), commits)

    for {branch, sha} <- Keyword.get(opts, :branch_heads, []) do
      GitHistory.record_branch_head(repository_id, branch, sha, "main")
    end

    repository_id
  end

  @doc """
  Stores a commit's file listing in the account's fixture repository, as the
  CLI uploads it from a clean checkout: what the unmeasured files are read
  against.
  """
  def seed_listing(account, sha, paths) do
    repository_id = repository_id(account)

    GitHistory.record_listing(
      repository_id,
      sha,
      Enum.map(paths, &%{path: &1, git_blob_id: "blob-" <> &1, mode: 0o100644}),
      files_count: length(paths)
    )

    repository_id
  end

  @doc """
  A covered source file for an `xcode_coverage` block: `counts` are the
  execution counts of lines 1..n.
  """
  def file(path, counts, opts \\ []) do
    %{
      path: path,
      git_blob_id: Keyword.get(opts, :git_blob_id, "blob-" <> path),
      targets: Keyword.get(opts, :targets, ["App"]),
      is_test: Keyword.get(opts, :is_test, false),
      covered_lines: Enum.count(counts, &(&1 > 0)),
      executable_lines: length(counts),
      line_numbers: Enum.to_list(1..length(counts)//1),
      execution_counts: counts,
      functions: []
    }
  end

  @doc """
  Creates a test run carrying coverage for `files` and returns it as stored.
  `attrs` override the run's fields; `:partial` marks the coverage partial.
  The run reports the fixture remote unless `git_remote_url_origin` says
  otherwise, and its commit's coverage is republished at once, as the
  `CommitWorker` would (`recompute: false` leaves that out).
  """
  def run_with_coverage(project, account, files, attrs \\ %{}) do
    {partial, attrs} = Map.pop(attrs, :partial, false)
    {recompute, attrs} = Map.pop(attrs, :recompute, true)

    {:ok, run} =
      Tests.create_test(
        Map.merge(
          %{
            id: UUIDv7.generate(),
            project_id: project.id,
            account_id: account.id,
            duration: 1000,
            status: "success",
            scheme: "App",
            git_branch: "main",
            git_commit_sha: "abc123",
            git_remote_url_origin: @remote_url,
            ran_at: NaiveDateTime.utc_now(),
            is_ci: true,
            test_modules: [],
            xcode_coverage: %{partial: partial, files: files}
          },
          attrs
        )
      )

    {:ok, run} = Tests.get_test(run.id)
    if recompute, do: recompute_commit(run)
    run
  end

  @doc "Republishes the run's commit coverage, as the `CommitWorker` does after a run reports."
  def recompute_commit(run) do
    if run.git_commit_sha not in [nil, ""] and not run.git_dirty do
      Commits.recompute(Projects.get_project_by_id(run.project_id), run.git_commit_sha)
    end
  end

  @doc """
  A run's coverage as its shards' latest reports merge it: line totals over
  its product files, and whether a report was partial. Nil when it measured
  nothing.
  """
  def run_summary(project_id, test_run_id, opts \\ []) do
    totals =
      ClickHouseRepo.one(
        from(f in subquery(merged_files(project_id, test_run_id, opts)),
          select: %{covered_lines: sum(f.covered_lines), executable_lines: sum(f.executable_lines)}
        )
      )

    case totals do
      %{executable_lines: executable} when is_integer(executable) and executable > 0 ->
        partial_rows =
          ClickHouseRepo.one(
            from(f in Coverage.report_files_for_runs(project_id, [test_run_id]),
              select: fragment("countIf(?)", f.partial)
            )
          )

        Map.put(totals, :partial, (partial_rows || 0) > 0)

      _ ->
        nil
    end
  end

  @doc "A run's targets with their line totals, least covered first."
  def targets_for_run(project_id, test_run_id, opts \\ []) do
    ClickHouseRepo.all(
      from(f in subquery(merged_files(project_id, test_run_id, opts)),
        group_by: fragment("arrayJoin(?)", f.targets),
        select: %{
          name: fragment("arrayJoin(?)", f.targets),
          files_count: count(f.path),
          covered_lines: sum(f.covered_lines),
          executable_lines: sum(f.executable_lines)
        },
        order_by: [
          asc: fragment("sum(?) / greatest(sum(?), 1)", f.covered_lines, f.executable_lines),
          asc: fragment("arrayJoin(?)", f.targets)
        ]
      )
    )
  end

  @doc "The totals each run published to `coverage_runs`, by run id, for the runs that measured something."
  def published_totals(_project_id, []), do: %{}

  def published_totals(project_id, test_run_ids) do
    from(c in CoverageRun,
      where: c.project_id == ^project_id and c.test_run_id in ^test_run_ids,
      group_by: c.test_run_id,
      having: fragment("argMax(?, ?)", c.executable_lines, c.version) > 0,
      select: %{
        test_run_id: c.test_run_id,
        covered_lines: fragment("argMax(?, ?)", c.covered_lines, c.version),
        executable_lines: fragment("argMax(?, ?)", c.executable_lines, c.version),
        partial: fragment("argMax(?, ?)", c.partial, c.version)
      }
    )
    |> ClickHouseRepo.all()
    |> Map.new(&{&1.test_run_id, Map.delete(&1, :test_run_id)})
  end

  defp merged_files(project_id, test_run_id, opts),
    do: Coverage.merged_files_query_for_runs(project_id, [test_run_id], Coverage.excluded(project_id, opts))

  @doc "The tests the run's client enumerated, as stored, in module, suite and name order."
  def enumerated_tests(%{id: test_run_id, project_id: project_id}) do
    ClickHouseRepo.all(
      from(t in EnumeratedTest,
        where: t.project_id == ^project_id and t.test_run_id == ^test_run_id,
        order_by: [t.module_name, t.suite_name, t.name],
        select: %{
          test_case_id: t.test_case_id,
          module_name: t.module_name,
          suite_name: t.suite_name,
          name: t.name,
          function_name: t.function_name,
          enabled: t.enabled
        }
      )
    )
  end

  @doc "The run's evidence rows (test, suite and target scopes), in scope and path order."
  def evidence_rows(%{id: test_run_id, project_id: project_id}) do
    ClickHouseRepo.all(
      from(f in CoverageFile,
        where: f.project_id == ^project_id and f.test_run_id == ^test_run_id and f.scope_kind != "run",
        order_by: [f.scope_kind, f.scope_id, f.path],
        select: %{
          shard_index: f.shard_index,
          scope_kind: f.scope_kind,
          scope_id: f.scope_id,
          path: f.path,
          covered_lines: f.covered_lines,
          line_numbers: f.line_numbers,
          inserted_at: f.inserted_at
        }
      )
    )
  end

  @doc "The files the run changed against its merge base, as stored."
  def changed_files(%{id: test_run_id, project_id: project_id}) do
    ClickHouseRepo.all(
      from(f in TestRunChangedFile,
        where: f.project_id == ^project_id and f.test_run_id == ^test_run_id,
        order_by: f.path,
        select: %{
          path: f.path,
          previous_path: f.previous_path,
          status: f.status,
          git_blob_id: f.git_blob_id,
          hunk_starts: f.hunk_starts,
          hunk_ends: f.hunk_ends,
          truncated: f.truncated
        }
      )
    )
  end

  @doc "The commit a ref's head is at, or nil."
  def branch_head(repository_id, name) do
    Repo.one(from(r in Ref, where: r.repository_id == ^repository_id and r.name == ^name, select: r.head_sha))
  end

  @doc "The stored listing of a commit (its file count and whether it was truncated), or nil."
  def listing(repository_id, sha) do
    Repo.one(from(l in CommitListing, where: l.repository_id == ^repository_id and l.sha == ^sha))
  end

  @doc "A commit's first parent, or nil."
  def first_parent(repository_id, sha) do
    Repo.one(
      from(p in CommitParent,
        where: p.repository_id == ^repository_id and p.child_sha == ^sha and p.position == 0,
        select: p.parent_sha
      )
    )
  end
end
