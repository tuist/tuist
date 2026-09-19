defmodule Tuist.GitHistory.Providers.GitHub do
  @moduledoc """
  `Tuist.GitHistory.Provider` over the GitHub REST API, through the project's
  GitHub App installation: the pull request endpoint for the base branch, the
  compare endpoint for the merge base, the commits between two points and the
  changed files with their patches, and the commits listing to walk history
  further back. Every call is bounded by the page budget the caller passes.
  """
  @behaviour Tuist.GitHistory.Provider

  alias Tuist.GitHub.Client

  @impl true
  def pull_request(connection, number) do
    case Client.get_pull_request(%{
           repository_full_handle: connection.repository_full_handle,
           installation: connection.github_app_installation,
           pr_number: number
         }) do
      {:ok, %{"base" => %{"ref" => base_branch, "sha" => base_sha}, "head" => %{"sha" => head_sha}}} ->
        {:ok, %{base_branch: base_branch, base_sha: base_sha, head_sha: head_sha}}

      {:ok, other} ->
        {:error, {:unexpected_response, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl true
  def compare(connection, base, head, opts \\ []) do
    page_budget = Keyword.get(opts, :page_budget, 1)

    with {:ok, first} <- compare_page(connection, base, head, 1) do
      total = first["total_commits"] || length(first["commits"] || [])
      commits = commits_from(first["commits"] || [])

      {commits, truncated} =
        collect_compare_pages(connection, base, head, commits, total, 2, page_budget)

      {:ok,
       %{
         merge_base_sha: get_in(first, ["merge_base_commit", "sha"]) || "",
         commits: commits,
         files: files_from(first["files"] || []),
         truncated: truncated or length(first["files"] || []) >= 300
       }}
    end
  end

  defp compare_page(connection, base, head, page) do
    Client.compare_commits(%{
      repository_full_handle: connection.repository_full_handle,
      installation: connection.github_app_installation,
      base: base,
      head: head,
      page: page
    })
  end

  defp collect_compare_pages(_connection, _base, _head, commits, total, _page, _budget) when length(commits) >= total,
    do: {commits, false}

  defp collect_compare_pages(_connection, _base, _head, commits, _total, page, budget) when page > budget,
    do: {commits, true}

  defp collect_compare_pages(connection, base, head, commits, total, page, budget) do
    case compare_page(connection, base, head, page) do
      {:ok, %{"commits" => []}} ->
        {commits, false}

      {:ok, %{"commits" => more}} ->
        collect_compare_pages(connection, base, head, commits ++ commits_from(more), total, page + 1, budget)

      {:error, _reason} ->
        {commits, true}
    end
  end

  @impl true
  def history(connection, sha, opts \\ []) do
    page_budget = Keyword.get(opts, :page_budget, 1)
    since = Keyword.get(opts, :since)
    collect_history(connection, sha, since, 1, page_budget, [])
  end

  defp collect_history(_connection, _sha, _since, page, budget, acc) when page > budget, do: {:ok, acc}

  defp collect_history(connection, sha, since, page, budget, acc) do
    case Client.list_commits(%{
           repository_full_handle: connection.repository_full_handle,
           installation: connection.github_app_installation,
           sha: sha,
           page: page
         }) do
      {:ok, []} ->
        {:ok, acc}

      {:ok, commits} when is_list(commits) ->
        commits = commits_from(commits)
        {kept, past_window} = split_at_window(commits, since)

        if past_window or length(commits) < 100 do
          {:ok, acc ++ kept}
        else
          collect_history(connection, sha, since, page + 1, budget, acc ++ kept)
        end

      {:ok, other} ->
        {:error, {:unexpected_response, other}}

      {:error, reason} when acc == [] ->
        {:error, reason}

      {:error, _reason} ->
        {:ok, acc}
    end
  end

  defp split_at_window(commits, nil), do: {commits, false}

  defp split_at_window(commits, since) do
    kept = Enum.filter(commits, &(DateTime.compare(&1.committed_at, since) != :lt))
    {kept, length(kept) < length(commits)}
  end

  defp commits_from(commits) do
    Enum.flat_map(commits, fn commit ->
      with sha when is_binary(sha) <- commit["sha"],
           {:ok, committed_at, _offset} <- DateTime.from_iso8601(get_in(commit, ["commit", "committer", "date"]) || "") do
        [%{sha: sha, parents: Enum.map(commit["parents"] || [], & &1["sha"]), committed_at: committed_at}]
      else
        _ -> []
      end
    end)
  end

  defp files_from(files) do
    Enum.map(files, fn file ->
      %{
        path: file["filename"],
        previous_path: file["previous_filename"],
        status: status(file["status"]),
        git_blob_id: if(file["status"] == "removed", do: nil, else: file["sha"]),
        hunks: hunks(file["patch"]),
        truncated: is_nil(file["patch"]) and file["status"] != "removed"
      }
    end)
  end

  defp status("removed"), do: "deleted"
  defp status("renamed"), do: "renamed"
  defp status("added"), do: "added"
  defp status(_), do: "modified"

  # The head-side ranges of a unified diff's hunk headers: `@@ -a,b +c,d @@`
  # covers lines c..c+d-1 at the head; a hunk with d = 0 only removed lines.
  defp hunks(nil), do: []

  defp hunks(patch) do
    ~r/^@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/m
    |> Regex.scan(patch)
    |> Enum.flat_map(fn
      [_, start, ""] ->
        [%{start: String.to_integer(start), end: String.to_integer(start)}]

      [_, start] ->
        [%{start: String.to_integer(start), end: String.to_integer(start)}]

      [_, _start, "0"] ->
        []

      [_, start, count] ->
        [%{start: String.to_integer(start), end: String.to_integer(start) + String.to_integer(count) - 1}]
    end)
  end
end
