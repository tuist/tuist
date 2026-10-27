defmodule Tuist.GitHistory.Providers.GitHub do
  @moduledoc """
  `Tuist.GitHistory.Provider` over GitHub's commits listing, through the
  project's GitHub App installation. The listing reads commit objects, so a
  pull request's merge commit (`refs/pull/<n>/merge`) is answered like any
  other while GitHub keeps it.
  """
  @behaviour Tuist.GitHistory.Provider

  alias Tuist.GitHub.Client

  @page_size 100

  @impl true
  def commits(connection, sha, page) do
    case Client.list_commits(%{
           repository_full_handle: connection.repository_full_handle,
           installation: connection.github_app_installation,
           sha: sha,
           page: page
         }) do
      {:ok, commits} when is_list(commits) ->
        {:ok, Enum.flat_map(commits, &commit/1), if(length(commits) < @page_size, do: :done, else: :more)}

      {:ok, other} ->
        {:error, {:unexpected_response, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp commit(%{"sha" => sha} = commit) when is_binary(sha) do
    case DateTime.from_iso8601(get_in(commit, ["commit", "committer", "date"]) || "") do
      {:ok, committed_at, _offset} ->
        [%{sha: sha, parents: Enum.map(commit["parents"] || [], & &1["sha"]), committed_at: committed_at}]

      _ ->
        []
    end
  end

  defp commit(_commit), do: []
end
