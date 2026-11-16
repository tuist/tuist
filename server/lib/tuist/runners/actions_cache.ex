defmodule Tuist.Runners.ActionsCache do
  @moduledoc """
  The GitHub Actions cache Linux runner hosts serve (`actions/cache`, setup
  actions' caches, buildx `type=gha`). Entries live in the actions cache bucket
  of the in-cluster store at the runner's site (a shard storage target with an
  `actions_cache_bucket`), or in the account's own S3 storage when it has one;
  hosts only stage uploads and relay reads. An entry is restorable only once
  its store holds the object.

  This index scopes and orders entries the way GitHub does. A job saves under
  its own ref and restores from its ref, its pull request's base branch and the
  repository's default branch, in that order. Scope comes from GitHub's API for
  the job the runner executes, never from the job.

  Only the trusted storage agent calls this module.
  """
  import Ecto.Query

  alias Tuist.Accounts
  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.KeyValueStore
  alias Tuist.Repo
  alias Tuist.Runners.ActionsCache.Entry
  alias Tuist.Runners.CacheVolumes
  alias Tuist.Runners.CacheVolumes.Identity
  alias Tuist.Runners.Sites
  alias Tuist.Shards.Storage, as: ShardStorage
  alias Tuist.Storage

  @retention_seconds 7 * 24 * 60 * 60
  # An upload that has not finished by then was abandoned.
  @reservation_seconds 60 * 60
  @repository_limit_bytes 200_000_000_000
  @store_fill_percent 90
  # One presigned PUT carries at most 5 GB.
  @max_entry_bytes 5_000_000_000
  @touch_seconds 60 * 60
  @url_ttl_seconds 6 * 60 * 60
  @max_key_bytes 512
  @max_restore_keys 10
  @sweep_limit 1_000

  def lookup(%{"pod_name" => pod, "node_name" => node, "key" => key, "version" => version} = params) do
    restore_keys = Map.get(params, "restore_keys") || []

    with true <- valid_key?(key) and valid_key?(version) and valid_restore_keys?(restore_keys),
         {:ok, scope} <- job_scope(pod, node),
         true <- enabled?(scope.account_id) do
      {:ok, restorable(find(scope, key, restore_keys, version), node)}
    else
      {:error, :pending} -> {:error, :pending}
      _ -> {:error, :unavailable}
    end
  end

  def lookup(_), do: {:error, :unavailable}

  @doc """
  Whether the account of the job running on `pod` uses this cache. Hosts leave
  every other account's jobs on GitHub's cache, and this index refuses them.
  """
  def enabled(%{"pod_name" => pod, "node_name" => node}) do
    case CacheVolumes.running_github_job(pod, node) do
      {:ok, job} -> {:ok, enabled?(job.account_id)}
      error -> error
    end
  end

  def enabled(_), do: {:error, :unavailable}

  defp enabled?(account_id), do: FeatureFlags.runner_actions_cache_enabled?(%Account{id: account_id})

  def reserve(%{"pod_name" => pod, "node_name" => node, "id" => id, "key" => key, "version" => version}) do
    with true <- valid_key?(key) and valid_key?(version),
         {:ok, id} <- Ecto.UUID.cast(id),
         {:ok, scope} <- job_scope(pod, node),
         true <- enabled?(scope.account_id),
         {:ok, account} <- Accounts.get_account_by_id(scope.account_id),
         {:ok, storage_target} <- place(account, node) do
      Repo.transaction(fn ->
        reserve_locked(%{
          storage_target: storage_target,
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
  Where the host `node` uploads the reservation `id` it received in full: a
  presigned PUT, bound to the entry's SHA-256, into the entry's store. Entries
  above one PUT's 5 GB are refused, like an upload the bucket has no room for.
  """
  def upload(%{"node_name" => node, "id" => id, "size_bytes" => size, "sha256" => sha256}) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         true <- is_integer(size) and size >= 0 and size <= @max_entry_bytes,
         true <- is_binary(sha256) and Regex.match?(~r/\A[0-9a-f]{64}\z/, sha256),
         %Entry{} = entry <- reservation(id, node),
         {:ok, actor} <- actor(entry),
         {checksum, opts} = upload_opts(actor, sha256),
         url when is_binary(url) <- Storage.generate_upload_url(object_key(entry), actor, opts),
         true <- trusted_url?(entry, url) do
      Repo.update_all(from(e in Entry, where: e.id == ^id and is_nil(e.committed_at)), set: [size_bytes: size])
      {:ok, %{upload_url: url, checksum: checksum}}
    else
      nil -> {:error, :not_found}
      _ -> {:error, :unavailable}
    end
  end

  def upload(_), do: {:error, :unavailable}

  defp reservation(id, node) do
    Repo.one(from(e in Entry, where: e.id == ^id and e.node_name == ^node and is_nil(e.committed_at)))
  end

  defp upload_opts(actor, sha256) do
    opts = [expires_in: @url_ttl_seconds]

    if Storage.supports_signed_upload_headers?(actor) do
      checksum = sha256 |> Base.decode16!(case: :lower) |> Base.encode64()
      {checksum, opts ++ [signed_headers: [{"x-amz-checksum-sha256", checksum}]]}
    else
      {nil, opts}
    end
  end

  @doc """
  Commits the reservation `id` once its store holds the object, which makes it
  restorable. Committing a committed entry again is a no-op.
  """
  def commit(%{"node_name" => node, "id" => id}) when is_binary(node) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Entry{} = entry <- Repo.one(from(e in Entry, where: e.id == ^id and e.node_name == ^node)) do
      cond do
        entry.committed_at -> :ok
        stored?(entry) -> mark_committed(id)
        true -> {:error, :unavailable}
      end
    else
      nil -> {:error, :not_found}
      _ -> {:error, :unavailable}
    end
  end

  def commit(_), do: {:error, :unavailable}

  defp stored?(%Entry{size_bytes: nil}), do: false

  defp stored?(entry) do
    case actor(entry) do
      {:ok, actor} -> Storage.object_exists?(object_key(entry), actor)
      _ -> false
    end
  end

  defp mark_committed(id) do
    now = DateTime.utc_now()

    Repo.update_all(from(e in Entry, where: e.id == ^id and is_nil(e.committed_at)),
      set: [committed_at: now, last_used_at: now]
    )

    :ok
  end

  @doc """
  Deletes reservations abandoned for an hour, entries unused for seven days,
  per repository the least recently used entries beyond 200 GB, and per store
  the least recently used entries beyond 90% of its bucket quota, so saves
  keep finding room under it. An entry whose object could not be deleted stays
  for the next sweep.
  """
  def sweep(now \\ DateTime.utc_now()) do
    abandoned = DateTime.add(now, -@reservation_seconds, :second)
    expired = DateTime.add(now, -@retention_seconds, :second)

    abandoned =
      Repo.all(from(e in Entry, where: is_nil(e.committed_at) and e.inserted_at < ^abandoned, limit: @sweep_limit))

    stale = Repo.all(from(e in Entry, where: e.last_used_at < ^expired, limit: @sweep_limit))
    {:ok, delete_entries(abandoned ++ stale ++ over_repository_limit() ++ over_store_limits())}
  end

  defp over_repository_limit do
    totals =
      from(e in Entry,
        where: not is_nil(e.committed_at),
        windows: [
          repository: [partition_by: [e.account_id, e.repository_id], order_by: [desc: e.last_used_at, desc: e.id]]
        ],
        select: %{id: e.id, total: over(sum(coalesce(e.size_bytes, 0)), :repository)}
      )

    beyond(totals, @repository_limit_bytes)
  end

  defp over_store_limits do
    for {id, {config, _target}} <- stores(),
        quota <- [config["actions_cache_bytes"]],
        is_integer(quota) and quota > 0,
        entry <- over_store_limit(id, div(quota * @store_fill_percent, 100)),
        do: entry
  end

  defp over_store_limit(id, limit) do
    totals =
      from(e in Entry,
        where: e.storage_target == ^id and not is_nil(e.committed_at),
        windows: [store: [order_by: [desc: e.last_used_at, desc: e.id]]],
        select: %{id: e.id, total: over(sum(coalesce(e.size_bytes, 0)), :store)}
      )

    beyond(totals, limit)
  end

  defp beyond(totals, limit) do
    Repo.all(
      from(e in Entry,
        join: t in subquery(totals),
        on: t.id == e.id,
        where: t.total > ^limit,
        limit: @sweep_limit
      )
    )
  end

  defp delete_entries(entries) do
    entries
    |> Enum.uniq_by(& &1.id)
    |> Enum.group_by(&{&1.account_id, &1.storage_target})
    |> Enum.map(fn {_place, [entry | _] = entries} ->
      if delete_objects(entry, entries) == :ok do
        ids = Enum.map(entries, & &1.id)
        {count, _} = Repo.delete_all(from(e in Entry, where: e.id in ^ids))
        count
      else
        0
      end
    end)
    |> Enum.sum()
  end

  # A store no longer configured cannot be reached, so its rows go without
  # their objects.
  defp delete_objects(entry, entries) do
    case actor(entry) do
      {:ok, actor} -> Storage.delete_objects(Enum.map(entries, &object_key/1), actor)
      {:error, :gone} -> :ok
      _ -> :error
    end
  rescue
    _ -> :error
  end

  @doc """
  The object-storage prefix holding an account's Actions cache entries, keyed by
  account ID like the volume masters.
  """
  def object_prefix(account_id), do: "runner-actions-cache/#{account_id}/"

  @doc "Deletes an account's entries from its own storage and every store."
  def purge_account(%Account{} = account) do
    prefix = object_prefix(account.id)
    Storage.delete_all_objects(prefix, account)
    for {_id, {_config, target}} <- stores(), do: Storage.delete_all_objects(prefix, target)
    :ok
  end

  defp object_key(entry), do: object_prefix(entry.account_id) <> "#{entry.repository_id}/#{entry.id}"

  # Shard storage targets that hold Actions cache entries, in their
  # `actions_cache_bucket`.
  defp stores do
    for {id, %{"actions_cache_bucket" => bucket} = config} <- Environment.shard_storage_targets(),
        is_binary(bucket) and bucket != "",
        {:ok, target} <- [ShardStorage.s3_target(id, Map.put(config, "bucket", bucket))],
        into: %{},
        do: {id, {config, target}}
  end

  # Where a save from `node` goes: an account with its own S3 storage keeps its
  # entries there, every other account in the store at the node's site.
  defp place(account, node) do
    if Account.custom_s3_storage_configured?(account) do
      {:ok, nil}
    else
      site = node_site(node)

      Enum.find_value(Enum.sort(stores()), :error, fn {id, {config, _target}} ->
        if is_binary(site) and config["site"] == site and config["private_network_ready"] == true, do: {:ok, id}
      end)
    end
  end

  # Store URLs are plain HTTP inside the cluster, so only a host on the store's
  # private network at its site may read one.
  defp readable?(%Entry{storage_target: nil}, _node), do: true

  defp readable?(%Entry{storage_target: id}, node) do
    case stores() do
      %{^id => {config, _target}} -> config["site"] == node_site(node)
      _ -> false
    end
  end

  defp node_site(node) do
    KeyValueStore.get_or_update([__MODULE__, :site, node], [ttl: to_timeout(minute: 5)], fn ->
      Sites.shard_storage_site(node)
    end)
  end

  defp actor(%Entry{storage_target: nil, account_id: account_id}), do: Accounts.get_account_by_id(account_id)

  defp actor(%Entry{storage_target: id}) do
    case stores() do
      %{^id => {_config, target}} -> {:ok, target}
      _ -> {:error, :gone}
    end
  end

  # An account's own storage may name any endpoint, and the host agent must not
  # be pointed at internal addresses; a store is the cluster's own.
  defp trusted_url?(%Entry{storage_target: nil}, url), do: Tuist.URL.public_host_url?(url)
  defp trusted_url?(_entry, _url), do: true

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

  defp restorable(nil, _node), do: nil

  defp restorable(entry, node) do
    with true <- readable?(entry, node),
         {:ok, actor} <- actor(entry),
         url when is_binary(url) <-
           Storage.generate_download_url(object_key(entry), actor, expires_in: @url_ttl_seconds),
         true <- trusted_url?(entry, url) do
      touch(entry)
      %{id: entry.id, key: entry.key, size_bytes: entry.size_bytes, download_url: url}
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
