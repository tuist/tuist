defmodule TuistTestSupport.Fixtures.CoverageFixtures do
  @moduledoc """
  Test runs with code coverage, for the tests of the coverage surfaces.
  """

  alias Tuist.Tests

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
  """
  def run_with_coverage(project, account, files, attrs \\ %{}) do
    {partial, attrs} = Map.pop(attrs, :partial, false)

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
            ran_at: NaiveDateTime.utc_now(),
            is_ci: true,
            test_modules: [],
            xcode_coverage: %{partial: partial, files: files}
          },
          attrs
        )
      )

    {:ok, run} = Tests.get_test(run.id)
    run
  end
end
