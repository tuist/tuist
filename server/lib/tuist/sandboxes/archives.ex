defmodule Tuist.Sandboxes.Archives do
  @moduledoc """
  The archive tier of paused Amp Orbs.

  A paused Orb holds its memory image and disks on one node, reserving its
  full disk ceiling there. Once it has been paused for longer than
  `Tuist.Environment.sandbox_archive_after_hours/0`, or its node's reserved
  disk exceeds `Tuist.Environment.sandbox_archive_disk_high_water_percent/0`,
  or its account's
  disk quota refuses a create or restore (`make_room/1`), or no node has
  disk left for a new sandbox (`make_node_room/1`), least recently paused
  first, its node uploads the
  kernel, rootfs and workspace (not the memory image) through presigned
  multipart URLs to the in-rack store at its node's site, or to the
  account's object storage when there is none available or the store's
  sandbox archive budget is exhausted or its physical free space cannot
  safely fit the upload, and the row becomes
  `archived` with no node, and the jail is deleted. The next spawn restores
  it on any node with room (`Tuist.Sandboxes` creates it `from_archive`)
  and it cold boots: files survive, processes do not.

  Any paused sandbox can also be archived on request (`request/1`, the
  dashboard's Archive button), whatever its source or pause age.

  The archive object is the only copy of an archived Orb, so nothing here
  deletes it without a verified replacement, a restore running on a node,
  or deletion of the sandbox or account. The upload runs without the sandbox's
  lock: the lock is taken to start it and again to finish it, and a resume meanwhile wins
  (the node cancels the upload, and a finish that finds the row changed
  since the upload started aborts it).

  An in-rack store is a shard storage target
  (`Tuist.Environment.shard_storage_targets/0`) with an `archive_bucket`.
  The row records which one holds its archive (`archive_store`), so a
  restore and a delete read it from there even after the target stops
  taking new archives, and a restore is placed on a node at its site.
  Accounts with their own S3 storage keep their archives there.

  Ready disk snapshots (`Tuist.Sandboxes.DiskSnapshot`) are archived the
  same way while the tier is on (`archive_disk_snapshot/1`, queued after
  each save and retried by `run/0`), with `archive_disks`, under
  `sandbox-archives/<account_id>/disk-snapshots/<snapshot_id>/`, so any
  node can create a sandbox from them (`create` with `from_archive`). The
  node copy stays: it is the fast path on its node. A snapshot archive is
  not the only copy of anything, so it is deleted with its snapshot row.
  Both kinds count toward each in-rack store's `archive_budget_bytes`, shared
  by all accounts, including restored archives awaiting deletion. The budget
  defaults to 100 GiB; production configures 500 GiB and canary 100 GiB to
  leave room for shard artifacts on their respective stores. Once reached,
  new uploads use account storage (Tigris by default, `archive_store: nil`).
  There is no per-account archive limit. Account-storage bytes and archives
  in other stores do not consume a store's budget. Uploads can cross the
  budget; it is a routing threshold, not a reservation. Before each upload,
  every URL in the target's `archive_capacity_urls` must report Garage data
  and metadata free bytes sufficient for the archive's worst-case size plus
  1 GiB of headroom. Missing configuration, failed probes or missing readings
  route new archives to account storage too. Garage's filesystem readings
  include other objects and delayed reclamation, but concurrent writers can
  still consume space after admission.

  Upload pressure and the periodic pass queue `offload_oldest/2`: completed
  Orb and snapshot archives move to account storage oldest `archived_at`
  first, across accounts, until enough bytes have been selected to relieve
  budget or measured-space pressure. Each pass copies at most ten objects,
  streaming to a fresh key under the same prefix and rereading the destination
  to verify its size and SHA-256 before atomically changing `archive_key` and
  `archive_store`. Failed or interrupted copies never replace the source.
  Durable cleanup jobs are scheduled before copying and with publication;
  unreferenced copies are deleted after two hours, longer than existing
  signed restore URLs and restore timeouts. Retiring rack copies still count
  against the budget until cleanup succeeds. New uploads continue falling
  back safely until both budget and measured free space allow vRack again;
  unknown capacity alone never triggers offloading. This moves data, not its
  retention deadline: no Orb archive expiry or account-storage cap is added.
  """
  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.Repo
  alias Tuist.Runners.Sites
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.DiskSnapshot
  alias Tuist.Sandboxes.Events
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Sandboxes.Workers.ArchiveDiskSnapshotWorker
  alias Tuist.Sandboxes.Workers.ArchiveSandboxesWorker
  alias Tuist.Sandboxes.Workers.DeleteArchiveCopyWorker
  alias Tuist.Sandboxes.Workers.OffloadArchivesWorker
  alias Tuist.Shards.Storage, as: ShardStorage
  alias Tuist.Storage

  require Logger

  @mib 1024 * 1024
  @gib 1024 * @mib
  @default_archive_budget_bytes 100 * @gib
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
  # Longer than the signed URL's lifetime plus a node's restore timeout.
  @copy_grace_seconds 2 * @url_ttl_seconds
  @copy_storage_salt "sandbox-archive-copy-storage"
  @storage_fields [:id, :s3_bucket_name, :s3_access_key_id, :s3_secret_access_key, :s3_region, :s3_endpoint]

  def object_prefix(account_id), do: "sandbox-archives/#{account_id}/"

  @doc """
  The bytes an account keeps in sandbox and disk snapshot archives,
  counting archives of restored Orbs whose deletion is still pending.
  """
  def archived_bytes(account_id) do
    archived_bytes(Sandbox, account_id: account_id) + archived_bytes(DiskSnapshot, account_id: account_id)
  end

  defp archived_bytes(schema, filters) do
    Repo.one(
      from s in schema,
        where: ^filters,
        where: not is_nil(s.archived_at),
        select: type(coalesce(sum(s.archive_bytes), 0), :integer)
    )
  end

  defp in_rack_archived_bytes(store) do
    routed_bytes(store) + retiring_bytes(store)
  end

  defp routed_bytes(store) do
    archived_bytes(Sandbox, archive_store: store) + archived_bytes(DiskSnapshot, archive_store: store)
  end

  # Switching the row does not reclaim disk: keep counting old copies until
  # their durable deletion jobs succeed, including jobs awaiting operator retry.
  defp retiring_bytes(store) do
    worker = Oban.Worker.to_string(DeleteArchiveCopyWorker)

    Repo.one(
      from j in Oban.Job,
        where: j.worker == ^worker and j.state not in ["completed", "cancelled"],
        where: fragment("? @> ?", j.args, ^%{"store" => store}),
        select: fragment("COALESCE(SUM((?->>'bytes')::bigint), 0)::bigint", j.args)
    )
  end

  @doc """
  One pass of the archive tier: deletes the archives of restored Orbs,
  aborts uploads and restores whose caller died, queues the oldest idle Orb
  on each node above its disk high-water mark, then archives Orbs paused
  for longer than the configured threshold and queues the archives of
  ready disk snapshots not archived yet. Archiving is off while no
  threshold is configured; the cleanups always run.
  """
  def run do
    delete_restored_archives()
    abandon_stuck_uploads()
    revert_stuck_restores()
    for {id, {config, _target}} <- stores(), accepting?(config), do: queue_offload(id, 0)

    case Environment.sandbox_archive_after_hours() do
      nil ->
        :ok

      hours ->
        for node <- pressure_nodes(), do: make_node_room([node.name], disk_pressure: true)
        hours |> candidates() |> Enum.each(&archive/1)
        queue_disk_snapshot_archives()
    end
  end

  @doc """
  Makes room for a create or restore the account's disk limit refused:
  queues the archive of its least recently paused idle Orb. Answers whether
  room is on its way, which is also the case while one of its archives is
  already uploading. Answers false when archiving is off or the account
  has no Orb to archive; only deleting sandboxes frees disk then.
  """
  def make_room(account_id) do
    cond do
      !Environment.sandbox_archive_after_hours() ->
        false

      Repo.exists?(from s in Sandbox, where: s.account_id == ^account_id and not is_nil(s.archive_upload_id)) ->
        true

      Repo.exists?(where(archivable(), [s], s.account_id == ^account_id)) ->
        {:ok, _job} = %{account_id: account_id} |> ArchiveSandboxesWorker.new() |> Oban.insert()
        true

      true ->
        false
    end
  end

  @doc """
  Makes room on nodes whose disk refused a new sandbox, any account's:
  queues the archive of the least recently paused idle Orb on them. Answers
  whether room is on its way, which is also the case while an archive is
  uploading from one of them. Answers false when archiving is off or they
  hold no Orb to archive. With `disk_pressure: true`, the worker rechecks
  the high-water mark before archiving; used by the proactive sweep.
  """
  def make_node_room(node_names, opts \\ []) when is_list(node_names) do
    node_names = node_names |> Enum.uniq() |> Enum.sort()

    cond do
      !Environment.sandbox_archive_after_hours() or node_names == [] ->
        false

      uploading_on?(node_names) ->
        true

      Repo.exists?(on_nodes(archivable(), node_names)) ->
        args = %{node_names: node_names}
        args = if opts[:disk_pressure], do: Map.put(args, :disk_pressure, true), else: args
        {:ok, _job} = args |> ArchiveSandboxesWorker.new() |> Oban.insert()
        true

      true ->
        false
    end
  end

  @doc """
  Archives the account's least recently paused idle Orb, queued by
  `make_room/1`.
  """
  def archive_oldest(account_id) do
    archivable() |> where([s], s.account_id == ^account_id) |> archive_first()
  end

  @doc """
  Archives the least recently paused idle Orb on the nodes, queued by
  `make_node_room/1`. With
  `disk_pressure: true`, only nodes still above the high-water mark qualify.
  """
  def archive_oldest_on(node_names, opts \\ []) when is_list(node_names) do
    # Recheck a queued pressure job: a delete or another archive may have
    # freed room since the sweep. On-demand jobs still make room unconditionally.
    node_names =
      if opts[:disk_pressure] do
        if Environment.sandbox_archive_after_hours() do
          for node <- pressure_nodes(), node.name in node_names, do: node.name
        else
          []
        end
      else
        node_names
      end

    if uploading_on?(node_names) do
      {:ok, :skipped}
    else
      archivable() |> on_nodes(node_names) |> archive_first()
    end
  end

  defp pressure_nodes do
    case Environment.sandbox_archive_disk_high_water_percent() do
      nil ->
        []

      percent ->
        Enum.filter(Nodes.connected_nodes(), fn node ->
          case Capacity.disk_budget_bytes(node) do
            :unbounded -> false
            budget -> Capacity.reserved_disk_bytes(node) * 100 > budget * percent
          end
        end)
    end
  end

  defp archive_first(query) do
    query
    |> order_by([s], asc: s.paused_at, asc: s.id)
    |> limit(1)
    |> Repo.one()
    |> case do
      nil -> {:ok, :skipped}
      sandbox -> archive(sandbox)
    end
  end

  defp on_nodes(query, node_names), do: where(query, [s], s.node_name in ^node_names)

  defp uploading_on?(node_names) do
    Repo.exists?(from s in Sandbox, where: s.node_name in ^node_names and not is_nil(s.archive_upload_id))
  end

  defp archivable do
    retry_before = DateTime.add(now(), -@retry_after_hours, :hour)

    from s in idle_paused_orbs(),
      where:
        is_nil(s.archived_at) and is_nil(s.archive_upload_id) and
          (is_nil(s.archive_attempted_at) or s.archive_attempted_at < ^retry_before)
  end

  defp idle_paused_orbs do
    from(s in Sandbox,
      where:
        s.state == :paused and s.platform == :linux and not is_nil(s.amp_orb_id) and not is_nil(s.node_name) and
          is_nil(s.residency_work_id) and not is_nil(s.paused_at)
    )
  end

  defp candidates(hours) do
    now = now()
    paused_before = DateTime.add(now, -hours, :hour)
    retry_before = DateTime.add(now, -@retry_after_hours, :hour)

    idle_paused_orbs()
    |> where([s], s.paused_at < ^paused_before)
    |> where([s], is_nil(s.archived_at) and is_nil(s.archive_upload_id))
    |> where([s], is_nil(s.archive_attempted_at) or s.archive_attempted_at < ^retry_before)
    |> order_by([s], asc: s.paused_at)
    |> limit(@per_run)
    |> Repo.all()
  end

  @doc """
  Whether `request/1` can archive the sandbox now: it is paused on a node
  and neither archived nor uploading. The same conditions `archive/1`
  starts an upload under.
  """
  def archivable?(%Sandbox{
        platform: :linux,
        state: :paused,
        node_name: node_name,
        paused_at: %DateTime{},
        archived_at: nil,
        archive_upload_id: nil
      })
      when is_binary(node_name), do: true

  def archivable?(%Sandbox{}), do: false

  @doc """
  Queues the archive of one paused sandbox someone asked for, whatever its
  source and however long it has been paused. The upload can take minutes,
  so it runs in `ArchiveSandboxesWorker`; the sandbox stays paused until
  it completes.
  """
  def request(%Sandbox{} = sandbox) do
    if archivable?(sandbox) do
      {:ok, _job} = %{sandbox_id: sandbox.id} |> ArchiveSandboxesWorker.new() |> Oban.insert()
      :ok
    else
      {:error, {:invalid_state, sandbox.state}}
    end
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
         {:ok, node} <- connected_node(node_name) do
      key = object_prefix(account.id) <> "#{sandbox.id}/#{Ecto.UUID.generate()}.sbxa"

      case start_upload(account, node, sandbox, key) do
        {:ok, upload} ->
          {:ok, _} =
            sandbox
            |> Sandbox.update_changeset(%{
              archive_key: key,
              archive_store: upload.store,
              archive_upload_id: upload.upload_id,
              archive_attempted_at: now()
            })
            |> Repo.update()

          {:ok, Map.put(upload, :sandbox, sandbox)}

        {:error, reason} ->
          mark_attempted(Sandbox, sandbox.id)
          {:error, reason}

        :unsupported ->
          {:ok, :skipped}
      end
    else
      _ -> {:ok, :skipped}
    end
  end

  # Starts the multipart upload of the disks of `subject` (a sandbox or a
  # disk snapshot) on `node` into the store `select_store/3` picks, and
  # presigns its part URLs for the node.
  defp start_upload(account, %{name: node_name} = node, subject, key) do
    max_bytes = Capacity.disk_snapshot_ceiling_bytes(subject, node) + @kernel_allowance_bytes
    max_bytes = max_bytes + div(max_bytes, 100)
    {store, actor} = select_store(account, node_name, max_bytes)

    if Storage.supports_signed_upload_headers?(actor) do
      {part_size, parts} = parts(max_bytes)

      with {:ok, upload_id} <- Storage.multipart_start(key, actor) do
        urls =
          for part <- 1..parts,
              do: Storage.multipart_generate_url(key, upload_id, part, actor, expires_in: @url_ttl_seconds)

        {:ok, %{store: store, actor: actor, key: key, upload_id: upload_id, part_size: part_size, urls: urls}}
      end
    else
      :unsupported
    end
  end

  # The archive is at most the files' sizes plus a small framing and
  # compression overhead; parts grow past the minimum so no archive needs
  # more than @max_parts presigned URLs.
  defp parts(max_bytes) do
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
    %{sandbox: sandbox, actor: actor, key: key, upload_id: upload_id} = upload
    parts = for %{"part_number" => number, "etag" => etag} <- parts, do: {number, etag}

    Sandboxes.with_sandbox_lock(sandbox.id, fn ->
      fresh = Sandboxes.get_sandbox_by_id(sandbox.id)

      if unchanged?(fresh, sandbox, upload_id) do
        case complete(key, upload_id, parts, actor) do
          :ok ->
            {:ok, archived} =
              fresh
              |> Sandbox.update_changeset(%{
                state: :archived,
                node_name: nil,
                residency_work_id: nil,
                archive_upload_id: nil,
                archive_attempted_at: nil,
                archive_bytes: bytes,
                archive_sha256: sha256,
                archived_at: now()
              })
              |> Repo.update()

            Events.record(archived, "archived")

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
            discard(Sandbox, upload)
            {:error, reason}
        end
      else
        discard(Sandbox, upload, cancelled: true)
        {:ok, :skipped}
      end
    end)
  end

  defp finish({:ok, _data}, upload) do
    discard(Sandbox, upload)
    {:error, :invalid_archive_result}
  end

  # sandboxd distinguishes a resume/delete cancellation from upload failures.
  # The next pause is eligible immediately, not after the failure backoff.
  defp finish({:error, "archive interrupted by a resume or delete"}, upload) do
    discard(Sandbox, upload, cancelled: true)
    {:ok, :skipped}
  end

  defp finish({:error, reason}, %{sandbox: sandbox} = upload) do
    Logger.warning("sandboxes: archiving a sandbox failed",
      sandbox_id: sandbox.id,
      node: sandbox.node_name,
      reason: inspect(reason)
    )

    discard(Sandbox, upload)
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
  defp complete(key, upload_id, parts, actor) do
    with result when result in [:ok, {:error, :multipart_upload_not_found}] <-
           Storage.multipart_complete_upload(key, upload_id, parts, actor),
         true <- readable?(key, actor, @readable_attempts) do
      :ok
    else
      false -> {:error, :archive_not_readable}
      {:error, reason} -> {:error, reason}
    end
  end

  defp readable?(key, actor, attempts) do
    cond do
      Storage.object_exists?(key, actor) ->
        true

      attempts <= 1 ->
        false

      true ->
        Process.sleep(@readable_interval_ms)
        readable?(key, actor, attempts - 1)
    end
  end

  # Aborts the upload and clears it from the row of `schema` (a sandbox or
  # a disk snapshot) that still records it. Only failures retain backoff.
  defp discard(schema, %{upload_id: upload_id} = upload, opts \\ []) do
    abort(upload)

    attrs = [archive_key: nil, archive_store: nil, archive_upload_id: nil, updated_at: now()]
    attrs = if opts[:cancelled], do: Keyword.put(attrs, :archive_attempted_at, nil), else: attrs

    Repo.update_all(from(s in schema, where: s.archive_upload_id == ^upload_id and is_nil(s.archived_at)),
      set: attrs
    )

    :ok
  end

  defp abort(%{actor: actor, key: key, upload_id: upload_id}) do
    case Storage.multipart_abort(key, upload_id, actor) do
      :ok -> :ok
      other -> Logger.warning("sandboxes: could not abort an archive upload", archive_key: key, reason: inspect(other))
    end
  end

  defp mark_attempted(schema, id) do
    Repo.update_all(from(s in schema, where: s.id == ^id), set: [archive_attempted_at: now()])
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
  Queues the upload of a ready disk snapshot when the archive tier is on.
  Answers whether it queued one.
  """
  def queue_disk_snapshot(%DiskSnapshot{} = snapshot) do
    if disk_snapshot_archivable?(snapshot) do
      {:ok, _job} = %{disk_snapshot_id: snapshot.id} |> ArchiveDiskSnapshotWorker.new() |> Oban.insert()
      true
    else
      false
    end
  end

  defp disk_snapshot_archivable?(%DiskSnapshot{state: :ready, node_name: node_name, archived_at: nil})
       when is_binary(node_name) do
    Environment.sandbox_archive_after_hours() != nil
  end

  defp disk_snapshot_archivable?(%DiskSnapshot{}), do: false

  # Ready snapshots still only on their node whose last upload failed long
  # enough ago, or that were never tried (a save while the tier was off, or
  # a job lost with its replica).
  defp queue_disk_snapshot_archives do
    retry_before = DateTime.add(now(), -@retry_after_hours, :hour)

    from(s in DiskSnapshot,
      where:
        s.state == :ready and not is_nil(s.node_name) and is_nil(s.archived_at) and is_nil(s.archive_upload_id) and
          (is_nil(s.archive_attempted_at) or s.archive_attempted_at < ^retry_before),
      order_by: [desc: s.last_used_at],
      limit: @per_run
    )
    |> Repo.all()
    |> Enum.each(&queue_disk_snapshot/1)
  end

  @doc """
  Uploads a ready disk snapshot from its node (`archive_disks`), which
  keeps its copy. Answers `{:ok, %DiskSnapshot{}}` once the archive is
  readable, `{:ok, :skipped}` when the snapshot is not archivable right now
  (already archived or uploading, archiving off, node away)
  or changed while uploading, or `{:error, reason}` when the upload failed;
  the next try waits six hours then.

  No lock is held during the upload. The row is claimed by recording the
  upload on it only while it has none, and the archive is recorded only
  while the row still names that upload: a snapshot deleted or superseded
  meanwhile has its upload aborted, or its object deleted.
  """
  def archive_disk_snapshot(%DiskSnapshot{id: id}) do
    with %DiskSnapshot{node_name: node_name, archive_upload_id: nil} = snapshot when is_binary(node_name) <-
           Repo.get(DiskSnapshot, id),
         true <- disk_snapshot_archivable?(snapshot),
         %Account{} = account <- Repo.get(Account, snapshot.account_id),
         {:ok, node} <- connected_node(node_name) do
      key = object_prefix(account.id) <> "disk-snapshots/#{snapshot.id}/#{Ecto.UUID.generate()}.sbxa"

      case start_upload(account, node, snapshot, key) do
        {:ok, upload} ->
          upload = Map.put(upload, :snapshot, snapshot)
          if claim(upload), do: upload |> transfer_disks() |> finish_disks(upload), else: skip(upload)

        {:error, reason} ->
          mark_attempted(DiskSnapshot, snapshot.id)
          {:error, reason}

        :unsupported ->
          {:ok, :skipped}
      end
    else
      _ -> {:ok, :skipped}
    end
  end

  defp claim(%{snapshot: snapshot, key: key, store: store, upload_id: upload_id}) do
    {count, _} =
      Repo.update_all(
        from(s in DiskSnapshot, where: s.id == ^snapshot.id and is_nil(s.archive_upload_id) and is_nil(s.archived_at)),
        set: [archive_key: key, archive_store: store, archive_upload_id: upload_id, archive_attempted_at: now()]
      )

    count == 1
  end

  defp skip(upload) do
    abort(upload)
    {:ok, :skipped}
  end

  defp transfer_disks(%{snapshot: snapshot} = upload) do
    Nodes.call(
      snapshot.node_name,
      "archive_disks",
      %{snapshot_id: snapshot.id, part_size: upload.part_size, part_urls: upload.urls},
      timeout: @archive_timeout
    )
  end

  defp finish_disks({:ok, %{"parts" => [_ | _] = parts, "bytes" => bytes, "sha256" => sha256} = data}, upload)
       when is_integer(bytes) and is_binary(sha256) do
    %{snapshot: snapshot, actor: actor, key: key, upload_id: upload_id} = upload
    parts = for %{"part_number" => number, "etag" => etag} <- parts, do: {number, etag}
    uploading = from(s in DiskSnapshot, where: s.id == ^snapshot.id and s.archive_upload_id == ^upload_id)

    with true <- Repo.exists?(uploading),
         :ok <- complete(key, upload_id, parts, actor) do
      now = now()

      case Repo.update_all(uploading,
             set: [
               archive_upload_id: nil,
               archive_bytes: bytes,
               archive_sha256: sha256,
               archived_at: now,
               updated_at: now
             ]
           ) do
        {1, _} ->
          Logger.info("sandboxes: disk snapshot archived",
            disk_snapshot_id: snapshot.id,
            node: snapshot.node_name,
            archive_bytes: bytes,
            stored_bytes: data["stored_bytes"],
            duration_ms: data["duration_ms"]
          )

          {:ok, Repo.get(DiskSnapshot, snapshot.id)}

        # Deleted while the upload completed: nothing would ever delete it.
        {0, _} ->
          Storage.delete_object(key, actor)
          {:ok, :skipped}
      end
    else
      false ->
        abort(upload)
        {:ok, :skipped}

      {:error, reason} ->
        discard(DiskSnapshot, upload)
        {:error, reason}
    end
  end

  defp finish_disks({:ok, _data}, upload) do
    discard(DiskSnapshot, upload)
    {:error, :invalid_archive_result}
  end

  # An older daemon answers `unknown op "archive_disks"`; like any other
  # failure, the snapshot stays on its node and is tried again later.
  defp finish_disks({:error, reason}, %{snapshot: snapshot} = upload) do
    Logger.warning("sandboxes: archiving a disk snapshot failed",
      disk_snapshot_id: snapshot.id,
      node: snapshot.node_name,
      reason: inspect(reason)
    )

    discard(DiskSnapshot, upload)
    {:error, reason}
  end

  @doc """
  Deletes the archive of a disk snapshot, aborting an upload in flight.
  Answers `:ok` when there is none.
  """
  def delete_disk_snapshot_archive(%DiskSnapshot{archive_upload_id: upload_id, archive_key: key} = snapshot)
      when is_binary(upload_id) do
    with {:ok, actor} <- actor(snapshot), do: abort(%{actor: actor, key: key, upload_id: upload_id})
    delete_object(snapshot)
  end

  def delete_disk_snapshot_archive(%DiskSnapshot{} = snapshot), do: delete_object(snapshot)

  @doc """
  What a node needs to restore the archive of an archived sandbox or of an
  archived disk snapshot: a presigned GET URL and the size and checksum it
  was uploaded with.
  """
  def restore_source(%Sandbox{state: :archived} = sandbox), do: download_source(sandbox)

  def restore_source(%DiskSnapshot{id: id, archived_at: %DateTime{}}) do
    # Snapshot callers don't hold a lifecycle lock. Never mint a new URL
    # for a retired copy from a struct loaded before an offload published.
    case Repo.get(DiskSnapshot, id) do
      %DiskSnapshot{archived_at: %DateTime{}} = snapshot -> download_source(snapshot)
      _ -> {:error, :archive_missing}
    end
  end

  def restore_source(_subject), do: {:error, :archive_missing}

  defp download_source(%{archive_key: key, archive_bytes: bytes, archive_sha256: sha256} = subject)
       when is_binary(key) and is_integer(bytes) and is_binary(sha256) do
    with {:ok, actor} <- actor(subject) do
      url = Storage.generate_download_url(key, actor, expires_in: @url_ttl_seconds)
      {:ok, %{url: url, bytes: bytes, sha256: sha256}}
    end
  end

  defp download_source(_subject), do: {:error, :archive_missing}

  @doc """
  Deletes the archive object of a sandbox or a disk snapshot. Answers `:ok`
  when there is none.
  """
  def delete_object(%{archive_key: nil}), do: :ok

  def delete_object(%{archive_key: key} = subject) do
    case actor(subject) do
      {:ok, actor} -> Storage.delete_object(key, actor)
      {:error, :not_found} -> :ok
      {:error, reason} -> {:error, reason}
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
          set: [
            archive_key: nil,
            archive_store: nil,
            archive_bytes: nil,
            archive_sha256: nil,
            archived_at: nil,
            archive_attempted_at: nil
          ]
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

    for {schema, id_key} <- [{Sandbox, :sandbox_id}, {DiskSnapshot, :disk_snapshot_id}] do
      from(s in schema, where: not is_nil(s.archive_upload_id) and s.archive_attempted_at < ^before)
      |> Repo.all()
      |> Enum.each(fn row ->
        Logger.warning("sandboxes: aborting an abandoned archive upload", [{id_key, row.id}])

        case actor(row) do
          {:ok, actor} -> discard(schema, %{actor: actor, key: row.archive_key, upload_id: row.archive_upload_id})
          {:error, _reason} -> :ok
        end
      end)
    end

    :ok
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

  @doc """
  The site of the in-rack store holding the archive of a sandbox or a disk
  snapshot, whose nodes alone can restore it, or `nil` when it is in the
  account's storage.
  """
  def restore_site(%{archive_store: nil}), do: nil

  def restore_site(%{archive_store: store}) do
    case Map.fetch(stores(), store) do
      {:ok, {config, _target}} -> config["site"]
      :error -> nil
    end
  end

  @doc """
  Deletes every archive of an account, in its storage and in every in-rack
  store.
  """
  def purge_account(%Account{} = account) do
    prefix = object_prefix(account.id)
    Storage.delete_all_objects(prefix, account)
    for {_id, {_config, target}} <- stores(), do: Storage.delete_all_objects(prefix, target)
    :ok
  end

  # The in-rack store an archive of a sandbox on `node_name` goes to, or the
  # account's storage. The node's site is only read when a store could take
  # the archive.
  defp select_store(account, node_name, max_bytes) do
    open =
      for {id, {config, target}} <- Enum.sort(stores()),
          accepting?(config),
          do: {id, config, target}

    site = if open != [] and not Account.custom_s3_storage_configured?(account), do: Sites.shard_storage_site(node_name)

    Enum.find_value(open, {nil, account}, fn {id, config, target} ->
      if is_binary(site) and config["site"] == site and Storage.available?(target) do
        if room_in_store?(id, config, max_bytes) do
          {id, target}
        else
          queue_offload(id, max_bytes)
          nil
        end
      end
    end)
  end

  defp accepting?(config), do: config["enabled"] == true and config["private_network_ready"] == true

  # Query each replica, not a load-balanced sample: every node must be able
  # to retain the archive. Leave room for metadata and metric sampling lag.
  defp room_in_store?(id, config, max_bytes) do
    budget = Map.get(config, "archive_budget_bytes", @default_archive_budget_bytes)

    with true <- in_rack_archived_bytes(id) < budget,
         {:ok, free} <- free_bytes(config) do
      free >= max_bytes + @gib
    else
      _ -> false
    end
  end

  defp free_bytes(%{"archive_capacity_urls" => [_ | _] = urls}) do
    Enum.reduce_while(urls, nil, fn url, minimum ->
      with {:ok, %Req.Response{status: 200, body: body}} when is_binary(body) <-
             Req.get(url,
               retry: false,
               redirect: false,
               receive_timeout: 1_000,
               pool_timeout: 1_000,
               connect_options: [timeout: 1_000]
             ),
           {:ok, free} <- metric_free_bytes(body) do
        {:cont, {:ok, if(minimum, do: min(elem(minimum, 1), free), else: free)}}
      else
        _ -> {:halt, :unknown}
      end
    end)
  end

  defp free_bytes(_config), do: :unknown

  defp metric_free_bytes(metrics) do
    readings =
      Regex.scan(~r/^garage_local_disk_avail\{volume="(data|metadata)"\} (\S+)\s*$/m, metrics, capture: :all_but_first)

    with [["data", data], ["metadata", metadata]] <- Enum.sort(readings),
         {data, ""} <- Float.parse(data),
         {metadata, ""} <- Float.parse(metadata) do
      {:ok, min(data, metadata)}
    else
      _ -> :unknown
    end
  end

  defp queue_offload(store, max_bytes) do
    %{store: store, max_bytes: max_bytes} |> OffloadArchivesWorker.new() |> Oban.insert!()
  end

  @doc """
  Offloads the oldest completed Orb and snapshot archives in a pressured store
  to their accounts' storage. Runs outside upload/placement locks. Each copy is
  streamed and verified against the recorded size and SHA-256 before switching
  the row. Old signed URLs remain usable during the deferred source cleanup.
  """
  def offload_oldest(store, max_bytes) do
    result =
      :global.trans(
        {{__MODULE__, :offload, store}, self()},
        fn ->
          case Map.fetch(stores(), store) do
            {:ok, {config, _target}} ->
              if accepting?(config), do: offload_needed(store, config, max_bytes), else: :ok

            :error ->
              :ok
          end
        end,
        [node() | Node.list()],
        0
      )

    if result == :aborted, do: {:snooze, 60}, else: result
  end

  defp offload_needed(store, config, max_bytes) do
    budget = Map.get(config, "archive_budget_bytes", @default_archive_budget_bytes)
    budget_deficit = max(0, routed_bytes(store) - budget + 1)

    space_deficit =
      case free_bytes(config) do
        {:ok, free} -> max(0, ceil(max_bytes + @gib - free) - retiring_bytes(store))
        :unknown -> 0
      end

    needed = max(budget_deficit, space_deficit)

    if needed > 0, do: offload_batch(store, needed), else: :ok
  end

  defp offload_batch(store, needed) do
    candidates = offload_candidates(store)

    candidates
    |> Enum.reduce_while(needed, fn subject, remaining ->
      case offload(subject) do
        :ok ->
          remaining = remaining - subject.archive_bytes
          if remaining <= 0, do: {:halt, :ok}, else: {:cont, remaining}

        {:ok, :skipped} ->
          {:cont, remaining}

        {:error, _reason} = error ->
          {:halt, error}
      end
    end)
    |> case do
      remaining when is_integer(remaining) and length(candidates) == @per_run -> {:snooze, 60}
      remaining when is_integer(remaining) -> :ok
      result -> result
    end
  end

  defp offload_candidates(store) do
    for_result =
      for {schema, state} <- [{Sandbox, :archived}, {DiskSnapshot, :ready}],
          subject <-
            Repo.all(
              from s in schema,
                where: s.state == ^state,
                where: s.archive_store == ^store and not is_nil(s.archived_at) and is_nil(s.archive_upload_id),
                where: not is_nil(s.archive_key) and s.archive_bytes > 0 and not is_nil(s.archive_sha256),
                order_by: [asc: s.archived_at, asc: s.id],
                limit: @per_run
            ),
          reduce: [] do
        subjects -> [subject | subjects]
      end

    for_result
    |> Enum.sort_by(&{DateTime.to_unix(&1.archived_at, :microsecond), &1.id})
    |> Enum.take(@per_run)
  end

  defp offload(subject) do
    with {:ok, source} <- actor(subject),
         %Account{} = account <- Repo.get(Account, subject.account_id) do
      # A new key for every attempt lets an interrupted copy's cleanup run
      # without ever deleting a later attempt's successful copy.
      key = Path.join(Path.dirname(subject.archive_key), "#{Ecto.UUID.generate()}.sbxa")
      queue_copy_cleanup(subject, key, nil, account)

      # Storage's S3 downloader emits 1 MiB chunks, too small for multipart
      # upload's 5 MiB minimum. Assemble bounded 32 MiB parts, plus the tail.
      result =
        subject.archive_key
        |> Storage.stream_object(source)
        |> Stream.chunk_every(div(@min_part_size, @mib))
        |> Stream.map(&IO.iodata_to_binary/1)
        |> Storage.upload(key, account)

      case result do
        {:error, _reason} = error ->
          error

        _ ->
          with :ok <- verify_copy(subject, key, account) do
            publish_offload(subject, key, account)
          end
      end
    else
      nil -> {:ok, :skipped}
      {:error, _reason} = error -> error
    end
  end

  defp verify_copy(subject, key, account) do
    if readable?(key, account, @readable_attempts) do
      {bytes, hash} =
        key
        |> Storage.stream_object(account)
        |> Enum.reduce({0, :crypto.hash_init(:sha256)}, fn chunk, {bytes, hash} ->
          {bytes + byte_size(chunk), :crypto.hash_update(hash, chunk)}
        end)

      sha256 = hash |> :crypto.hash_final() |> Base.encode16(case: :lower)

      if bytes == subject.archive_bytes and sha256 == subject.archive_sha256,
        do: :ok,
        else: {:error, :archive_copy_mismatch}
    else
      {:error, :archive_not_readable}
    end
  end

  defp publish_offload(subject, key, account) do
    # Share the lifecycle lock only for publication, never for the transfer.
    # DiskSnapshots.delete/1 uses the same lock and reloads the current route.
    subject.id
    |> Sandboxes.with_sandbox_lock(
      fn ->
        fn ->
          {count, _} =
            Repo.update_all(
              from(s in subject.__struct__,
                where:
                  s.id == ^subject.id and s.archive_key == ^subject.archive_key and
                    s.archive_store == ^subject.archive_store and s.state == ^subject.state
              ),
              set: [archive_key: key, archive_store: nil, updated_at: now()]
            )

          if count == 1 do
            queue_copy_cleanup(subject, subject.archive_key, subject.archive_store, account)
            :ok
          else
            {:ok, :skipped}
          end
        end
        |> Repo.transaction()
        |> case do
          {:ok, result} -> result
          {:error, reason} -> {:error, reason}
        end
      end,
      wait: false
    )
    |> case do
      {:error, :locked} -> {:ok, :skipped}
      result -> result
    end
  end

  defp queue_copy_cleanup(subject, key, store, account) do
    # A copy can finish after account deletion purges its prefix. Like
    # DeleteAccountArtifactsWorker, retain only an encrypted storage actor so
    # cleanup can outlive that row, including accounts with custom S3 storage.
    storage = Phoenix.Token.encrypt(Tuist.Web.endpoint(), @copy_storage_salt, Map.take(account, @storage_fields))

    %{
      "account_id" => subject.account_id,
      "kind" => if(is_struct(subject, Sandbox), do: "sandbox", else: "snapshot"),
      "id" => subject.id,
      "key" => key,
      "store" => store,
      "bytes" => subject.archive_bytes,
      "encrypted_storage" => storage
    }
    |> DeleteArchiveCopyWorker.new(schedule_in: @copy_grace_seconds)
    |> Oban.insert!()
  end

  @doc """
  Deletes an unreferenced migration copy after its grace period. Both failed
  destination copies and retired rack copies have durable cleanup jobs; the
  active archive is never deleted by these jobs.
  """
  def delete_archive_copy(%{"kind" => kind, "id" => id, "key" => key, "store" => store} = args) do
    schema = if kind == "sandbox", do: Sandbox, else: DiskSnapshot

    case Repo.get(schema, id) do
      %{archive_key: ^key, archive_store: ^store} ->
        :ok

      _ ->
        with {:ok, actor} <- copy_actor(args) do
          Storage.delete_object(key, actor)
        end
    end
  end

  defp copy_actor(%{"store" => nil, "account_id" => id, "encrypted_storage" => encrypted}) do
    case Phoenix.Token.decrypt(Tuist.Web.endpoint(), @copy_storage_salt, encrypted, max_age: :infinity) do
      {:ok, %{id: ^id} = storage} -> {:ok, struct(Account, storage)}
      _ -> {:error, :invalid_archive_copy_storage}
    end
  end

  defp copy_actor(args), do: actor(%{archive_store: args["store"]})

  defp actor(%{archive_store: nil, account_id: account_id}) do
    case Repo.get(Account, account_id) do
      %Account{} = account -> {:ok, account}
      nil -> {:error, :not_found}
    end
  end

  defp actor(%{archive_store: store}) do
    case Map.fetch(stores(), store) do
      {:ok, {_config, target}} -> {:ok, target}
      :error -> {:error, :archive_store_unavailable}
    end
  end

  # Shard storage targets that hold archives, in their `archive_bucket`.
  defp stores do
    for {id, %{"archive_bucket" => bucket} = config} <- Environment.shard_storage_targets(),
        is_binary(bucket) and bucket != "",
        {:ok, target} <- [ShardStorage.s3_target(id, Map.put(config, "bucket", bucket))],
        into: %{},
        do: {id, {config, target}}
  end

  defp connected_node(node_name) do
    case Enum.find(Nodes.connected_nodes(), &(&1.name == node_name)) do
      nil -> {:error, :not_connected}
      node -> {:ok, node}
    end
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)
end
