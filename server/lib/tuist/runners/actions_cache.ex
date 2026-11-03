defmodule Tuist.Runners.ActionsCache do
  @moduledoc """
  The GitHub Actions cache Linux runner hosts serve (`actions/cache`, setup
  actions' caches, buildx `type=gha`). Hosts keep the bytes; this index scopes
  and orders entries the way GitHub does. A job saves under its own ref and
  restores from its ref, its pull request's base branch and the repository's
  default branch, in that order. Scope comes from GitHub's API for the job the
  runner executes, never from the job.

  Only the trusted storage agent calls this module.
  """
  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.KeyValueStore
  alias Tuist.Repo
  alias Tuist.Runners.ActionsCache.Entry
  alias Tuist.Runners.CacheVolumes
  alias Tuist.Runners.CacheVolumes.Identity
  alias Tuist.Storage

  @retention_seconds 7 * 24 * 60 * 60
  # An upload that has not finished by then was abandoned.
  @reservation_seconds 60 * 60
  @repository_limit_bytes 50_000_000_000
  # Larger entries stay on the host that received them: one presigned PUT
  # carries at most 5 GB.
  @max_stored_bytes 5_000_000_000
  @touch_seconds 60 * 60
  @url_ttl_seconds 6 * 60 * 60
  @max_key_bytes 512
  @max_restore_keys 10
  @sweep_limit 1_000

  def lookup(%{"pod_name" => pod, "node_name" => node, "key" => key, "version" => version} = params) do
    restore_keys = Map.get(params, "restore_keys") || []

    with true <- valid_key?(key) and valid_key?(version) and valid_restore_keys?(restore_keys),
         {:ok, scope} <- job_scope(pod, node) do
      case find(scope, key, restore_keys, version) do
        nil -> {:ok, nil}
        entry -> {:ok, describe(touch(entry))}
      end
    else
      {:error, :pending} -> {:error, :pending}
      _ -> {:error, :unavailable}
    end
  end

  def lookup(_), do: {:error, :unavailable}

  def reserve(%{"pod_name" => pod, "node_name" => node, "id" => id, "key" => key, "version" => version}) do
    with true <- valid_key?(key) and valid_key?(version),
         {:ok, id} <- Ecto.UUID.cast(id),
         {:ok, scope} <- job_scope(pod, node) do
      Repo.transaction(fn ->
        reserve_locked(%{
          id: id,
          account_id: scope.account_id,
          repository_id: scope.repository_id,
          scope: scope.write,
          key: key,
          version: version,
          node_name: node
        })
      end)
    else
      {:error, :pending} -> {:error, :pending}
      _ -> {:error, :unavailable}
    end
  end

  def reserve(_), do: {:error, :unavailable}

  # A reservation that never finished uploading gives way after an hour, like a
  # failed save on GitHub. Saving an existing key and version is refused.
  defp reserve_locked(%{id: id} = attrs) do
    existing =
      Repo.one(
        from(e in Entry,
          where:
            e.account_id == ^attrs.account_id and e.repository_id == ^attrs.repository_id and e.scope == ^attrs.scope and
              e.version == ^attrs.version and e.key == ^attrs.key,
          lock: "FOR UPDATE"
        )
      )

    case existing do
      nil -> insert_reservation(attrs)
      %Entry{id: ^id} -> id
      %Entry{committed_at: nil} = abandoned -> replace_abandoned(abandoned, attrs)
      _committed -> Repo.rollback(:conflict)
    end
  end

  defp replace_abandoned(reservation, attrs) do
    if DateTime.diff(DateTime.utc_now(), reservation.inserted_at) > @reservation_seconds do
      Repo.delete!(reservation)
      insert_reservation(attrs)
    else
      Repo.rollback(:conflict)
    end
  end

  defp insert_reservation(%{id: id} = attrs) do
    %Entry{id: id}
    |> Ecto.Changeset.change(attrs |> Map.delete(:id) |> Map.put(:last_used_at, DateTime.utc_now()))
    |> Ecto.Changeset.unique_constraint([:account_id, :repository_id, :scope, :version, :key],
      name: :runner_actions_cache_entries_unique_index
    )
    |> Ecto.Changeset.unique_constraint(:id, name: :runner_actions_cache_entries_pkey)
    |> Repo.insert()
    |> case do
      {:ok, _entry} -> id
      {:error, _changeset} -> Repo.rollback(:conflict)
    end
  end

  @doc """
  Commits the reservation `id` the host `node` received the whole entry for.
  Returns a presigned PUT for the account's storage when the entry is small
  enough to copy there, so hosts that never received it can serve it.
  """
  def commit(%{"node_name" => node, "id" => id, "size_bytes" => size, "sha256" => sha256}) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         true <- is_integer(size) and size >= 0 and is_binary(sha256) and Regex.match?(~r/\A[0-9a-f]{64}\z/, sha256),
         {:ok, entry} <- Repo.transaction(fn -> commit_locked(node, id, size) end) do
      {:ok, storage_upload(entry, sha256)}
    else
      {:error, reason} when reason in [:not_found, :conflict] -> {:error, reason}
      _ -> {:error, :unavailable}
    end
  end

  def commit(_), do: {:error, :unavailable}

  defp commit_locked(node, id, size) do
    case Repo.one(from(e in Entry, where: e.id == ^id and e.node_name == ^node, lock: "FOR UPDATE")) do
      nil ->
        Repo.rollback(:not_found)

      %Entry{committed_at: nil} = entry ->
        now = DateTime.utc_now()
        entry |> Ecto.Changeset.change(committed_at: now, size_bytes: size, last_used_at: now) |> Repo.update!()

      %Entry{size_bytes: ^size} = entry ->
        entry

      _ ->
        Repo.rollback(:conflict)
    end
  end

  defp storage_upload(%Entry{stored_at: nil, size_bytes: size} = entry, sha256) when size <= @max_stored_bytes do
    with {:ok, account} <- Accounts.get_account_by_id(entry.account_id),
         {checksum, opts} = upload_opts(account, sha256),
         url when is_binary(url) <- Storage.generate_upload_url(object_key(entry), account, opts),
         true <- Tuist.URL.public_host_url?(url) do
      %{upload_url: url, checksum: checksum}
    else
      _ -> %{upload_url: nil, checksum: nil}
    end
  end

  defp storage_upload(_entry, _sha256), do: %{upload_url: nil, checksum: nil}

  defp upload_opts(account, sha256) do
    opts = [expires_in: @url_ttl_seconds]

    if Storage.supports_signed_upload_headers?(account) do
      checksum = sha256 |> Base.decode16!(case: :lower) |> Base.encode64()
      {checksum, opts ++ [signed_headers: [{"x-amz-checksum-sha256", checksum}]]}
    else
      {nil, opts}
    end
  end

  @doc "Records that the committed entry `id` is in the account's storage."
  def stored(%{"node_name" => node, "id" => id}) when is_binary(node) do
    with {:ok, id} <- Ecto.UUID.cast(id) do
      Repo.update_all(
        from(e in Entry,
          where: e.id == ^id and e.node_name == ^node and not is_nil(e.committed_at) and is_nil(e.stored_at)
        ),
        set: [stored_at: DateTime.utc_now()]
      )

      :ok
    end
  end

  def stored(_), do: :error

  @doc """
  Deletes abandoned reservations, entries unused for seven days and, per
  repository, the least recently used entries beyond 50 GB. An entry whose
  object could not be deleted stays for the next sweep.
  """
  def sweep(now \\ DateTime.utc_now()) do
    abandoned = DateTime.add(now, -@reservation_seconds, :second)
    expired = DateTime.add(now, -@retention_seconds, :second)

    {abandoned_count, _} =
      Repo.delete_all(from(e in Entry, where: is_nil(e.committed_at) and e.inserted_at < ^abandoned))

    stale = Repo.all(from(e in Entry, where: e.last_used_at < ^expired, limit: @sweep_limit))
    {:ok, abandoned_count + delete_entries(stale ++ over_limit())}
  end

  defp over_limit do
    totals =
      from(e in Entry,
        where: not is_nil(e.committed_at),
        windows: [
          repository: [partition_by: [e.account_id, e.repository_id], order_by: [desc: e.last_used_at, desc: e.id]]
        ],
        select: %{id: e.id, total: over(sum(coalesce(e.size_bytes, 0)), :repository)}
      )

    Repo.all(
      from(e in Entry,
        join: t in subquery(totals),
        on: t.id == e.id,
        where: t.total > ^@repository_limit_bytes,
        limit: @sweep_limit
      )
    )
  end

  defp delete_entries(entries) do
    entries
    |> Enum.uniq_by(& &1.id)
    |> Enum.group_by(& &1.account_id)
    |> Enum.map(fn {account_id, entries} ->
      {stored, local} = Enum.split_with(entries, &(&1.stored_at != nil))

      deletable =
        case stored do
          [] -> local
          stored -> if delete_objects(account_id, stored) == :ok, do: entries, else: local
        end

      ids = Enum.map(deletable, & &1.id)
      {count, _} = Repo.delete_all(from(e in Entry, where: e.id in ^ids))
      count
    end)
    |> Enum.sum()
  end

  defp delete_objects(account_id, entries) do
    case Accounts.get_account_by_id(account_id) do
      {:ok, account} -> Storage.delete_objects(Enum.map(entries, &object_key/1), account)
      _ -> :error
    end
  rescue
    _ -> :error
  end

  @doc """
  The object-storage prefix holding an account's Actions cache entries, keyed by
  account ID like the volume masters, so account deletion removes it.
  """
  def object_prefix(account_id), do: "runner-actions-cache/#{account_id}/"

  defp object_key(entry), do: object_prefix(entry.account_id) <> "#{entry.repository_id}/#{entry.id}"

  defp find(scope, key, restore_keys, version) do
    Enum.find_value(scope.read, fn ref ->
      exact(scope, ref, version, key) || prefixed(scope, ref, version, key) ||
        Enum.find_value(restore_keys, &prefixed(scope, ref, version, &1))
    end)
  end

  defp committed(scope, ref, version) do
    from(e in Entry,
      where:
        e.account_id == ^scope.account_id and e.repository_id == ^scope.repository_id and e.scope == ^ref and
          e.version == ^version and not is_nil(e.committed_at)
    )
  end

  defp exact(scope, ref, version, key), do: Repo.one(from(e in committed(scope, ref, version), where: e.key == ^key))

  defp prefixed(scope, ref, version, prefix) do
    pattern = String.replace(prefix, ~r/[\\%_]/, "\\\\\\0") <> "%"

    Repo.one(
      from(e in committed(scope, ref, version),
        where: like(e.key, ^pattern),
        order_by: [desc: e.committed_at],
        limit: 1
      )
    )
  end

  defp touch(entry) do
    now = DateTime.utc_now()

    if DateTime.diff(now, entry.last_used_at) > @touch_seconds do
      Repo.update_all(from(e in Entry, where: e.id == ^entry.id), set: [last_used_at: now])
    end

    entry
  end

  defp describe(entry) do
    %{id: entry.id, key: entry.key, size_bytes: entry.size_bytes, download_url: storage_download(entry)}
  end

  defp storage_download(%Entry{stored_at: nil}), do: nil

  defp storage_download(entry) do
    with {:ok, account} <- Accounts.get_account_by_id(entry.account_id),
         url when is_binary(url) <-
           Storage.generate_download_url(object_key(entry), account, expires_in: @url_ttl_seconds),
         true <- Tuist.URL.public_host_url?(url) do
      url
    else
      _ -> nil
    end
  end

  defp job_scope(pod, node) do
    with {:ok, job} <- CacheVolumes.running_github_job(pod, node) do
      KeyValueStore.get_or_update(
        [__MODULE__, :scope, job.account_id, job.workflow_run_id, job.run_attempt],
        [ttl: to_timeout(hour: 1), cache_errors: false],
        fn -> resolve_scope(job) end
      )
    end
  end

  defp resolve_scope(job) do
    with {:ok, run} <- Identity.github_run(job), do: github_scope(job, run)
  end

  @doc """
  The refs a job saves under and restores from, from its verified workflow run.
  A pull request from the repository itself saves under `refs/pull/<n>/merge`;
  other runs of the repository under their branch. A run from a fork, which
  GitHub lists without its pull request, saves under the fork's branch only.
  """
  def github_scope(job, run) do
    with %{"id" => id, "full_name" => repository, "default_branch" => default} <- run["repository"],
         true <- is_integer(id) and id > 0 and is_binary(default) and default != "",
         true <- repository == job.repository and run["id"] == job.workflow_run_id,
         true <- run["run_attempt"] == job.run_attempt,
         branch when is_binary(branch) and branch != "" <- run["head_branch"],
         {:ok, write, base} <- refs(run, id, branch) do
      {:ok,
       %{
         account_id: job.account_id,
         repository_id: id,
         write: write,
         read: Enum.uniq([write | base] ++ ["refs/heads/" <> default])
       }}
    else
      _ -> {:error, :unavailable}
    end
  end

  defp refs(run, id, branch) do
    head_repository = get_in(run, ["head_repository", "id"])

    case {run["event"], run["pull_requests"]} do
      {"pull_request", [%{"number" => number, "head" => %{"repo" => %{"id" => ^id}}, "base" => %{"ref" => base}} | _]}
      when is_integer(number) and is_binary(base) ->
        {:ok, "refs/pull/#{number}/merge", ["refs/heads/" <> base]}

      _ when head_repository == id ->
        {:ok, "refs/heads/" <> branch, []}

      _ when is_integer(head_repository) ->
        {:ok, "fork/#{head_repository}/" <> branch, []}

      _ ->
        :error
    end
  end

  defp valid_key?(key), do: is_binary(key) and key != "" and byte_size(key) <= @max_key_bytes and String.valid?(key)

  defp valid_restore_keys?(keys),
    do: is_list(keys) and length(keys) <= @max_restore_keys and Enum.all?(keys, &valid_key?/1)
end
