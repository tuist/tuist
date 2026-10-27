defmodule Tuist.GitHistory.Provider do
  @moduledoc """
  What a VCS provider answers for the server to complete a repository's
  commit graph when the client's checkout could not see far enough: the
  commits reachable from one, newest first, a page at a time. `connection`
  is the project's `Tuist.Projects.VCSConnection` with its installation
  preloaded.

  Commits are maps with `sha`, `parents` (first parent first) and
  `committed_at`, as `Tuist.GitHistory.record_commits/3` takes them. The
  second element says whether a later page may hold more.
  """

  @callback commits(connection :: struct(), sha :: String.t(), page :: pos_integer()) ::
              {:ok, [map()], :more | :done} | {:error, term()}
end
