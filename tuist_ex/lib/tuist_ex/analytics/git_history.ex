defmodule TuistEx.Analytics.GitHistory do
  @moduledoc false

  # A run's Git history, collected from the checkout within the limits the
  # server sets: the fields a coverage run reports (merge base, whether the
  # checkout was dirty), and, once the run exists, the commits the
  # server's graph lacks, the branch head, and the commit's file listing when
  # the checkout is clean. Both halves are best effort: a run is never lost to
  # a history problem, and what could not be collected is reported with the
  # run so the server can complete it from the VCS provider. Mirrors the
  # command line tool's `GitHistoryService`.

  alias TuistEx.Analytics.Env
  alias TuistEx.Analytics.HTTP
  alias TuistEx.Git

  @listing_batch_size 10_000
  @missing_batch_size 5_000

  @default_settings %{
    window_days: 365,
    window_commits: 5000,
    deepen_budget_seconds: 60,
    upload_batch_size: 500,
    commit_file_limit: 50_000
  }

  @doc """
  Collects the history of the checkout at `dir`. Returns the collected state
  for `payload/1` and `upload/2`.
  """
  def collect(dir, options, environment \\ &System.get_env/1) do
    observed_at = DateTime.utc_now()
    head = Env.git_commit_sha(environment)
    base_branch = Env.base_branch(environment)
    pull_request_number = Env.pull_request_number(environment)

    base = %{
      dir: dir,
      branch: Env.git_branch(environment),
      repository_url: Env.git_remote_url_origin(environment),
      base_branch: base_branch,
      pull_request_number: pull_request_number,
      pull_request?: not is_nil(pull_request_number),
      observed_at: observed_at,
      settings: @default_settings,
      dirty?: false,
      history: nil
    }

    cond do
      is_nil(head) ->
        Map.put(base, :fallback_reason, "the run's commit is unknown")

      not Git.repository?(dir) ->
        Map.put(base, :fallback_reason, "the working directory is not a Git repository")

      true ->
        settings = settings(options)
        dirty? = Git.dirty?(dir)

        case Git.history(
               dir,
               head,
               base_branch,
               Map.take(settings, [:window_days, :window_commits, :deepen_budget_seconds])
             ) do
          {:ok, history} ->
            %{base | settings: settings, dirty?: dirty?, history: history}
            |> Map.put(:fallback_reason, history.fallback_reason)

          {:error, reason} ->
            %{base | settings: settings, dirty?: dirty?} |> Map.put(:fallback_reason, reason)
        end
    end
  end

  @doc "The fields the run reports about its history."
  def payload(%{history: nil} = collected) do
    %{
      base_branch: collected.base_branch,
      is_pull_request: collected.pull_request?,
      pull_request_number: collected.pull_request_number,
      history_source: "none",
      history_fallback_reason: collected.fallback_reason,
      git_dirty: collected.dirty?
    }
    |> reject_nil()
  end

  def payload(%{history: history} = collected) do
    %{
      base_branch: history.base_branch,
      merge_base_sha: history.merge_base_sha,
      is_pull_request: collected.pull_request?,
      pull_request_number: collected.pull_request_number,
      git_object_format: history.object_format,
      history_source: "client",
      history_fallback_reason: history.fallback_reason,
      git_dirty: collected.dirty?
    }
    |> reject_nil()
  end

  @doc """
  Sends the commits the server lacks, oldest first so their generation
  numbers are exact, in batches of the server's size, with the branch head
  the run was on, and the commit's file listing when the server lacks it and
  the checkout is clean. A checkout without a remote has no graph to upload
  to. Returns the problems it ran into, which are never raised.
  """
  def upload(%{history: nil}, _options), do: []
  def upload(%{repository_url: url}, _options) when url in [nil, ""], do: []

  def upload(collected, options) do
    [
      upload_step("the run's Git history", fn -> upload_commits(collected, options) end),
      upload_step("the commit's file listing", fn -> upload_listing(collected, options) end)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp upload_step(what, fun) do
    case fun.() do
      :ok -> nil
      {:error, reason} -> "#{what} could not be uploaded: #{inspect(reason)}"
    end
  end

  defp upload_commits(%{history: history} = collected, options) do
    shas = Enum.map(history.commits, & &1.sha)

    with {:ok, missing} <-
           missing(shas, "/tests/git-history/commits/missing", collected.repository_url, options) do
      # `git log` lists children before their parents, so reversed, a stable
      # sort keeps parents first among commits made in the same second.
      to_upload =
        history.commits
        |> Enum.reverse()
        |> Enum.filter(&MapSet.member?(missing, &1.sha))
        |> Enum.sort_by(&DateTime.to_unix(&1.committed_at))
        |> Enum.map(fn commit ->
          %{
            sha: commit.sha,
            parents: commit.parents,
            committed_at: DateTime.to_iso8601(commit.committed_at)
          }
        end)

      branch_heads =
        if collected.branch,
          do: [
            %{
              branch: collected.branch,
              sha: history.head_sha,
              observed_at: DateTime.to_iso8601(collected.observed_at)
            }
          ],
          else: []

      batches =
        case Enum.chunk_every(to_upload, max(collected.settings.upload_batch_size, 1)) do
          [] -> if branch_heads == [], do: [], else: [[]]
          batches -> batches
        end

      last = length(batches) - 1

      batches
      |> Enum.with_index()
      |> Enum.reduce_while(:ok, fn {batch, index}, :ok ->
        body = %{
          repository_url: collected.repository_url,
          object_format: history.object_format,
          commits: batch,
          branch_heads: if(index == last, do: branch_heads, else: [])
        }

        case HTTP.project_request(:post, "/tests/git-history/commits", body, options) do
          {:ok, _} -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    end
  end

  defp upload_listing(%{dirty?: true}, _options), do: :ok

  defp upload_listing(%{history: history} = collected, options) do
    with {:ok, missing} <-
           missing(
             [history.head_sha],
             "/tests/git-history/listings/missing",
             collected.repository_url,
             options
           ),
         true <- MapSet.member?(missing, history.head_sha) || :ok,
         {:ok, listing} <-
           Git.commit_files(collected.dir, history.head_sha, collected.settings.commit_file_limit) do
      files = listing.files

      batches =
        case Enum.chunk_every(files, @listing_batch_size) do
          [] -> [[]]
          batches -> batches
        end

      last = length(batches) - 1

      batches
      |> Enum.with_index()
      |> Enum.reduce_while(:ok, fn {batch, index}, :ok ->
        body = %{
          repository_url: collected.repository_url,
          sha: history.head_sha,
          files: batch,
          complete: index == last,
          truncated: listing.truncated,
          files_count: length(files)
        }

        case HTTP.project_request(:post, "/tests/git-history/listings", body, options) do
          {:ok, _} -> {:cont, :ok}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
    else
      :error -> {:error, :listing_unreadable}
      other -> other
    end
  end

  defp missing(shas, suffix, repository_url, options) do
    shas
    |> Enum.chunk_every(@missing_batch_size)
    |> Enum.reduce_while({:ok, MapSet.new()}, fn batch, {:ok, acc} ->
      case HTTP.project_request(
             :post,
             suffix,
             %{repository_url: repository_url, shas: batch},
             options
           ) do
        {:ok, %{"missing" => missing}} -> {:cont, {:ok, MapSet.union(acc, MapSet.new(missing))}}
        {:ok, other} -> {:halt, {:error, {:unexpected_response, other}}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp settings(options) do
    case HTTP.project_request(:get, "/tests/git-history/settings", nil, options) do
      {:ok, body} when is_map(body) ->
        Map.new(@default_settings, fn {key, default} ->
          case Map.get(body, Atom.to_string(key)) do
            value when is_integer(value) -> {key, value}
            _ -> {key, default}
          end
        end)

      _ ->
        @default_settings
    end
  end

  defp reject_nil(map), do: Map.reject(map, fn {_key, value} -> is_nil(value) end)
end
