defmodule TuistTestSupport.Fixtures.CoverageFixtures do
  @moduledoc """
  Test runs with code coverage, and the repository graph they sit in, for
  the tests of the coverage surfaces.
  """

  alias Tuist.GitHistory
  alias Tuist.Projects
  alias Tuist.Tests
  alias Tuist.Tests.Coverage.Commits

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
end
