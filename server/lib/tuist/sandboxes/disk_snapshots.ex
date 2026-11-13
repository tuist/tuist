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

  Snapshots unused for longer than Amp reuses one, Claude Code snapshots
  included, are deleted with their archive, and the node's reports
  reconcile copies the database no longer knows and rows whose copy the
  node lost.
  """
  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.AgentEnvironment
  alias Tuist.Sandboxes.Archives
  alias Tuist.Sandboxes.Capacity
  alias Tuist.Sandboxes.DiskSnapshot
  alias Tuist.Sandboxes.Nodes
  alias Tuist.Sandboxes.Sandbox
  alias Tuist.Sandboxes.Workers.BuildRepositorySnapshotWorker
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
  `setup_sha256`, for the environment's template and workspace size. Only a
  snapshot of a template tag a connected node creates new sandboxes with
  qualifies: the rootfs carries `sbx-worker`, so a snapshot of an older
  image would hold sessions back on it.
  """
  def find_ready_for_repository(%AgentEnvironment{} = agent_environment, repository, setup_sha256)
      when is_binary(repository) and is_binary(setup_sha256) do
    case current_template_tags(agent_environment.template) do
      [] ->
        nil

      tags ->
        Repo.one(
          from(s in DiskSnapshot,
            where: s.agent_environment_id == ^agent_environment.id and s.repository == ^repository,
            where: s.setup_sha256 == ^setup_sha256 and s.state == :ready,
            where: s.template == ^agent_environment.template and s.template_tag in ^tags,
            where: s.workspace_gb == ^agent_environment.workspace_gb,
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
  (`Tuist.Sandboxes.Workers.BuildRepositorySnapshotWorker`). Answers
  `{:error, :already_building}` while a build of the same key runs or for a
  while after one failed.
  """
  def start_build(%AgentEnvironment{} = agent_environment, repository, setup_sha256)
      when is_binary(repository) and is_binary(setup_sha256) do
    attrs = %{
      account_id: agent_environment.account_id,
      agent_environment_id: agent_environment.id,
      repository: repository,
      setup_sha256: setup_sha256,
      template: agent_environment.template,
      workspace_gb: agent_environment.workspace_gb,
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
  and ends the build.
  """
  def save_build(%DiskSnapshot{state: :building} = build, %Sandbox{state: :paused, node_name: node_name} = sandbox)
      when is_binary(node_name) do
    with {:ok, ready} <-
           do_save(sandbox, %{
             agent_environment_id: build.agent_environment_id,
             repository: build.repository,
             setup_sha256: build.setup_sha256
           }) do
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
      do_save(sandbox, %{amp_snapshot_id: amp_snapshot_id})
    end
  end

  def save(%Sandbox{state: state}, _amp_snapshot_id), do: {:error, {:invalid_state, state}}

  defp do_save(%Sandbox{node_name: node_name} = sandbox, key) do
    attrs = %{
      account_id: sandbox.account_id,
      source_sandbox_id: sandbox.id,
      node_name: node_name,
      template: sandbox.template,
      template_tag: sandbox.template_tag,
      workspace_gb: sandbox.workspace_gb,
      last_used_at: now()
    }

    attrs = Map.merge(attrs, key)

    with {:ok, node} <- connected_node(node_name),
         {:ok, snapshot} <-
           Capacity.reserve_disk_snapshot(node, attrs, fn ->
             %DiskSnapshot{} |> DiskSnapshot.create_changeset(attrs) |> Repo.insert()
           end) do
      case Nodes.call(node_name, "save_disks", %{sandbox_id: sandbox.id, snapshot_id: snapshot.id},
             timeout: @save_timeout
           ) do
        {:ok, data} ->
          {:ok, ready} = snapshot |> DiskSnapshot.update_changeset(%{state: :ready, last_used_at: now()}) |> Repo.update()

          Logger.info("sandboxes: disk snapshot saved",
            disk_snapshot_id: ready.id,
            sandbox_id: sandbox.id,
            node: node_name,
            duration_ms: data["duration_ms"]
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

  # A Claude Code environment keeps one snapshot per repository: the newest
  # save replaces the older ready ones, whichever setup script they ran.
  # Builds of the repository are left to finish.
  #
  # Amp refreshes a project snapshot under a new identifier: it spawns an
  # Orb from the current one and has it save the next. Once that save is
  # ready Amp boots new Orbs from it, so copies of the identifier the Orb
  # was spawned from are superseded too, not only older saves of this one.
  defp delete_superseded(%DiskSnapshot{agent_environment_id: agent_environment_id} = snapshot, _sandbox)
       when is_integer(agent_environment_id) do
    from(s in DiskSnapshot,
      where:
        s.agent_environment_id == ^agent_environment_id and s.repository == ^snapshot.repository and
          s.state == :ready and s.id != ^snapshot.id and s.inserted_at <= ^snapshot.inserted_at
    )
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
  def touch(%DiskSnapshot{id: id}) do
    Repo.update_all(from(s in DiskSnapshot, where: s.id == ^id), set: [last_used_at: now()])
    :ok
  end

  @doc """
  Forgets the node copy when the node answered that it no longer holds it:
  an archived snapshot keeps its row without a node, any other is dropped.
  """
  def forget_if_missing(%DiskSnapshot{} = snapshot, reason) when is_binary(reason) do
    cond do
      not String.contains?(reason, "disk snapshot not found") -> :ok
      snapshot.archived_at -> forget_node_copy(snapshot)
      true -> delete(snapshot)
    end

    :ok
  end

  def forget_if_missing(_snapshot, _reason), do: :ok

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
    if snapshot.node_name, do: delete_node_copy(snapshot)

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

  defp delete_node_copy(%DiskSnapshot{} = snapshot) do
    case Nodes.call(snapshot.node_name, "delete_disks", %{snapshot_id: snapshot.id}, []) do
      {:ok, _data} ->
        :ok

      {:error, reason} ->
        Logger.warning("sandboxes: failed to delete a disk snapshot on its node",
          disk_snapshot_id: snapshot.id,
          node: snapshot.node_name,
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
    known =
      Repo.all(from(s in DiskSnapshot, where: s.id in ^reported_ids and s.node_name == ^node_name, select: s.id))

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

    :ok
  end

  def reconcile_node_report(_node_name, _report), do: :ok

  # Runs off the socket process, which has to deliver the answer.
  defp delete_orphan(node_name, snapshot_id) do
    Logger.warning("sandboxes: deleting a disk snapshot unknown to the server",
      disk_snapshot_id: snapshot_id,
      node: node_name
    )

    Tasks.run_async(fn ->
      case Nodes.call(node_name, "delete_disks", %{snapshot_id: snapshot_id}, []) do
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

  defp connected_node(node_name) do
    case Enum.find(Nodes.connected_nodes(), &(&1.name == node_name)) do
      nil -> {:error, :not_connected}
      node -> {:ok, node}
    end
  end

  defp now, do: DateTime.truncate(DateTime.utc_now(), :second)
end
