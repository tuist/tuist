defmodule Tuist.Runners.CacheVolumes.Builtin do
  @moduledoc false
  import Ecto.Query

  alias Tuist.Repo
  alias Tuist.Runners.CacheVolumes.Measurement
  alias Tuist.Runners.CacheVolumes.Usage
  alias Tuist.Runners.CacheVolumes.Volume
  alias Tuist.Runners.RunnerSession
  alias Tuist.Runners.VolumeHeads
  alias Tuist.Runners.WorkflowJob

  # Only the authenticated host calls this after finalizing its private branch.
  # The durable execution binding supplies account, repository and job identity.
  def report(node, %{"pod_name" => pod, "pod_uid" => uid, "volume_name" => name} = params) do
    with true <- is_binary(uid) and byte_size(uid) in 1..128,
         true <- VolumeHeads.valid_volume_name?(name),
         {session, job} <- execution(node, pod),
         true <- name in [VolumeHeads.reserved_tuist_cache(), VolumeHeads.volume_name_for_repository(job.repository)],
         true <- is_binary(params["attached_at"]),
         {:ok, attached, _} <- DateTime.from_iso8601(params["attached_at"] || ""),
         true <- DateTime.diff(attached, session.started_at) >= -300,
         true <- DateTime.diff(DateTime.utc_now(), attached) >= -300,
         true <- valid_measurements?(params) do
      attached = DateTime.from_unix!(DateTime.to_unix(attached, :microsecond), :microsecond)
      record(job, node, pod, uid, name, attached, params)
    else
      nil -> {:error, :pending}
      _ -> {:error, :invalid_report}
    end
  end

  def report(_, _), do: {:error, :invalid_report}

  defp execution(node, pod) when is_binary(pod) do
    Repo.one(
      from(s in RunnerSession,
        join: j in WorkflowJob,
        on: j.workflow_job_id == s.executed_workflow_job_id and j.account_id == s.account_id,
        where: s.node_name == ^node and s.pod_name == ^pod and s.platform == :macos,
        order_by: [desc: s.started_at],
        limit: 1,
        select: {s, j}
      )
    )
  end

  defp execution(_, _), do: nil

  defp valid_measurements?(params) do
    counters = ~w(size_bytes capacity_bytes attached_size_bytes attach_ms generation base_generation)

    Enum.all?(counters, &valid_counter?(params[&1])) and valid_sizes?(params) and
      is_boolean(params["warm"]) and params["outcome"] in ["promoted", "discarded"]
  end

  defp valid_counter?(value), do: is_integer(value) and value >= 0 and value <= 9_000_000_000_000_000

  defp valid_sizes?(params) do
    params["capacity_bytes"] > 0 and params["size_bytes"] <= params["capacity_bytes"] and
      params["attached_size_bytes"] <= params["capacity_bytes"]
  end

  defp record(job, node, pod, uid, name, attached, params) do
    Repo.transaction(fn ->
      now = DateTime.utc_now()
      volume = upsert_volume(job, name, now)

      case Repo.get_by(Usage, volume_id: volume.id, generation: 1, pod_uid: uid) do
        nil -> record_usage(volume, job, node, pod, uid, attached, params, now)
        %{workflow_job_id: job_id} when job_id == job.workflow_job_id -> :ok
        _ -> Repo.rollback(:invalid_report)
      end

      %{id: volume.id}
    end)
  end

  defp upsert_volume(job, name, now) do
    timestamp = DateTime.truncate(now, :second)

    Repo.insert_all(
      Volume,
      [
        %{
          id: Ecto.UUID.generate(),
          account_id: job.account_id,
          builtin_name: name,
          provider: job.provider,
          provider_instance: "tuist-runner",
          scope_id: name,
          repository: if(name == VolumeHeads.reserved_tuist_cache(), do: "—", else: job.repository),
          repository_id: 0,
          key: "tuist-cache",
          platform: "macos",
          architecture: "arm64",
          uid: 501,
          inserted_at: timestamp,
          updated_at: timestamp
        }
      ],
      on_conflict: :nothing,
      conflict_target: [:account_id, :builtin_name]
    )

    Repo.one!(from(v in Volume, where: v.account_id == ^job.account_id and v.builtin_name == ^name, lock: "FOR UPDATE"))
  end

  defp record_usage(volume, job, node, pod, uid, attached, params, now) do
    projection = projection(volume, params)

    usage =
      Repo.insert!(%Usage{
        volume_id: volume.id,
        generation: 1,
        pod_name: pod,
        pod_uid: uid,
        node_name: node,
        workflow_job_id: job.workflow_job_id,
        workflow_run_id: job.workflow_run_id,
        can_publish: false,
        status: if(params["outcome"] == "promoted", do: "published", else: "discarded"),
        warm: params["warm"],
        size_bytes: projection.size,
        capacity_bytes: params["capacity_bytes"],
        attach_ms: params["attach_ms"],
        attached_at: attached,
        finished_at: now,
        last_reported_at: now,
        deleted_at: if(projection.deleted, do: now),
        superseded_at: if(projection.retired, do: now),
        published_generation: projection.generation,
        inserted_at: DateTime.truncate(attached, :second)
      })

    measure(usage, params["attached_size_bytes"], attached, false)
    measure(usage, usage.size_bytes, now, projection.deleted, projection.retired)

    if projection.retained, do: retire_previous(volume, usage, now)

    Repo.update!(
      Ecto.Changeset.change(volume,
        head_id: if(projection.retained, do: usage.id, else: volume.head_id),
        last_used_at: latest(volume.last_used_at, attached)
      )
    )
  end

  defp projection(volume, params) do
    head = VolumeHeads.get_head(volume.account_id, volume.builtin_name)
    promoted = params["outcome"] == "promoted" and head_generation?(head, params["generation"])
    inherited = params["warm"] and head_generation?(head, params["base_generation"]) and is_nil(volume.head_id)
    values = projection_values(params, inherited and not promoted)
    Map.merge(values, retention(promoted or inherited, params["outcome"]))
  end

  defp retention(true, _), do: %{retained: true, retired: false, deleted: false}
  defp retention(false, "promoted"), do: %{retained: false, retired: true, deleted: false}
  defp retention(false, _), do: %{retained: false, retired: false, deleted: true}

  defp head_generation?(nil, _), do: false
  defp head_generation?(head, generation), do: head.generation == generation

  defp projection_values(params, true), do: %{size: params["attached_size_bytes"], generation: params["base_generation"]}
  defp projection_values(params, false), do: %{size: params["size_bytes"], generation: params["generation"]}

  defp retire_previous(volume, usage, now) do
    # This projection tracks the canonical saved image. Superseding its
    # measurement is not an acknowledgement of host/S3 physical deletion.
    {_, previous} =
      Repo.update_all(
        from(u in Usage,
          where: u.volume_id == ^volume.id and u.id != ^usage.id and is_nil(u.deleted_at) and is_nil(u.superseded_at),
          select: %{id: u.id, size_bytes: u.size_bytes, capacity_bytes: u.capacity_bytes}
        ),
        set: [superseded_at: now]
      )

    Repo.insert_all(
      Measurement,
      Enum.map(previous, fn previous ->
        %{
          usage_id: previous.id,
          size_bytes: previous.size_bytes,
          capacity_bytes: previous.capacity_bytes,
          observed_at: now,
          deleted: false,
          retired: true
        }
      end)
    )
  end

  defp latest(nil, at), do: at
  defp latest(a, b), do: if(DateTime.before?(a, b), do: b, else: a)

  defp measure(usage, size, at, deleted, retired \\ false) do
    Repo.insert!(%Measurement{
      usage_id: usage.id,
      size_bytes: size,
      capacity_bytes: usage.capacity_bytes,
      observed_at: at,
      deleted: deleted,
      retired: retired
    })
  end
end
