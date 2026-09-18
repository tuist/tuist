defmodule Tuist.GitHistory.Completion do
  @moduledoc """
  Fills in what a run's client could not tell about its Git history, from the
  VCS provider: the base branch (from the pull request), the merge base and
  the changed files (from a compare), and the commits the graph lacks between
  the head and the merge base and behind it, within the page budget.

  Everything the client did send is kept; the provider only adds. The run is
  rewritten with `history_source` `provider` (or `mixed` when the client sent
  part) and a `history_fallback_reason` naming whatever still could not be
  completed.
  """

  import Ecto.Query

  alias Tuist.ClickHouseRepo
  alias Tuist.GitHistory
  alias Tuist.Tests
  alias Tuist.Tests.Test
  alias Tuist.Tests.TestRunChangedFile

  @doc """
  Completes `run`'s history through `provider` (a `Tuist.GitHistory.Provider`)
  over `connection`. Returns the updated run.
  """
  def complete(project, connection, %Test{} = run, settings, provider) do
    pull_request_number = pull_request_number(run)
    head = run.git_commit_sha || ""
    budget = settings.provider_page_budget

    with {:ok, base_branch, notes} <- base_branch(project, connection, run, pull_request_number, provider),
         true <- head != "" || {:error, "the run has no commit sha"},
         repository_id when is_integer(repository_id) <-
           repository_id(project, run) || {:error, "the connected repository is unknown"} do
      run = %{run | git_repository_id: repository_id}
      {merge_base, notes} = compare_and_record(connection, run, base_branch, head, budget, provider, notes)
      notes = backfill_graph(connection, run, merge_base, settings, budget, provider, notes)

      Tests.update_test_history(run, %{
        git_repository_id: repository_id,
        base_branch: base_branch,
        merge_base_sha: merge_base || run.merge_base_sha || "",
        is_pull_request: run.is_pull_request == true or pull_request_number != nil,
        pull_request_number: pull_request_number || run.pull_request_number || 0,
        git_object_format: object_format(run, head),
        history_source: if(run.history_source == "client", do: "mixed", else: "provider"),
        history_fallback_reason: Enum.join(notes, "; ")
      })
    else
      {:error, reason} ->
        Tests.update_test_history(run, %{history_fallback_reason: "provider: #{format(reason)}"})
    end
  end

  # The repository the run named, else the connected one: the provider only
  # answers for the latter, and `Tuist.GitHistory.enqueue_completion/2` left
  # runs from another repository alone.
  defp repository_id(_project, %Test{git_repository_id: id}) when is_integer(id) and id > 0, do: id
  defp repository_id(project, _run), do: GitHistory.repository_id_for_connection(project)

  # The pull request number the client sent, or the one in a
  # `refs/pull/<n>/...` ref.
  defp pull_request_number(%Test{pull_request_number: number}) when is_integer(number) and number > 0, do: number

  defp pull_request_number(%Test{git_ref: ref}) when is_binary(ref) do
    case Regex.run(~r{^refs/(?:pull|merge-requests)/(\d+)/}, ref) do
      [_, number] -> String.to_integer(number)
      _ -> nil
    end
  end

  defp pull_request_number(_run), do: nil

  defp base_branch(_project, _connection, %Test{base_branch: branch}, _number, _provider)
       when is_binary(branch) and branch != "", do: {:ok, branch, []}

  defp base_branch(project, connection, _run, number, provider) when is_integer(number) do
    case provider.pull_request(connection, number) do
      {:ok, %{base_branch: branch}} -> {:ok, branch, []}
      {:error, reason} -> {:ok, project.default_branch, ["pull request #{number}: #{format(reason)}"]}
    end
  end

  defp base_branch(project, _connection, _run, _number, _provider), do: {:ok, project.default_branch, []}

  defp compare_and_record(connection, run, base_branch, head, budget, provider, notes) do
    case provider.compare(connection, base_branch, head, page_budget: budget) do
      {:ok, %{merge_base_sha: merge_base} = compare} ->
        GitHistory.record_commits(run.git_repository_id, object_format(run, head), compare.commits)
        if compare.files != [] and not changed_files_stored?(run), do: Tests.create_test_changed_files(run, compare.files)

        notes = if compare.truncated, do: notes ++ ["compare truncated by the page budget"], else: notes
        {blank_to_nil(merge_base), notes}

      {:error, reason} ->
        {nil, notes ++ ["compare #{base_branch}...#{String.slice(head, 0, 12)}: #{format(reason)}"]}
    end
  end

  # The graph needs to reach from the head back past the merge base; what the
  # compare did not cover comes from the commit listing, newest first, until
  # the window or the budget ends.
  defp backfill_graph(connection, run, merge_base, settings, budget, provider, notes) do
    start = merge_base || run.merge_base_sha

    cond do
      start in [nil, ""] ->
        notes ++ ["no merge base to walk history from"]

      GitHistory.known?(run.git_repository_id, start) and ancestry_deep_enough?(run.git_repository_id, start) ->
        notes

      true ->
        since = DateTime.add(DateTime.utc_now(), -settings.window_days * 86_400, :second)

        case provider.history(connection, start, page_budget: budget, since: since) do
          {:ok, commits} ->
            GitHistory.record_commits(run.git_repository_id, object_format(run, start), commits)
            notes

          {:error, reason} ->
            notes ++ ["history from #{String.slice(start, 0, 12)}: #{format(reason)}"]
        end
    end
  end

  # A merge base whose ancestry the graph already follows for a while needs
  # no more pages; one that dead-ends at once is a fresh start.
  defp ancestry_deep_enough?(repository_id, sha) do
    length(GitHistory.ancestors(repository_id, sha, max_depth: 50)) > 1
  end

  defp changed_files_stored?(%Test{id: id, project_id: project_id}) do
    ClickHouseRepo.exists?(from(f in TestRunChangedFile, where: f.project_id == ^project_id and f.test_run_id == ^id))
  end

  defp object_format(%Test{git_object_format: format}, _sha) when is_binary(format) and format != "", do: format
  defp object_format(_run, sha) when byte_size(sha) == 64, do: "sha256"
  defp object_format(_run, _sha), do: "sha1"

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp format(reason) when is_binary(reason), do: reason
  defp format(reason), do: inspect(reason)
end
