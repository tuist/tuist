defmodule Tuist.GitHistory.Completion do
  @moduledoc """
  Completes the commit graph behind a commit from the VCS provider where the
  client's checkout could not see. A depth-1 CI checkout uploads its head
  with the parents the commit object names and nothing behind them, so a
  walk from the head stops after one step: on a pull request's
  `refs/pull/<n>/merge` checkout that head is GitHub's merge commit, whose
  base-branch parent and pull request head are both unknown, and coverage
  then finds no measured ancestor, or a stale one through whatever the graph
  happens to hold.

  `Tuist.GitHistory.gaps/3` says where the walk stops, nearest first. Each
  gap is listed from the provider, a page of commits at a time, until the
  listing reaches a commit the graph already follows, leaves the history
  window, ends, or the page budget runs out; then the gaps are read again,
  since filling one moves the frontier. The graph itself dedupes: a commit
  stored with its parents is never a gap again. A gap the provider could not
  fill (an error, or a commit older than the window) is remembered for a
  while in `Tuist.KeyValueStore`, so later completions skip it instead of
  asking again. The first error stops the completion: a rate limit is not
  worth spending the rest of the budget on.

  Only the graph is written; the runs keep the history their client reported.
  """

  alias Tuist.GitHistory
  alias Tuist.KeyValueStore

  @unfilled_ttl to_timeout(hour: 1)
  @past_window_ttl to_timeout(day: 30)

  @doc """
  Completes the graph of `repository_id` behind `sha` through `provider` (a
  `Tuist.GitHistory.Provider`) over `connection`, within `settings`
  (`Tuist.GitHistory.settings/1`). Returns `{:ok, summary}` or
  `{:error, reason, summary}`, where the summary counts the pages spent and
  the commits recorded, and lists the gaps left.
  """
  def complete(connection, repository_id, sha, settings, provider) do
    state = %{
      connection: connection,
      repository_id: repository_id,
      provider: provider,
      since: DateTime.add(DateTime.utc_now(), -settings.window_days * 86_400, :second),
      max_depth: settings.window_commits,
      budget: settings.provider_page_budget,
      tried: MapSet.new(),
      pages: 0,
      recorded: 0
    }

    fill(sha, state)
  end

  defp fill(sha, state) do
    gaps =
      state.repository_id
      |> GitHistory.gaps(sha, since: state.since, max_depth: state.max_depth)
      |> Enum.reject(&(MapSet.member?(state.tried, &1) or unfilled?(state.repository_id, &1)))

    case gaps do
      [] ->
        {:ok, summary(state, [])}

      gaps when state.budget <= 0 ->
        {:ok, summary(state, gaps)}

      [start | _] ->
        case walk(start, 1, %{state | tried: MapSet.put(state.tried, start)}) do
          {:cont, state} -> fill(sha, state)
          {:halt, reason, state} -> {:error, reason, summary(state, gaps)}
        end
    end
  end

  defp walk(start, page, state) do
    case state.provider.commits(state.connection, start, page) do
      {:ok, commits, more} ->
        state = %{state | budget: state.budget - 1, pages: state.pages + 1}
        {in_window, past_window} = Enum.split_with(commits, &(DateTime.compare(&1.committed_at, state.since) != :lt))
        shas = Enum.map(in_window, & &1.sha)
        new = new_commits(state.repository_id, in_window)
        GitHistory.record_commits(state.repository_id, object_format(start), in_window)
        state = %{state | recorded: state.recorded + length(new)}

        if page == 1 and start not in shas, do: mark_unfilled(state.repository_id, start, @past_window_ttl)

        connected? = length(new) < length(shas)

        if more == :more and past_window == [] and not connected? and state.budget > 0 do
          walk(start, page + 1, state)
        else
          {:cont, state}
        end

      {:error, reason} ->
        mark_unfilled(state.repository_id, start, @unfilled_ttl)
        {:halt, reason, state}
    end
  end

  # The listed commits the graph does not follow yet: not stored, or stored
  # without the parents the listing names (a shallow clone's boundary). A
  # stored root is already whole.
  defp new_commits(repository_id, commits) do
    missing = MapSet.new(GitHistory.missing_shas(repository_id, Enum.map(commits, & &1.sha)))

    Enum.filter(commits, fn commit ->
      MapSet.member?(missing, commit.sha) and (commit.parents != [] or not GitHistory.known?(repository_id, commit.sha))
    end)
  end

  defp summary(state, gaps_left), do: %{pages: state.pages, recorded: state.recorded, gaps_left: gaps_left}

  defp unfilled?(repository_id, sha), do: KeyValueStore.get(cache_key(repository_id, sha), cache_opts()) == true

  defp mark_unfilled(repository_id, sha, ttl),
    do: KeyValueStore.put(cache_key(repository_id, sha), true, Keyword.put(cache_opts(), :ttl, ttl))

  defp cache_key(repository_id, sha), do: [__MODULE__, "unfilled", repository_id, sha]

  defp cache_opts, do: [persist_across_deployments: true]

  defp object_format(sha) when byte_size(sha) == 64, do: "sha256"
  defp object_format(_sha), do: "sha1"
end
