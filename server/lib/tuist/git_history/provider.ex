defmodule Tuist.GitHistory.Provider do
  @moduledoc """
  What a VCS provider must answer for the server to complete a run's Git
  history when the client could not: the base branch of a pull request, the
  merge base and changed files between two commits, and the commits reachable
  from one. `connection` is the project's `Tuist.Projects.VCSConnection` with
  its installation preloaded.

  Commits are maps with `sha`, `parents` and `committed_at`
  (`Tuist.GitHistory.record_commits/3`); changed files match the
  `changed_files` items of the test run API (`path`, `previous_path`,
  `status`, `git_blob_id`, `hunks`, `truncated`).
  """

  @callback pull_request(connection :: struct(), number :: pos_integer()) ::
              {:ok, %{base_branch: String.t(), head_sha: String.t(), base_sha: String.t()}} | {:error, term()}

  @callback compare(connection :: struct(), base :: String.t(), head :: String.t(), opts :: keyword()) ::
              {:ok, %{merge_base_sha: String.t(), commits: [map()], files: [map()], truncated: boolean()}}
              | {:error, term()}

  @callback history(connection :: struct(), sha :: String.t(), opts :: keyword()) ::
              {:ok, [map()]} | {:error, term()}
end
