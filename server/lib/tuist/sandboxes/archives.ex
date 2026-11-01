defmodule Tuist.Sandboxes.Archives do
  @moduledoc """
  The archive tier of paused Amp Orbs.

  A paused Orb holds its memory image and disks on one node, reserving its
  full disk ceiling there. Once it has been paused for longer than
  `Tuist.Environment.sandbox_archive_after_hours/0`, or its account keeps
  more than `max_paused_on_node_per_account/0` paused Orbs on nodes (the
  least recently paused go first), its node uploads the
  kernel, rootfs and workspace (not the memory image) to the account's
  object storage through presigned multipart URLs, the row becomes
  `archived` with no node, and the jail is deleted. The next spawn restores
  it on any node with room (`Tuist.Sandboxes` creates it `from_archive`)
  and it cold boots: files survive, processes do not.

  The archive object is the only copy of an archived Orb, so nothing here
  deletes it until a restore is running on a node, the sandbox is deleted,
  or its account is. The upload runs without the sandbox's lock: the lock
  is taken to start it and again to finish it, and a resume meanwhile wins
  (the node cancels the upload, and a finish that finds the row changed
  since the upload started aborts it).
  """
  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Sandboxes.Workers.ArchiveSandboxesWorker
  alias Tuist.Storage

  require Logger

  @mib 1024 * 1024
  @gib 1024 * @mib
  @max_archived_bytes_per_account 100 * @gib
  @max_paused_on_node_per_account 10
  # The archived kernel, and room for the archive's framing and an
  # incompressible worst case on top of the disk ceiling.
  @kernel_allowance_bytes 512 * @mib
  @min_part_size 32 * @mib
  @max_parts 2000
  @per_run 10
  @retry_after_hours 6
  # Above the node's 30-minute archive timeout: an upload this old belongs
  # to a caller that died.
  @abandoned_after_minutes 45
  # A restore not settled by then belongs to a caller that died.
  @stuck_restore_minutes 15
  @archive_timeout to_timeout(minute: 31)
  @url_ttl_seconds 3600
  @readable_attempts 20
  @readable_interval_ms 3_000

  def max_archived_bytes_per_account, do: @max_archived_bytes_per_account
  def max_paused_on_node_per_account, do: @max_paused_on_node_per_account

  def object_prefix(account_id), do: "sandbox-archives/#{account_id}/"

  @doc """
  The bytes an account keeps in sandbox archives, counting archives of
  restored Orbs whose deletion is still pending.
  """
  def archived_bytes(account_id) do
    Repo.one(
      from s in Sandbox,
        where: s.account_id == ^account_id and not is_nil(s.archived_at),
        select: type(coalesce(sum(s.archive_bytes), 0), :integer)
    )
  end

  @doc """
  One pass of the archive tier: deletes the archives of restored Orbs,
  aborts uploads and restores whose caller died, then archives Orbs paused
  for longer than the configured threshold and the least recently paused
  Orbs of accounts over the on-node cap. Archiving is off while no
  threshold is configured; the cleanups always run.
  """
  def run do
    delete_restored_archives()
    abandon_stuck_uploads()
    revert_stuck_restores()

    case Environment.sandbox_archive_after_hours() do
      nil -> :ok
      hours -> hours |> candidates() |> Enum.each(&archive/1)
    end
  end

  @doc """
  Queues an archive run when the account keeps more paused Orbs on nodes
  than the cap, so the oldest leave without waiting for the hourly run.
  """
  def enqueue_if_over_cap(account_id) do
    paused = Repo.aggregate(where(idle_paused_orbs(), [s], s.account_id == ^account_id), :count)

    if Environment.sandbox_archive_after_hours() && paused > @max_paused_on_node_per_account do
      {:ok, _job} = %{} |> ArchiveSandboxesWorker.new() |> Oban.insert()
    end

    :ok
  end

  defp idle_paused_orbs do
    from(s in Sandbox,
      where:
        s.state == :paused and not is_nil(s.amp_orb_id) and not is_nil(s.node_name) and is_nil(s.residency_work_id) and
          not is_nil(s.paused_at)
    )
  end

  defp candidates(hours) do
    now = now()
    paused_before = DateTime.add(now, -hours, :hour)
    retry_before = DateTime.add(now, -@retry_after_hours, :hour)

    newest_first =
      from s in idle_paused_orbs(),
        select: %{
          id: s.id,
          rank: over(row_number(), partition_by: s.account_id, order_by: [desc: s.paused_at, desc: s.id])
        }

    idle_paused_orbs()
    |> join(:inner, [s], r in subquery(newest_first), on: r.id == s.id)
    |> where([s, r], s.paused_at < ^paused_before or r.rank > ^@max_paused_on_node_per_account)
    |> where([s], is_nil(s.archived_at) and is_nil(s.archive_upload_id))
    |> where([s], is_nil(s.archive_attempted_at) or s.archive_attempted_at < ^retry_before)
    |> order_by([s], asc: s.paused_at)
    |> limit(@per_run)
    |> Repo.all()
    |> Enum.filter(&(archived_bytes(&1.account_id) < @max_archived_bytes_per_account))
  end

  @doc """
  Archives a paused Orb and removes it from its node. Answers
  `{:ok, %Sandbox{state: :archived}}`, `{:ok, :skipped}` when the sandbox
  is not archivable right now (busy, resumed, not idle, storage or node
  unsuited), or `{:error, reason}` when the upload failed; it stays paused
  on its node either way.
  """
  def archive(%Sandbox{id: id}) do
    case Sandboxes.with_sandbox_lock(id, fn -> start(id) end, wait: false) do
      {:ok, %{} = upload} -> upload |> transfer() |> finish(upload)
      {:error, :locked} -> {:ok, :skipped}
      other -> other
    end
  end

  defp start(id) do
    with %Sandbox{
           state: :paused,
           node_name: node_name,
           paused_at: %DateTime{},
           archived_at: nil,
           archive_upload_id: nil
         } = sandbox
         when is_binary(node_name) <- Sandboxes.get_sandbox_by_id(id),
         %Account{} = account <- Repo.get(Account, sandbox.account_id),
         true <- Storage.supports_signed_upload_headers?(account),
         {:ok, node} <- connected_node(node_name) do
      key = object_prefix(account.id) <> "#{sandbox.id}/#{Ecto.UUID.generate()}.sbxa"
      {part_size, parts} = parts(sandbox, node)

      case Storage.multipart_start(key, account) do
        {:ok, upload_id} ->
          urls =
            for part <- 1..parts,
                do: Storage.multipart_generate_url(key, upload_id, part, account, expires_in: @url_ttl_seconds)

          {:ok, _} =
            sandbox
            |> Sandbox.update_changeset(%{archive_key: key, archive_upload_id: upload_id, archive_attempted_at: now()})
            |> Repo.update()

          {:ok,
           %{
             sandbox: sandbox,
             account: account,
             key: key,
             upload_id: upload_id,
             part_size: part_size,
             urls: urls
           }}

        {:error, reason} ->
          mark_attempted(sandbox)
          {:error, reason}
      end
    else
      _ -> {:ok, :skipped}
    end
  end

  # The archive is at most the files' sizes plus a small framing and
  # compression overhead; parts grow past the minimum so no archive needs
  # more than @max_parts presigned URLs.
  defp parts(sandbox, node) do
    max_bytes =
      Capacity.disk_snapshot_ceiling_bytes(sandbox, node) + @kernel_allowance_bytes

    max_bytes = max_bytes + div(max_bytes, 100)
    part_size = max(@min_part_size, div(max_bytes + @max_parts - 1, @max_parts))
    part_size = div(part_size + @mib - 1, @mib) * @mib
    {part_size, div(max_bytes + part_size - 1, part_size)}
  end

  defp transfer(%{sandbox: sandbox} = upload) do
    Nodes.call(
      sandbox.node_name,
      "archive",
      %{sandbox_id: sandbox.id, part_size: upload.part_size, part_urls: upload.urls},
      timeout: @archive_timeout
    )
  end

  defp finish({:ok, %{"parts" => [_ | _] = parts, "bytes" => bytes, "sha256" => sha256} = data}, upload)
       when is_integer(bytes) and is_binary(sha256) do
    %{sandbox: sandbox, account: account, key: key, upload_id: upload_id} = upload
    parts = for %{"part_number" => number, "etag" => etag} <- parts, do: {number, etag}

    Sandboxes.with_sandbox_lock(sandbox.id, fn ->
      fresh = Sandboxes.get_sandbox_by_id(sandbox.id)

      if unchanged?(fresh, sandbox, upload_id) do
        case complete(key, upload_id, parts, account) do
          :ok ->
            {:ok, archived} =
              fresh
              |> Sandbox.update_changeset(%{
                state: :archived,
                node_name: nil,
                residency_work_id: nil,
                archive_upload_id: nil,
                archive_bytes: bytes,
                archive_sha256: sha256,
                archived_at: now()
              })
              |> Repo.update()

            Logger.info("sandboxes: sandbox archived",
              sandbox_id: sandbox.id,
              node: sandbox.node_name,
              archive_bytes: bytes,
              stored_bytes: data["stored_bytes"],
              disks_synced: data["disks_synced"],
              duration_ms: data["duration_ms"]
            )

            delete_from_node(sandbox)
            {:ok, archived}

          {:error, reason} ->
            discard(upload)
            {:error, reason}
        end
      else
        discard(upload)
        {:ok, :skipped}
      end
    end)
  end

  defp finish({:ok, _data}, upload) do
    discard(upload)
    {:error, :invalid_archive_result}
  end

  defp finish({:error, reason}, %{sandbox: sandbox} = upload) do
    Logger.warning("sandboxes: archiving a sandbox failed",
      sandbox_id: sandbox.id,
      node: sandbox.node_name,
      reason: inspect(reason)
    )

    discard(upload)
    {:error, reason}
  end

  # A resume, pause or delete since the upload started means the archive no
  # longer holds the sandbox's latest disks.
  defp unchanged?(%Sandbox{} = fresh, sandbox, upload_id) do
    fresh.state == :paused and fresh.node_name == sandbox.node_name and fresh.paused_at == sandbox.paused_at and
      fresh.archive_upload_id == upload_id
  end

  defp unchanged?(nil, _sandbox, _upload_id), do: false

  # Tigris answers a completion before the object is readable, so the
  # archive only counts once a HEAD finds it.
  defp complete(key, upload_id, parts, account) do
    with result when result in [:ok, {:error, :multipart_upload_not_found}] <-
           Storage.multipart_complete_upload(key, upload_id, parts, account),
         true <- readable?(key, account, @readable_attempts) do
      :ok
    else
      false -> {:error, :archive_not_readable}
      {:error, reason} -> {:error, reason}
    end
  end

  defp readable?(key, account, attempts) do
    cond do
      Storage.object_exists?(key, account) ->
        true

      attempts <= 1 ->
        false

      true ->
        Process.sleep(@readable_interval_ms)
        readable?(key, account, attempts - 1)
    end
  end

  defp discard(%{account: account, key: key, upload_id: upload_id}) do
    case Storage.multipart_abort(key, upload_id, account) do
      :ok -> :ok
      other -> Logger.warning("sandboxes: could not abort an archive upload", archive_key: key, reason: inspect(other))
    end

    Repo.update_all(from(s in Sandbox, where: s.archive_upload_id == ^upload_id and is_nil(s.archived_at)),
      set: [archive_key: nil, archive_upload_id: nil, updated_at: now()]
    )

    :ok
  end

  defp mark_attempted(%Sandbox{id: id}) do
    Repo.update_all(from(s in Sandbox, where: s.id == ^id), set: [archive_attempted_at: now()])
  end

  # The row is archived already, so a node that is away removes the jail
  # when its next report lists a sandbox the server keeps archived.
  defp delete_from_node(%Sandbox{node_name: node_name, id: id}) do
    case Nodes.call(node_name, "delete", %{sandbox_id: id}, []) do
      {:ok, _data} ->
        :ok

      {:error, reason} ->
        Logger.warning("sandboxes: could not delete an archived sandbox from its node",
          sandbox_id: id,
          node: node_name,
          reason: inspect(reason)
        )
    end
  end

  @doc """
  What a node needs to restore the archive: a presigned GET URL and the
  size and checksum it was uploaded with.
  """
  def restore_source(%Sandbox{state: :archived, archive_key: key, archive_bytes: bytes, archive_sha256: sha256} = sandbox)
      when is_binary(key) and is_integer(bytes) and is_binary(sha256) do
    case Repo.get(Account, sandbox.account_id) do
      %Account{} = account ->
        url = Storage.generate_download_url(key, account, expires_in: @url_ttl_seconds)
        {:ok, %{url: url, bytes: bytes, sha256: sha256}}

      nil ->
        {:error, :not_found}
    end
  end

  def restore_source(%Sandbox{}), do: {:error, :archive_missing}

  @doc """
  Deletes the archive object of a sandbox. Answers `:ok` when there is
  none.
  """
  def delete_object(%Sandbox{archive_key: nil}), do: :ok

  def delete_object(%Sandbox{archive_key: key, account_id: account_id}) do
    case Repo.get(Account, account_id) do
      nil -> :ok
      account -> Storage.delete_object(key, account)
    end
  end

  @doc """
  Deletes the archive of a sandbox that is back on a node. A failure is
  retried by the next `run/0`; the object never outlives the sandbox's
  deletion, which deletes it too.
  """
  def delete_restored(%Sandbox{state: state, archived_at: %DateTime{}} = sandbox)
      when state in [:running, :paused, :resuming] do
    case delete_object(sandbox) do
      :ok ->
        Repo.update_all(
          from(s in Sandbox,
            where: s.id == ^sandbox.id and s.archive_key == ^sandbox.archive_key and s.state != :archived
          ),
          set: [archive_key: nil, archive_bytes: nil, archive_sha256: nil, archived_at: nil]
        )

        :ok

      {:error, reason} ->
        Logger.warning("sandboxes: could not delete a restored sandbox's archive",
          sandbox_id: sandbox.id,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  def delete_restored(%Sandbox{}), do: :ok

  defp delete_restored_archives do
    from(s in Sandbox, where: s.state in [:running, :paused, :resuming] and not is_nil(s.archived_at))
    |> Repo.all()
    |> Enum.each(&delete_restored/1)
  end

  defp abandon_stuck_uploads do
    before = DateTime.add(now(), -@abandoned_after_minutes, :minute)

    from(s in Sandbox, where: not is_nil(s.archive_upload_id) and s.archive_attempted_at < ^before)
    |> Repo.all()
    |> Enum.each(fn sandbox ->
      Logger.warning("sandboxes: aborting an abandoned archive upload", sandbox_id: sandbox.id)

      case Repo.get(Account, sandbox.account_id) do
        nil -> :ok
        account -> discard(%{account: account, key: sandbox.archive_key, upload_id: sandbox.archive_upload_id})
      end
    end)
  end

  @doc """
  Puts a restore whose caller died back to `archived`, so the next spawn
  restores it again. Guarded by the state, so a restore that finished
  meanwhile is left alone.
  """
  def revert_restore(id) do
    Repo.update_all(
      from(s in Sandbox, where: s.id == ^id and s.state == :creating and not is_nil(s.archived_at)),
      set: [state: :archived, node_name: nil, error_message: "restore interrupted", updated_at: now()],
      inc: [residency_epoch: 1]
    )

    :ok
  end

  defp revert_stuck_restores do
    before = DateTime.add(now(), -@stuck_restore_minutes, :minute)

    from(s in Sandbox,
      where: s.state == :creating and not is_nil(s.archived_at) and s.updated_at < ^before,
      select: s.id
    )
    |> Repo.all()
    |> Enum.each(fn id ->
      Logger.warning("sandboxes: reverting a stuck restore", sandbox_id: id)
      revert_restore(id)
    end)
  end

  defp connected_node(node_name) do
    case Enum.find(Nodes.connected_nodes(), &(&1.name == node_name)) do
      nil -> {:error, :not_connected}
      node -> {:ok, node}
    end
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)
end
