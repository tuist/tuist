defmodule Tuist.Sandboxes.DiskSnapshots do
  @moduledoc """
  Disk snapshots of paused sandboxes (`Tuist.Sandboxes.DiskSnapshot`): of
  Amp Orbs under Amp's identifier, and of the builder sandboxes in which a
  Claude Code environment's setup script prepared a repository
  (`Tuist.Sandboxes.ClaudeCodeSnapshots`).

  Saving a snapshot is a copy-on-write clone on the node that held its
  source sandbox, and a sandbox created from it on that node clones it
  again. Each snapshot reserves its full ceiling against that node's disk
  budget. While the archive tier is on, a ready snapshot is also uploaded
  to object storage (`Tuist.Sandboxes.Archives.archive_disk_snapshot/1`),
  so a sandbox created where its node has no room, or after the node lost
  the copy, boots from the archive on any node instead of the template. An
  archived snapshot whose node copy is gone keeps its row with no
  `node_name`; one that was never archived is dropped.

  An archived snapshot of a popular lineage is also copied onto other nodes
  (`Tuist.Sandboxes.DiskSnapshotCopy`, `copy/1`): a spawn that finds every
  node holding it full otherwise pays the archive download on its path. The
  nodes are placed as runner cache volumes are (`Tuist.Runners.VolumePlacement`):
  by the snapshot's lineage, which Amp's refreshes keep, so every snapshot of
  a project goes to the same nodes, and as many as half again its most Orbs
  running at once, with at most four copies. A copy goes only to a node whose reserved disk stays
  under the archive high-water mark with it, so it never makes an Orb get
  archived, and it is the first thing dropped when a node needs room
  (`drop_copy/1`).

  Snapshots unused for longer than Amp reuses one, Claude Code snapshots
  included, are deleted with their archive and copies, copies unused for a
  day are dropped, and the node's reports reconcile copies the database no
  longer knows and rows whose copy the node lost.
  """
  import Ecto.Query

  alias Tuist.Environment
  alias Tuist.Repo
  alias Tuist.Runners.Sites
  alias Tuist.Runners.VolumePlacement
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.AgentEnvironment
  alias Tuist.Sandboxes.Archives
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.DiskSnapshot
  alias Tuist.Sandboxes.DiskSnapshotCopy
  alias Tuist.Sandboxes.MacosCapacity
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Sandboxes.Workers.BuildRepositorySnapshotWorker
  alias Tuist.Sandboxes.Workers.CopyDiskSnapshotWorker
  alias Tuist.Tasks

  require Logger

  # Amp reuses a project snapshot for up to 72 hours.
  @unused_retention_hours 72
  @stuck_saving_minutes 15
  # A build's command runs for at most an hour
  # (`Tuist.Sandboxes.ClaudeCodeSnapshots`); its job then saves or fails it.
  @stuck_build_minutes 90
  # A failed build keeps its key from building again for this long.
  @failed_build_retry_minutes 60
  # A report can be older than a save that just finished.
  @report_grace_seconds 120
  @save_timeout 120_000
  # A snapshot is popular once this many Orbs were spawned in its lineage
  # within the window. Measured in production (2026-11): a busy project
  # spawns over ten Orbs a day.
  @popular_spawns 2
  @popularity_window_hours 24
  # An Orb in these states holds memory on its node.
  @live_states [:creating, :running, :resuming]
  # Extra node copies of one snapshot at most, however busy its lineage.
  # Each reserves a snapshot ceiling (about 22 GiB) of its node's disk budget.
  @max_copies 4
  @copy_unused_hours 24
  # The proactive disk-pressure sweep leaves copies used this recently alone:
  # an Orb spawned on a copy pushes its node over the high-water mark, and
  # dropping that copy then threw it away a minute after its first use
  # (measured in production, 2026-11: one snapshot was copied seven times in
  # nine hours).
  @copy_pressure_idle_minutes 60
  # A copy downloads the whole archive (4.4 GB at p50), as long as the
  # daemon's archive timeout at most.
  @copy_timeout to_timeout(minute: 30)
  @stuck_copying_minutes 45

  def unused_retention_hours, do: @unused_retention_hours

  @doc """
  The newest ready snapshot an account saved under `amp_snapshot_id` that a
  sandbox of this template and workspace size can be created from.
  """
  def find_ready(account_id, amp_snapshot_id, template, workspace_gb) when is_binary(amp_snapshot_id) do
    Repo.one(
      from(s in DiskSnapshot,
        where:
          s.account_id == ^account_id and s.amp_snapshot_id == ^amp_snapshot_id and s.state == :ready and
            s.template == ^template and s.workspace_gb == ^workspace_gb,
        order_by: [desc: s.inserted_at],
        limit: 1
      )
    )
  end

  @doc """
  The newest ready snapshot of `repository` (`owner/name`) a Claude Code
  environment saved after running the setup script whose SHA-256 is
  `setup_sha256`, for the environment's template and workspace size, or the
  `template:` and `workspace_gb:` given. Only a snapshot of a template tag a
  connected node creates new sandboxes with qualifies: the rootfs carries
  `sbx-worker`, so a snapshot of an older image would hold sessions back on it.
  """
  def find_ready_for_repository(%AgentEnvironment{} = agent_environment, repository, setup_sha256, opts \\ [])
      when is_binary(repository) and is_binary(setup_sha256) do
    template = Keyword.get(opts, :template, agent_environment.template)
    workspace_gb = Keyword.get(opts, :workspace_gb, agent_environment.workspace_gb)

    case current_template_tags(template) do
      [] ->
        nil

      tags ->
        Repo.one(
          from(s in DiskSnapshot,
            where: s.agent_environment_id == ^agent_environment.id and s.repository == ^repository,
            where: s.setup_sha256 == ^setup_sha256 and s.state == :ready,
            where: s.template == ^template and s.template_tag in ^tags,
            where: s.workspace_gb == ^workspace_gb,
            order_by: [desc: s.inserted_at],
            limit: 1
          )
        )
    end
  end

  # The tag a node gives a new sandbox of `template`: its configured default
  # tag for its default template, else the only one it has ready
  # (sandboxd's `resolveTemplate`).
  defp current_template_tags(template) do
    Nodes.connected_nodes()
    |> Enum.flat_map(fn node ->
      configured = Map.get(node, :default_template_tag)

      if Map.get(node, :default_template) == template and is_binary(configured) do
        [configured]
      else
        for %{name: ^template, ready: true, tag: tag} <- Map.get(node, :templates, []), is_binary(tag), do: tag
      end
    end)
    |> Enum.uniq()
  end

  @doc """
  Starts building the snapshot of `repository` for a Claude Code
  environment and the setup script whose SHA-256 is `setup_sha256`
  (`Tuist.Sandboxes.Workers.BuildRepositorySnapshotWorker`), on the
  environment's platform, template and workspace size, or the `platform:`,
  `template:` and `workspace_gb:` given. Answers
  `{:error, :already_building}` while a build of the same key runs or for a
  while after one failed.
  """
  def start_build(%AgentEnvironment{} = agent_environment, repository, setup_sha256, opts \\ [])
      when is_binary(repository) and is_binary(setup_sha256) do
    attrs = %{
      account_id: agent_environment.account_id,
      agent_environment_id: agent_environment.id,
      repository: repository,
      setup_sha256: setup_sha256,
      platform: Keyword.get(opts, :platform, agent_environment.platform),
      template: Keyword.get(opts, :template, agent_environment.template),
      workspace_gb: Keyword.get(opts, :workspace_gb, agent_environment.workspace_gb),
      last_used_at: now()
    }

    Repo.transaction(fn ->
      with {:ok, build} <- attrs |> DiskSnapshot.build_changeset() |> Repo.insert(),
           {:ok, _job} <- %{disk_snapshot_id: build.id} |> BuildRepositorySnapshotWorker.new() |> Oban.insert() do
        build
      else
        {:error, reason} ->
          Repo.rollback(if unique_violation?(reason), do: :already_building, else: reason)
      end
    end)
  end

  defp unique_violation?(%Ecto.Changeset{errors: errors}),
    do: Enum.any?(errors, fn {_field, {_message, opts}} -> opts[:constraint] == :unique end)

  defp unique_violation?(_reason), do: false

  @doc """
  Saves the disks of a build's paused builder sandbox as the repository's
  snapshot, replacing the environment's older snapshots of the repository,
  and ends the build. The snapshot takes over the builder's disk
  reservation, since the caller deletes the builder next: a node with room
  for the builder has room for its snapshot.
  """
  def save_build(%DiskSnapshot{state: :building} = build, %Sandbox{state: :paused, node_name: node_name} = sandbox)
      when is_binary(node_name) do
    with {:ok, ready} <-
           do_save(
             sandbox,
             %{
               agent_environment_id: build.agent_environment_id,
               repository: build.repository,
               setup_sha256: build.setup_sha256,
               commit_sha: build.commit_sha
             },
             releases: sandbox,
             shutdown: true
           ) do
      Repo.delete_all(from(s in DiskSnapshot, where: s.id == ^build.id))
      {:ok, ready}
    end
  end

  @doc """
  Marks a build failed. The row keeps the key from building again until
  `delete_expired/0` removes it.
  """
  def fail_build(%DiskSnapshot{state: :building, id: id}) do
    Repo.update_all(from(s in DiskSnapshot, where: s.id == ^id and s.state == :building),
      set: [state: :failed, updated_at: now()]
    )

    :ok
  end

  @doc """
  Saves a paused sandbox's disks under `amp_snapshot_id` on its node and
  replaces the older snapshots saved under that identifier, then queues its
  upload to object storage (`Archives.queue_disk_snapshot/1`). The
  sandbox's last pause must have synced its disks. A repeated save of the
  same pause does nothing.
  """
  def save(%Sandbox{state: :paused, node_name: node_name} = sandbox, amp_snapshot_id)
      when is_binary(node_name) and is_binary(amp_snapshot_id) do
    if saved_since_pause?(sandbox, amp_snapshot_id) do
      {:ok, :already_saved}
    else
      do_save(sandbox, %{amp_snapshot_id: amp_snapshot_id, lineage_id: lineage_id(sandbox, amp_snapshot_id)})
    end
  end

  def save(%Sandbox{state: state}, _amp_snapshot_id), do: {:error, {:invalid_state, state}}

  defp do_save(%Sandbox{node_name: node_name} = sandbox, key, opts \\ []) do
    attrs = %{
      account_id: sandbox.account_id,
      source_sandbox_id: sandbox.id,
      node_name: node_name,
      template: sandbox.template,
      template_tag: sandbox.template_tag,
      workspace_gb: sandbox.workspace_gb,
      platform: sandbox.platform,
      last_used_at: now()
    }

    attrs = Map.merge(attrs, key)
    insert = fn -> %DiskSnapshot{} |> DiskSnapshot.create_changeset(attrs) |> Repo.insert() end

    with {:ok, node} <- connected_node(node_name),
         {:ok, snapshot} <- reserve_disk(sandbox, node, attrs, insert, opts) do
      case Nodes.call(node_name, "save_disks", save_args(sandbox, snapshot, opts), timeout: @save_timeout) do
        {:ok, data} ->
          {:ok, ready} =
            snapshot
            |> DiskSnapshot.update_changeset(%{state: :ready, last_used_at: now(), disk_bytes: data["bytes"]})
            |> Repo.update()

          release_macos_slot(sandbox)

          Logger.info("sandboxes: disk snapshot saved",
            disk_snapshot_id: ready.id,
            sandbox_id: sandbox.id,
            node: node_name,
            duration_ms: data["duration_ms"],
            bytes: data["bytes"]
          )

          delete_superseded(ready, sandbox)
          Archives.queue_disk_snapshot(ready)
          {:ok, ready}

        {:error, reason} ->
          delete(snapshot)
          {:error, reason}
      end
    end
  end

  # A macOS snapshot holds only the blocks its overlay wrote, which only the
  # host can measure: the host admits the save against its disk budget and
  # reports the bytes its snapshots hold (`MacosCapacity`). The Linux ceiling
  # would charge each one a whole macOS root disk.
  defp reserve_disk(%Sandbox{platform: :darwin}, _node, _attrs, insert, _opts), do: insert.()
  defp reserve_disk(_sandbox, node, attrs, insert, opts), do: Capacity.reserve_disk_snapshot(node, attrs, insert, opts)

  # A macOS host saves only a stopped VM's disks, so the save evicted the
  # paused VM and gave its slot back. The host's next report says so too;
  # this frees the slot for placement without waiting for it.
  defp release_macos_slot(%Sandbox{platform: :darwin, id: id}) do
    Repo.update_all(from(s in Sandbox, where: s.id == ^id and s.state == :paused), set: [resident: false])
  end

  defp release_macos_slot(_sandbox), do: :ok

  # The refresh chain a save continues: the lineage of an older save of this
  # id or of the snapshot the Orb was spawned from, else the id the Orb was
  # spawned from, else this one. It stays the same across Amp's refreshes,
  # so every snapshot of a project is copied to the same nodes.
  defp lineage_id(%Sandbox{account_id: account_id, amp_base_snapshot_id: base}, amp_snapshot_id) do
    ids = Enum.reject([amp_snapshot_id, base], &is_nil/1)

    Repo.one(
      from(s in DiskSnapshot,
        where: s.account_id == ^account_id and s.amp_snapshot_id in ^ids and not is_nil(s.lineage_id),
        order_by: [desc: s.inserted_at],
        limit: 1,
        select: s.lineage_id
      )
    ) || base || amp_snapshot_id
  end

  defp saved_since_pause?(%Sandbox{id: id, account_id: account_id, paused_at: paused_at}, amp_snapshot_id) do
    query =
      from(s in DiskSnapshot,
        where:
          s.account_id == ^account_id and s.amp_snapshot_id == ^amp_snapshot_id and s.source_sandbox_id == ^id and
            s.state == :ready
      )

    query = if paused_at, do: where(query, [s], s.inserted_at >= ^paused_at), else: query
    Repo.exists?(query)
  end

  # A Claude Code environment keeps one snapshot per repository for its
  # sessions: the newest save replaces the older ready ones of its platform,
  # whichever setup script or template they ran. The Macs its sessions create
  # keep one per Xcode template (`ClaudeCodeSnapshots.mac_build?/2`), which
  # those of the environment's own platform leave alone.
  # Builds of the repository are left to finish.
  #
  # Amp refreshes a project snapshot under a new identifier: it spawns an
  # Orb from the current one and has it save the next. Once that save is
  # ready Amp boots new Orbs from it, so copies of the identifier the Orb
  # was spawned from are superseded too, not only older saves of this one.
  defp delete_superseded(%DiskSnapshot{agent_environment_id: agent_environment_id} = snapshot, _sandbox)
       when is_integer(agent_environment_id) do
    query =
      from(s in DiskSnapshot,
        where:
          s.agent_environment_id == ^agent_environment_id and s.repository == ^snapshot.repository and
            s.platform == ^snapshot.platform and s.state == :ready and s.id != ^snapshot.id and
            s.inserted_at <= ^snapshot.inserted_at
      )

    environment_platform =
      Repo.one(from(e in AgentEnvironment, where: e.id == ^agent_environment_id, select: e.platform))

    query =
      if snapshot.platform == environment_platform,
        do: query,
        else: where(query, [s], s.template == ^snapshot.template)

    query
    |> Repo.all()
    |> Enum.each(&delete/1)
  end

  defp delete_superseded(%DiskSnapshot{} = snapshot, %Sandbox{amp_base_snapshot_id: base}) do
    superseded_ids = Enum.reject([snapshot.amp_snapshot_id, base], &is_nil/1)

    from(s in DiskSnapshot,
      where:
        s.account_id == ^snapshot.account_id and s.amp_snapshot_id in ^superseded_ids and
          s.id != ^snapshot.id and s.inserted_at <= ^snapshot.inserted_at
    )
    |> Repo.all()
    |> Enum.each(&delete/1)
  end

  @doc """
  Records that a sandbox was created from the snapshot, which keeps it
  from expiring.
  """
  def touch(%DiskSnapshot{id: id}, node_name \\ nil) do
    Repo.update_all(from(s in DiskSnapshot, where: s.id == ^id), set: [last_used_at: now()])

    if node_name,
      do:
        Repo.update_all(from(c in DiskSnapshotCopy, where: c.disk_snapshot_id == ^id and c.node_name == ^node_name),
          set: [last_used_at: now()]
        )

    :ok
  end

  @doc """
  The nodes holding a ready copy of the snapshot: its own node and the
  nodes it was copied to.
  """
  def held_nodes(%DiskSnapshot{id: id, node_name: node_name}) do
    copies =
      Repo.all(from(c in DiskSnapshotCopy, where: c.disk_snapshot_id == ^id and c.state == :ready, select: c.node_name))

    if node_name, do: [node_name | copies], else: copies
  end

  @doc """
  Forgets the node copy when the node answered that it no longer holds it:
  an archived snapshot keeps its row without a node, any other is dropped.
  """
  def forget_if_missing(%DiskSnapshot{} = snapshot, node_name, reason) when is_binary(reason) do
    cond do
      not String.contains?(reason, "disk snapshot not found") -> :ok
      node_name != snapshot.node_name -> delete_copy_row(snapshot.id, node_name)
      snapshot.archived_at -> forget_node_copy(snapshot)
      true -> delete(snapshot)
    end

    :ok
  end

  def forget_if_missing(_snapshot, _node_name, _reason), do: :ok

  defp delete_copy_row(snapshot_id, node_name) do
    Repo.delete_all(from(c in DiskSnapshotCopy, where: c.disk_snapshot_id == ^snapshot_id and c.node_name == ^node_name))
  end

  # The node lost its copy (it answered so, or stopped listing it). Only the
  # archive is left of an archived snapshot.
  defp forget_node_copy(%DiskSnapshot{archived_at: %DateTime{}} = snapshot) do
    Repo.update_all(from(s in DiskSnapshot, where: s.id == ^snapshot.id), set: [node_name: nil, updated_at: now()])
  end

  defp forget_node_copy(%DiskSnapshot{} = snapshot) do
    Repo.delete_all(from(s in DiskSnapshot, where: s.id == ^snapshot.id))
    # An upload in flight fails without the copy; abort it in case its caller died.
    if snapshot.archive_key, do: Tasks.run_async(fn -> Archives.delete_disk_snapshot_archive(snapshot) end)
  end

  @doc """
  Removes the copy from its node, the archive and the row. A node that is
  not connected removes the copy when its next report lists one the
  database no longer knows. When storage refuses to delete a completed
  archive, the row stays without a node, so a later expiry or supersede
  deletes the archive again.
  """
  def delete(%DiskSnapshot{id: id}) do
    # An offload can change the archive's route after the caller loaded it.
    # Publication uses this same lock, without holding it during the copy.
    Sandboxes.with_sandbox_lock(
      id,
      fn ->
        case Repo.get(DiskSnapshot, id) do
          nil -> :ok
          snapshot -> do_delete(snapshot)
        end
      end,
      wait: false
    )
  end

  defp do_delete(snapshot) do
    if snapshot.node_name, do: delete_node_copy(snapshot.id, snapshot.node_name)

    # The rows go with the snapshot's; a node that misses this removes its
    # copy at its next report.
    from(c in DiskSnapshotCopy, where: c.disk_snapshot_id == ^snapshot.id, select: c.node_name)
    |> Repo.all()
    |> Enum.each(&delete_node_copy(snapshot.id, &1))

    case Archives.delete_disk_snapshot_archive(snapshot) do
      :ok ->
        Repo.delete_all(from(s in DiskSnapshot, where: s.id == ^snapshot.id))
        :ok

      {:error, reason} ->
        Logger.warning("sandboxes: failed to delete a disk snapshot's archive",
          disk_snapshot_id: snapshot.id,
          reason: inspect(reason)
        )

        # Only a completed archive is worth another try; an upload in flight
        # left nothing readable behind.
        if snapshot.archived_at,
          do:
            Repo.update_all(from(s in DiskSnapshot, where: s.id == ^snapshot.id),
              set: [node_name: nil, updated_at: now()]
            ),
          else: Repo.delete_all(from(s in DiskSnapshot, where: s.id == ^snapshot.id))

        {:error, reason}
    end
  end

  defp delete_node_copy(snapshot_id, node_name) do
    case Nodes.call(node_name, "delete_disks", Nodes.command_args(node_name, %{snapshot_id: snapshot_id}), []) do
      {:ok, _data} ->
        :ok

      {:error, reason} ->
        Logger.warning("sandboxes: failed to delete a disk snapshot on its node",
          disk_snapshot_id: snapshot_id,
          node: node_name,
          reason: inspect(reason)
        )
    end
  end

  @doc """
  Deletes snapshots unused for longer than Amp reuses one, saves that never
  finished, builds that outlived their command's deadline (with their
  builder sandbox), and failed builds old enough to try again.
  """
  def delete_expired do
    unused_before = DateTime.add(now(), -@unused_retention_hours, :hour)
    stuck_before = DateTime.add(now(), -@stuck_saving_minutes, :minute)
    build_before = DateTime.add(now(), -@stuck_build_minutes, :minute)
    failed_before = DateTime.add(now(), -@failed_build_retry_minutes, :minute)

    from(s in DiskSnapshot,
      where:
        (s.state == :ready and s.last_used_at < ^unused_before) or
          (s.state == :saving and s.updated_at < ^stuck_before) or
          (s.state == :building and s.inserted_at < ^build_before) or
          (s.state == :failed and s.updated_at < ^failed_before)
    )
    |> Repo.all()
    |> Enum.each(fn snapshot ->
      Logger.info("sandboxes: deleting an expired disk snapshot",
        disk_snapshot_id: snapshot.id,
        node: snapshot.node_name,
        state: snapshot.state,
        last_used_at: snapshot.last_used_at
      )

      delete_builder(snapshot)
      delete(snapshot)
    end)

    delete_expired_copies()
  end

  defp delete_expired_copies do
    copy_unused_before = DateTime.add(now(), -@copy_unused_hours, :hour)
    copy_stuck_before = DateTime.add(now(), -@stuck_copying_minutes, :minute)

    from(c in DiskSnapshotCopy,
      where:
        (c.state == :ready and c.last_used_at < ^copy_unused_before) or
          (c.state == :copying and c.updated_at < ^copy_stuck_before)
    )
    |> Repo.all()
    |> Enum.each(fn copy ->
      Logger.info("sandboxes: dropping an unused disk snapshot copy",
        disk_snapshot_id: copy.disk_snapshot_id,
        node: copy.node_name,
        state: copy.state
      )

      delete_copy(copy)
    end)
  end

  # A build's builder sandbox has the build's id.
  defp delete_builder(%DiskSnapshot{state: :building, id: id}) do
    case Sandboxes.get_sandbox_by_id(id) do
      %Sandbox{} = sandbox -> Sandboxes.delete(sandbox)
      nil -> :ok
    end
  end

  defp delete_builder(_snapshot), do: :ok

  @doc """
  Aligns the database with the disk snapshots a node lists in its `hello`
  or `report`: copies no row places on the node are deleted from it, and
  rows whose copy the node no longer lists lose it: an archived one keeps
  its row without a node, any other is dropped. A daemon that does not
  report disk snapshots is left alone.
  """
  def reconcile_node_report(node_name, %{"disk_snapshots" => reported}) when is_binary(node_name) and is_list(reported) do
    reported_ids = for %{"id" => id} <- reported, {:ok, uuid} <- [Ecto.UUID.cast(id)], do: uuid

    # A row that no longer names this node (its copy was given up for lost)
    # does not reserve the node's disk, so the copy goes too.
    copies =
      from(c in DiskSnapshotCopy,
        where: c.disk_snapshot_id in ^reported_ids and c.node_name == ^node_name,
        select: c.disk_snapshot_id
      )

    known =
      from(s in DiskSnapshot, where: s.id in ^reported_ids and s.node_name == ^node_name, select: s.id)
      |> union(^copies)
      |> Repo.all()

    reported_ids
    |> Kernel.--(known)
    |> Enum.each(&delete_orphan(node_name, &1))

    reported_before = DateTime.add(now(), -@report_grace_seconds, :second)

    from(s in DiskSnapshot,
      where:
        s.node_name == ^node_name and s.id not in ^reported_ids and s.state == :ready and
          s.updated_at < ^reported_before
    )
    |> Repo.all()
    |> Enum.each(fn snapshot ->
      Logger.warning("sandboxes: disk snapshot missing on node",
        disk_snapshot_id: snapshot.id,
        node: node_name
      )

      forget_node_copy(snapshot)
    end)

    forget_missing_copies(node_name, reported_ids, reported_before)
    :ok
  end

  def reconcile_node_report(_node_name, _report), do: :ok

  defp forget_missing_copies(node_name, reported_ids, reported_before) do
    from(c in DiskSnapshotCopy,
      where:
        c.node_name == ^node_name and c.disk_snapshot_id not in ^reported_ids and c.state == :ready and
          c.updated_at < ^reported_before
    )
    |> Repo.all()
    |> Enum.each(fn copy ->
      Logger.warning("sandboxes: disk snapshot copy missing on node",
        disk_snapshot_id: copy.disk_snapshot_id,
        node: node_name
      )

      Repo.delete(copy, allow_stale: true)
    end)
  end

  @doc """
  Queues copies of an archived snapshot onto other nodes when it is popular.
  Answers whether it queued them.
  """
  def queue_copies(%DiskSnapshot{} = snapshot) do
    if copyable?(snapshot) and popular?(spawns(snapshot)) do
      {:ok, _job} = %{disk_snapshot_id: snapshot.id} |> CopyDiskSnapshotWorker.new() |> Oban.insert()
      true
    else
      false
    end
  end

  defp copyable?(%DiskSnapshot{state: :ready, archived_at: %DateTime{}}), do: true
  defp copyable?(%DiskSnapshot{}), do: false

  # The Orbs spawned within the window in the snapshot's lineage, or from its
  # Amp identifier or the one its source Orb was spawned from (Orbs spawned
  # before lineages were recorded on them). Amp refreshes a project snapshot
  # under a new identifier at nearly every spawn, so a fresh snapshot is as
  # popular as its lineage; counting only its own identifiers left it
  # unpopular when archived, and its copies came after the next spawn had
  # already missed (measured in production, 2026-11). Each is the span it
  # held memory: from its creation to its last change, still open (`nil`)
  # while it is live.
  #
  # A Claude Code snapshot has no Amp identifier: its spawns are the
  # sessions of its environment on the snapshot's platform (builders have no
  # session; sessions do not record their repository, so they count for each
  # of its repositories' snapshots), and the Macs created through the account
  # API for its repository on its template, which the macOS snapshot of a
  # Linux environment serves (`Query.run(:create)`). A create that failed
  # (`:error`, such as a busy fleet) booted nothing and does not count.
  defp spawns(%DiskSnapshot{agent_environment_id: agent_environment_id} = snapshot)
       when is_integer(agent_environment_id) do
    since = DateTime.add(now(), -@popularity_window_hours, :hour)

    from(s in Sandbox,
      where:
        s.inserted_at >= ^since and s.state != :error and
          ((s.agent_environment_id == ^agent_environment_id and not is_nil(s.anthropic_session_id) and
              s.platform == ^snapshot.platform) or
             (s.account_id == ^snapshot.account_id and s.repository == ^snapshot.repository and
                s.template == ^snapshot.template)),
      select: {s.inserted_at, s.state, s.updated_at}
    )
    |> Repo.all()
    |> Enum.map(fn {started, state, updated} -> {started, if(state not in @live_states, do: updated)} end)
  end

  defp spawns(%DiskSnapshot{} = snapshot) do
    base =
      if snapshot.source_sandbox_id,
        do: Repo.one(from(s in Sandbox, where: s.id == ^snapshot.source_sandbox_id, select: s.amp_base_snapshot_id))

    ids = Enum.reject([snapshot.amp_snapshot_id, base], &is_nil/1)
    since = DateTime.add(now(), -@popularity_window_hours, :hour)

    query =
      from(s in Sandbox,
        where: s.account_id == ^snapshot.account_id and s.inserted_at >= ^since,
        select: {s.inserted_at, s.state, s.updated_at}
      )

    query =
      if snapshot.lineage_id,
        do: where(query, [s], s.amp_snapshot_lineage_id == ^snapshot.lineage_id or s.amp_base_snapshot_id in ^ids),
        else: where(query, [s], s.amp_base_snapshot_id in ^ids)

    query
    |> Repo.all()
    |> Enum.map(fn {started, state, updated} -> {started, if(state not in @live_states, do: updated)} end)
  end

  defp popular?(spawns), do: length(spawns) >= @popular_spawns

  # The most spawns that held memory at the same time. A span ending when
  # another starts does not overlap it.
  defp peak_concurrency(spawns) do
    spawns
    |> Enum.flat_map(fn
      {started, nil} -> [{started, 1}]
      {started, ended} -> [{started, 1}, {ended, -1}]
    end)
    |> Enum.sort_by(fn {at, delta} -> {DateTime.to_unix(at), delta} end)
    |> Enum.scan(0, fn {_at, delta}, open -> open + delta end)
    |> Enum.max(fn -> 0 end)
  end

  @doc """
  Copies a popular archived snapshot from its archive (`copy_disks`) onto
  the nodes that hold its lineage, one node at a time. Like a runner cache
  volume (`VolumePlacement`), a lineage is held by half again as many nodes
  as its Orbs ran on at once in the window, at least two, picked by weighted
  rendezvous hashing of the lineage over the ready nodes at the archive's
  site, weighted by disk budget. The snapshot's own node counts when it is
  among them, and a snapshot gets at most four copies however busy it is. A node that cannot take the copy, because its reserved disk
  would pass the archive high-water mark (so a copy never pushes an Orb into
  the archive; a Claude Code snapshot's copy only its whole budget), passes
  it to the next node in that order. The copy is
  reserved under the node's lock before the download, like a save. Answers
  `{:error, :no_capacity}` when fewer nodes than that hold it.
  """
  def copy(%DiskSnapshot{id: id}) do
    with %DiskSnapshot{} = snapshot <- Repo.get(DiskSnapshot, id),
         true <- copyable?(snapshot),
         spawns = spawns(snapshot),
         true <- popular?(spawns) do
      copy_to_holders(snapshot, peak_concurrency(spawns))
    else
      _skipped -> :ok
    end
  end

  defp copy_to_holders(snapshot, peak) do
    site = Archives.restore_site(snapshot)

    peers =
      snapshot
      |> copy_candidates()
      |> Enum.filter(&(is_nil(site) or Sites.shard_storage_site(&1.name) == site))
      |> Map.new(&{&1.name, &1})

    weights = placement_weights(peers)
    wanted = VolumePlacement.replicas(peak, map_size(weights))
    copies = Repo.all(from(c in DiskSnapshotCopy, where: c.disk_snapshot_id == ^snapshot.id, select: c.node_name))
    held = if snapshot.node_name, do: [snapshot.node_name | copies], else: copies

    snapshot
    |> placement_key()
    |> VolumePlacement.holders(weights, map_size(weights))
    |> Enum.reduce_while({0, @max_copies - length(copies)}, fn name, {holders, room} = acc ->
      cond do
        enough?(acc, wanted) -> {:halt, acc}
        name in held -> {:cont, {holders + 1, room}}
        true -> copy_to_node(snapshot, peers[name], acc)
      end
    end)
    |> case do
      {:error, reason} -> {:error, reason}
      acc -> if enough?(acc, wanted), do: :ok, else: {:error, :no_capacity}
    end
  end

  # A macOS snapshot only copies onto hosts running the image it was saved
  # from; a Linux one onto any node with its template.
  defp copy_candidates(%DiskSnapshot{platform: :darwin} = snapshot), do: MacosCapacity.snapshot_hosts(snapshot)
  defp copy_candidates(%DiskSnapshot{template: template}), do: Capacity.ready_nodes(template)

  defp reserve_copy(%DiskSnapshot{platform: :darwin} = snapshot, node, insert),
    do: MacosCapacity.reserve_snapshot_copy(node, snapshot, insert)

  defp reserve_copy(snapshot, node, insert),
    do: Capacity.reserve_disk_snapshot(node, snapshot, insert, budget_percent: copy_budget_percent(snapshot))

  # Enough nodes hold the lineage, or the snapshot has its most copies.
  defp enough?({holders, room}, wanted), do: holders >= wanted or room <= 0

  defp copy_to_node(snapshot, node, {holders, room} = acc) do
    insert = fn ->
      %DiskSnapshotCopy{}
      |> DiskSnapshotCopy.create_changeset(%{disk_snapshot_id: snapshot.id, node_name: node.name, last_used_at: now()})
      |> Repo.insert()
    end

    case reserve_copy(snapshot, node, insert) do
      {:ok, copy} ->
        case fill_copy(snapshot, copy) do
          {:ok, _copy} -> {:cont, {holders + 1, room - 1}}
          {:error, reason} -> {:halt, {:error, reason}}
        end

      {:error, _reason} ->
        {:cont, acc}
    end
  end

  # A Claude Code snapshot's copies may fill the node's whole disk budget, as
  # its sandboxes do: Linux nodes run at the archive high-water mark, which
  # would refuse every copy. Above the mark the disk-pressure sweep drops a
  # copy unused for an hour before it archives an Orb, and a node without
  # room for a sandbox drops a copy first (`Archives.make_node_room/2`).
  # Amp snapshots stay under the mark, so their copies never archive an Orb.
  defp copy_budget_percent(%DiskSnapshot{agent_environment_id: id}) when is_integer(id), do: 100
  defp copy_budget_percent(_snapshot), do: Environment.sandbox_archive_disk_high_water_percent() || 100

  # A Claude Code snapshot's copies are placed by its environment and
  # repository, which every rebuild keeps.
  defp placement_key(%DiskSnapshot{account_id: account_id, agent_environment_id: id, repository: repository})
       when is_integer(id), do: "#{account_id}/claude-code/#{id}/#{repository}"

  # A snapshot's copies are placed by its account and lineage. Snapshots
  # saved before lineages were recorded are their own lineage.
  defp placement_key(%DiskSnapshot{account_id: account_id} = snapshot),
    do: "#{account_id}/#{snapshot.lineage_id || snapshot.amp_snapshot_id}"

  # Nodes weigh their disk budget, as cache hosts weigh their cache capacity.
  # While any node has an unbounded budget, every node weighs the same.
  defp placement_weights(peers) do
    budgets = Map.new(peers, fn {name, node} -> {name, Capacity.disk_budget_bytes(node)} end)

    if Enum.all?(budgets, fn {_name, budget} -> is_integer(budget) end),
      do: budgets,
      else: Map.new(peers, fn {name, _node} -> {name, 1} end)
  end

  defp fill_copy(snapshot, %DiskSnapshotCopy{node_name: node_name} = copy) do
    args = %{snapshot_id: snapshot.id, template: snapshot.template, workspace_gb: snapshot.workspace_gb}
    # A macOS host admits the copy's measured bytes before downloading, and
    # clones the image the snapshot was saved from.
    args =
      if snapshot.platform == :darwin,
        do: Map.merge(args, %{bytes: snapshot.disk_bytes, template_tag: snapshot.template_tag}),
        else: args

    args = Nodes.command_args(node_name, args)

    with {:ok, source} <- Archives.restore_source(snapshot),
         {:ok, data} <- Nodes.call(node_name, "copy_disks", Map.put(args, :from_archive, source), timeout: @copy_timeout) do
      case Repo.update_all(from(c in DiskSnapshotCopy, where: c.id == ^copy.id),
             set: [state: :ready, last_used_at: now(), updated_at: now()]
           ) do
        {1, _} ->
          Logger.info("sandboxes: disk snapshot copied",
            disk_snapshot_id: snapshot.id,
            node: node_name,
            archive_bytes: snapshot.archive_bytes,
            duration_ms: data["duration_ms"]
          )

          {:ok, copy}

        # The snapshot was deleted while the copy downloaded.
        {0, _} ->
          delete_node_copy(snapshot.id, node_name)
          {:error, :deleted}
      end
    else
      {:error, reason} ->
        Logger.warning("sandboxes: copying a disk snapshot failed",
          disk_snapshot_id: snapshot.id,
          node: node_name,
          reason: inspect(reason)
        )

        # A download the node finishes anyway is removed at its next report.
        {:ok, _deleted} = Repo.delete(copy, allow_stale: true)
        {:error, reason}
    end
  end

  @doc """
  Frees disk on nodes that need room by dropping the least recently used
  ready copy on them: a copy is the cheapest thing to give up, since its
  snapshot stays on its own node and in its archive. The row goes at once,
  which is what frees the reservation; the node removes the files right
  after. Answers whether it dropped one. With `idle_only: true`, for the
  proactive disk-pressure sweep, only a copy unused for the last hour goes.
  """
  def drop_copy(node_names, opts \\ []) when is_list(node_names) do
    query =
      from(c in DiskSnapshotCopy,
        where: c.node_name in ^node_names and c.state == :ready,
        order_by: [asc: c.last_used_at],
        limit: 1
      )

    if_result =
      if(opts[:idle_only],
        do: where(query, [c], c.last_used_at < ^DateTime.add(now(), -@copy_pressure_idle_minutes, :minute)),
        else: query
      )

    if_result
    |> Repo.one()
    |> case do
      nil ->
        false

      copy ->
        Logger.info("sandboxes: dropping a disk snapshot copy to make room",
          disk_snapshot_id: copy.disk_snapshot_id,
          node: copy.node_name
        )

        {:ok, _deleted} = Repo.delete(copy, allow_stale: true)
        Tasks.run_async(fn -> delete_node_copy(copy.disk_snapshot_id, copy.node_name) end)
        true
    end
  end

  @doc """
  Gives up, on nodes that need room and hold no copy to drop, the node
  copy of their least recently used archived snapshot: its archive keeps
  it, so the next spawn from it boots from the archive or a copy, as a
  node that refuses the clone would make it anyway. The row loses its node
  at once, which frees the reservation; the node removes the files right
  after. Answers whether it dropped one. With `idle_only: true`, for the
  proactive disk-pressure sweep, only a snapshot unused for the last hour.
  """
  def drop_archived_node_copy(node_names, opts \\ []) when is_list(node_names) do
    query =
      from(s in DiskSnapshot,
        where: s.node_name in ^node_names and s.state == :ready and not is_nil(s.archived_at),
        order_by: [asc: s.last_used_at],
        limit: 1
      )

    query =
      if opts[:idle_only],
        do: where(query, [s], s.last_used_at < ^DateTime.add(now(), -@copy_pressure_idle_minutes, :minute)),
        else: query

    with %DiskSnapshot{id: id, node_name: node_name} <- Repo.one(query),
         {1, _} <-
           Repo.update_all(from(s in DiskSnapshot, where: s.id == ^id and s.node_name == ^node_name),
             set: [node_name: nil, updated_at: now()]
           ) do
      Logger.info("sandboxes: dropping an archived disk snapshot's node copy to make room",
        disk_snapshot_id: id,
        node: node_name
      )

      Tasks.run_async(fn -> delete_node_copy(id, node_name) end)
      true
    else
      _none -> false
    end
  end

  defp delete_copy(%DiskSnapshotCopy{} = copy) do
    delete_node_copy(copy.disk_snapshot_id, copy.node_name)
    Repo.delete(copy, allow_stale: true)
  end

  # Runs off the socket process, which has to deliver the answer.
  defp delete_orphan(node_name, snapshot_id) do
    Logger.warning("sandboxes: deleting a disk snapshot unknown to the server",
      disk_snapshot_id: snapshot_id,
      node: node_name
    )

    Tasks.run_async(fn ->
      case Nodes.call(node_name, "delete_disks", Nodes.command_args(node_name, %{snapshot_id: snapshot_id}), []) do
        {:ok, _data} ->
          :ok

        {:error, reason} ->
          Logger.warning("sandboxes: failed to delete an orphaned disk snapshot",
            disk_snapshot_id: snapshot_id,
            node: node_name,
            reason: inspect(reason)
          )
      end
    end)
  end

  # A macOS host runs only commands that name its current incarnation.
  # A build's builder is shut down cleanly instead of checkpointed
  # (`shutdown`): a Mac booted from disks a running guest only synced read a
  # compilation cache store that crashed `tuist-cas-proxy` on its first
  # writes (2026-11). Nothing resumes the builder, which the caller deletes
  # next. A host that predates the option evicts the builder as before.
  defp save_args(%Sandbox{platform: :darwin} = sandbox, snapshot, opts) do
    args = %{sandbox_id: sandbox.id, snapshot_id: snapshot.id, node_uid: sandbox.node_uid}
    if opts[:shutdown], do: Map.put(args, :shutdown, true), else: args
  end

  defp save_args(sandbox, snapshot, _opts), do: %{sandbox_id: sandbox.id, snapshot_id: snapshot.id}

  defp connected_node(node_name) do
    case Enum.find(Nodes.connected_nodes(), &(&1.name == node_name)) do
      nil -> {:error, :not_connected}
      node -> {:ok, node}
    end
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)
end
