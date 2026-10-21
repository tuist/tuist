defmodule Tuist.Runners.CacheVolumes do
  @moduledoc """
  Account-owned snapshot volumes and their job history. Only the trusted storage
  agent calls allocate/report. Workflow identity comes from the proven execution
  binding, never from workflow-supplied repository or branch names.

  Deletion advances a generation under the same row lock as publication. Existing
  clones remain usable, but cannot resurrect the deleted generation. Physical
  reclamation is acknowledged separately from logical invalidation.
  """
  import Ecto.Query

  alias Tuist.Accounts.Account
  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.Repo
  alias Tuist.Runners
  alias Tuist.Runners.CacheVolumes.Identity
  alias Tuist.Runners.CacheVolumes.Measurement
  alias Tuist.Runners.CacheVolumes.Usage
  alias Tuist.Runners.CacheVolumes.Volume
  alias Tuist.Runners.JobCompletion
  alias Tuist.Runners.Profile
  alias Tuist.Runners.Profiles
  alias Tuist.Runners.RunnerSession
  alias Tuist.Runners.VolumeHeads
  alias Tuist.Runners.Workers.ExecutionLookupWorker
  alias Tuist.Runners.WorkflowJob
  alias Tuist.VCS

  @retention_seconds 7 * 24 * 60 * 60
  @checkout_key "checkout"

  # A saved snapshot at or above @full_percent of its capacity, which a clone filled
  # to @out_of_space_percent, is not cloned again: the next use starts a fresh lineage.
  @full_percent 80
  @out_of_space_percent 99

  @volume_bytes 20_000_000_000
  # Tuist sizes its managed volumes and ignores requested sizes for them.
  @managed_volume_bytes %{"tuist-xcode" => 30_000_000_000, "tuist-module" => 20_000_000_000}
  # The largest volume a host that does not advertise its maximum accepts.
  @legacy_max_volume_bytes 32_000_000_000
  @default_key "tuist-default"

  def allocate(
        %{
          "pod_name" => pod,
          "pod_uid" => uid,
          "node_name" => node,
          "key" => key,
          "architecture" => arch,
          "uid" => user_id
        } = params
      ) do
    with true <- valid_key?(key) and key != @checkout_key,
         true <- arch in ["amd64", "arm64"],
         true <- is_integer(user_id) and user_id >= 0 and user_id <= 2_147_483_647,
         true <- is_binary(uid) and Regex.match?(~r/^[a-zA-Z0-9-]{1,128}$/, uid),
         {:ok, job, platform} <- executing_job(pod, node),
         {:ok, identity} <- Identity.resolve(job) do
      allocate_for_job(job, identity, %{
        pod_name: pod,
        pod_uid: uid,
        node_name: node,
        key: key,
        architecture: arch,
        platform: to_string(platform),
        uid: user_id,
        requested_volume_bytes: params["requested_volume_bytes"],
        max_volume_bytes: params["max_volume_bytes"]
      })
    else
      {:error, :pending} ->
        {:error, :pending}

      _ ->
        {:error, :unavailable}
    end
  end

  def allocate(_), do: {:error, :unavailable}

  def valid_key?(key), do: is_binary(key) and Regex.match?(~r/^[a-zA-Z0-9][a-zA-Z0-9_.\/-]{0,199}$/, key)

  @doc "The reserved name of a repository's checkout volume, which no job can request."
  def checkout_key, do: @checkout_key

  @doc """
  Allocates the checkout volume of the GitHub repository the pod is running a job
  for. The host builds its master from what jobs export and verifies it, so a
  job's own branch never publishes; the host publishes the master instead. Besides
  the identity and the volume's HEAD, the result carries the clone URL, the
  default branch, the job's commit and whether the job ran on the default branch.
  """
  def allocate_checkout(%{
        "pod_name" => pod,
        "pod_uid" => uid,
        "node_name" => node,
        "architecture" => arch,
        "uid" => user_id
      }) do
    with true <- arch in ["amd64", "arm64"],
         true <- is_integer(user_id) and user_id >= 0 and user_id <= 2_147_483_647,
         true <- is_binary(uid) and Regex.match?(~r/^[a-zA-Z0-9-]{1,128}$/, uid),
         {:ok, %WorkflowJob{provider: "github"} = job, platform} <- executing_job(pod, node),
         true <- profile_cached_checkouts?(job),
         {:ok, installation} <- VCS.get_github_app_installation_for_account(job.account_id),
         true <- VCS.installation_api_url(installation) == "https://api.github.com",
         {:ok, identity} <- Identity.resolve(job),
         {:ok, allocation} <-
           allocate_for_job(job, identity, %{
             pod_name: pod,
             pod_uid: uid,
             node_name: node,
             key: @checkout_key,
             architecture: arch,
             platform: to_string(platform),
             uid: user_id
           }) do
      usage = Repo.get!(Usage, allocation.id)

      {:ok,
       Map.merge(allocation, %{
         generation: usage.generation,
         repository: job.repository,
         clone_url: "https://github.com/" <> job.repository,
         default_branch: identity.default_branch,
         commit: job.head_sha,
         # A pull request from a branch or fork named like the default branch is not one.
         default_branch_job: identity.trusted,
         # Stable across clears, so a host can drop the copies of a cleared generation.
         volume_key: :sha256 |> :crypto.hash(usage.volume_id) |> Base.encode16(case: :lower)
       })}
    else
      {:error, :pending} -> {:error, :pending}
      _ -> {:error, :unavailable}
    end
  end

  def allocate_checkout(_), do: {:error, :unavailable}

  # A job follows its profile's setting; one on a legacy label has checkouts on.
  defp profile_cached_checkouts?(job) do
    case Profiles.get_for_dispatch_label(job.account_id, job.requested_dispatch_label) do
      %Profile{cached_checkouts: enabled} -> enabled
      nil -> true
    end
  end

  # The session's executed binding is the proof that this runner runs the job.
  # The job row can still be `queued` or `claimed` by another Pod until the
  # unstarted-executions sweep moves it, or not exist until its `queued`
  # webhook arrives.
  defp executing_job(pod, node) do
    case execution_binding(pod, node) do
      {job, %RunnerSession{platform: platform} = session} ->
        if Environment.runner_cache_volumes_enabled?(platform) do
          case job do
            %WorkflowJob{status: status} = job when status in ~w(queued claimed running) ->
              {:ok, job, platform}

            nil ->
              await_execution(session)

            _ ->
              {:error, :unavailable}
          end
        else
          {:error, :unavailable}
        end

      _ ->
        {:error, :unavailable}
    end
  end

  # Without a binding, ask GitHub directly rather than wait for an
  # `in_progress` delivery that can lag the job's start by minutes.
  defp await_execution(%RunnerSession{executed_workflow_job_id: nil} = session) do
    {:ok, _job} = ExecutionLookupWorker.enqueue(session)
    {:error, :pending}
  end

  defp await_execution(%RunnerSession{}), do: {:error, :pending}

  defp execution_binding(pod, node) do
    Repo.one(
      from(s in RunnerSession,
        left_join: j in WorkflowJob,
        on:
          j.workflow_job_id == s.executed_workflow_job_id and j.account_id == s.account_id and
            j.provider in ["github", "buildkite", "gitlab"],
        where: s.pod_name == ^pod and s.node_name == ^node and is_nil(s.ended_at) and s.platform in [:linux, :macos],
        order_by: [desc: s.started_at],
        limit: 1,
        select: {j, s}
      )
    )
  end

  defdelegate run_identity(job, run), to: Identity, as: :github_identity

  # Also used by lifecycle tests with already verified provider metadata.
  def allocate_for_job(job, identity, attrs) do
    identity = Identity.storage_scope(identity)
    attrs = Map.put_new(attrs, :platform, "linux")

    Repo.transaction(fn ->
      # One admission lock per pod also bounds concurrent requests for new keys.
      Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
        "cache-volume:#{job.account_id}:#{attrs.pod_uid}"
      ])

      # Lock the profile before the volume, in the same order as policy changes,
      # so their revocation sees every use granted under the previous policy.
      profile = writer_profile(job)

      # A job's own checkout branch never publishes: the host publishes the master
      # it builds from verified exports instead (`image/3`).
      grant = if attrs.key == @checkout_key, do: :denied, else: writer_grant(identity, profile)
      attrs = %{attrs | key: volume_key(attrs.key, profile)}
      ensure_job_capacity!(job, identity, attrs)
      now = DateTime.utc_now()
      timestamp = DateTime.truncate(now, :second)
      fields = Map.take(attrs, [:key, :platform, :architecture, :uid])

      row =
        Map.merge(fields, %{
          id: Ecto.UUID.generate(),
          account_id: job.account_id,
          repository_id: identity.repository_id,
          provider: identity.provider,
          provider_instance: identity.provider_instance,
          scope_id: identity.scope_id,
          repository: job.repository,
          default_branch: Map.get(identity, :default_branch),
          inserted_at: timestamp,
          updated_at: timestamp
        })

      Repo.insert_all(Volume, [row],
        on_conflict: :nothing,
        conflict_target: [:account_id, :provider, :provider_instance, :scope_id, :key, :platform, :architecture, :uid]
      )

      volume =
        Repo.one!(from(v in volume_query(job, identity, attrs), lock: "FOR UPDATE"))

      volume = expire_locked(volume, now)
      requested = requested_volume_bytes(job, attrs)
      {volume, saved_head, volume_bytes} = size_locked(volume, requested, max_volume_bytes(attrs))

      head = VolumeHeads.get_head(volume.account_id, storage_name(volume))

      use_attrs =
        attrs
        |> Map.take([:pod_name, :pod_uid, :node_name])
        |> Map.merge(%{
          id: Ecto.UUID.generate(),
          volume_id: volume.id,
          generation: volume.generation,
          parent_id: volume.head_id,
          base_generation: (head && head.generation) || 0,
          image_digest: head && head.tree_digest,
          content_digest: head && head.content_digest,
          workflow_job_id: job.workflow_job_id,
          workflow_run_id: job.workflow_run_id,
          volume_bytes: volume_bytes,
          inserted_at: timestamp,
          updated_at: timestamp
        })
        |> Map.merge(writer_fields(identity, grant))

      Repo.insert_all(Usage, [use_attrs],
        on_conflict: :nothing,
        conflict_target: [:volume_id, :generation, :pod_uid]
      )

      usage = Repo.get_by!(Usage, volume_id: volume.id, generation: volume.generation, pod_uid: attrs.pod_uid)

      ensure_allocation_matches!(usage, job, attrs)

      Repo.update!(
        Ecto.Changeset.change(volume,
          last_used_at: if(volume.deleted_at, do: nil, else: volume.last_used_at),
          deleted_at: nil,
          repository: job.repository,
          default_branch: Map.get(identity, :default_branch, volume.default_branch),
          requested_volume_bytes: saved_request(volume, usage, requested)
        )
      )

      %{
        id: usage.id,
        account_id: volume.account_id,
        scope: scope(volume),
        parent_id: usage.parent_id,
        base_generation: usage.base_generation,
        image_digest: usage.image_digest,
        content_digest: usage.content_digest,
        can_publish: usage.can_publish,
        uid: volume.uid,
        volume_bytes: usage.volume_bytes || volume_bytes,
        head_size_bytes: saved_head && saved_head.size_bytes
      }
    end)
  end

  # Picks the capacity of the job's copy. It grows within a lineage and shrinks
  # only when the volume starts empty. A saved head that would be nearly full at
  # that capacity, and whose clone filled its own, is cleared first. A capacity
  # above what the host holds allocates nothing.
  defp size_locked(volume, requested, max_volume_bytes) do
    saved_head = volume.head_id && Repo.get(Usage, volume.head_id)
    volume_bytes = allocation_volume_bytes(volume, saved_head, requested)

    reset? =
      not is_nil(saved_head) and full?(saved_head.size_bytes, volume_bytes) and clone_ran_out_of_space?(saved_head.id)

    {saved_head, volume_bytes} =
      if reset?,
        do: {nil, allocation_volume_bytes(%{volume | head_id: nil}, nil, requested)},
        else: {saved_head, volume_bytes}

    if volume_bytes > max_volume_bytes, do: Repo.rollback(:capacity)

    if reset? do
      Runners.clear_volume_master(volume.account_id, storage_name(volume))
      {Repo.update!(Ecto.Changeset.change(volume, generation: volume.generation + 1, head_id: nil)), nil, volume_bytes}
    else
      {volume, saved_head, volume_bytes}
    end
  end

  defp allocation_volume_bytes(%{key: key, head_id: nil}, _saved_head, requested),
    do: Map.get(@managed_volume_bytes, key) || requested || @volume_bytes

  defp allocation_volume_bytes(%{key: key}, saved_head, requested),
    do: Map.get(@managed_volume_bytes, key) || max(saved_volume_bytes(key, saved_head), requested || 0)

  # Managed volumes size themselves. Sizes above the default need the account's
  # flag; larger requests are capped to the default.
  defp requested_volume_bytes(job, attrs) do
    requested = Map.get(attrs, :requested_volume_bytes)

    cond do
      Map.has_key?(@managed_volume_bytes, attrs.key) or not valid_requested_volume_bytes?(requested) ->
        nil

      requested > @volume_bytes and
          not FeatureFlags.runner_custom_volume_sizes_enabled?(%Account{id: job.account_id}) ->
        @volume_bytes

      true ->
        requested
    end
  end

  # Only a use that may publish records its request, so pull requests leave the
  # volume's size unchanged.
  defp saved_request(_volume, %Usage{can_publish: true}, requested) when is_integer(requested), do: requested
  defp saved_request(volume, _usage, _requested), do: volume.requested_volume_bytes

  defp valid_requested_volume_bytes?(bytes),
    do: is_integer(bytes) and rem(bytes, 1_000_000_000) == 0 and bytes >= 1_000_000_000 and bytes <= 100_000_000_000

  defp max_volume_bytes(attrs) do
    case Map.get(attrs, :max_volume_bytes) do
      bytes when is_integer(bytes) and bytes > 0 -> bytes
      _ -> @legacy_max_volume_bytes
    end
  end

  # Without a key, a job attaches the default volume of its runner profile. A job
  # without a profile has none and must name a key.
  defp volume_key(@default_key, %Profile{id: id}), do: "#{@default_key}/#{id}"
  defp volume_key(@default_key, nil), do: Repo.rollback(:unavailable)
  defp volume_key(key, _profile), do: key

  defp ensure_allocation_matches!(usage, job, attrs) do
    if usage.node_name != attrs.node_name or usage.workflow_job_id != job.workflow_job_id do
      Repo.rollback(:unavailable)
    end
  end

  # The job's runner profile decides which branches save. Without a profile, a
  # new profile's policy applies.
  defp writer_grant(identity, %Profile{} = profile) do
    if writer_allowed?(profile, identity.trusted, Map.get(identity, :writer_branch)),
      do: {:ok, profile.id},
      else: :denied
  end

  defp writer_grant(identity, nil) do
    if writer_allowed?(%Profile{}, identity.trusted, Map.get(identity, :writer_branch)),
      do: {:ok, nil},
      else: :denied
  end

  defp writer_fields(identity, grant) do
    %{
      writer_branch: Map.get(identity, :writer_branch),
      writer_default_branch: identity.trusted,
      writer_profile_id:
        case grant do
          {:ok, id} -> id
          _ -> nil
        end,
      can_publish: grant != :denied
    }
  end

  defp writer_profile(job), do: Profiles.lock_for_dispatch_label(job.account_id, Map.get(job, :requested_dispatch_label))

  @doc """
  Revokes pending saves granted under a runner profile's previous policy that
  its current policy no longer allows. A deleted profile falls back to a new
  profile's policy. Call inside the transaction that updated or deleted the
  profile row, after the row was written. Additions only affect new attachments.
  """
  def revoke_profile_writers({:deleted, %Profile{} = profile}) do
    default = %Profile{}

    revoke_profile_writers(%{
      profile
      | cache_writer_all_branches: default.cache_writer_all_branches,
        cache_writer_default_branch: default.cache_writer_default_branch,
        cache_writer_branches: default.cache_writer_branches
    })
  end

  def revoke_profile_writers(%Profile{id: id} = profile) do
    revoked =
      from(u in Usage,
        where: u.writer_profile_id == ^id and u.can_publish and u.status not in ["published", "discarded"]
      )
      |> Repo.all()
      |> Enum.reject(&writer_allowed?(profile, &1.writer_default_branch, &1.writer_branch))
      |> Enum.map(& &1.id)
      |> Enum.concat(unrecorded_profile_writers(profile))

    if revoked != [] do
      # Publication reads can_publish under the volume lock.
      Repo.all(
        from(v in Volume,
          where: v.id in subquery(from(u in Usage, where: u.id in ^revoked, select: u.volume_id)),
          order_by: v.id,
          lock: "FOR UPDATE",
          select: v.id
        )
      )

      Repo.update_all(
        from(u in Usage, where: u.id in ^revoked and u.status not in ["published", "discarded"]),
        set: [can_publish: false]
      )
    end

    :ok
  end

  # Uses allocated before uses recorded their profile, including by older pods
  # during a rollout, were default-branch grants without a recorded branch.
  defp unrecorded_profile_writers(%Profile{cache_writer_all_branches: true}), do: []
  defp unrecorded_profile_writers(%Profile{cache_writer_default_branch: true}), do: []

  defp unrecorded_profile_writers(%Profile{account_id: account_id} = profile) do
    label = Profile.dispatch_label(profile)

    Repo.all(
      from(u in Usage,
        join: v in Volume,
        on: v.id == u.volume_id,
        join: j in WorkflowJob,
        on: j.workflow_job_id == u.workflow_job_id and j.account_id == v.account_id,
        where:
          is_nil(u.writer_profile_id) and u.can_publish and u.status not in ["published", "discarded"] and
            v.account_id == ^account_id and is_nil(v.builtin_name) and
            j.requested_dispatch_label == ^label,
        select: u.id
      )
    )
  end

  # Only same-repository jobs of qualifying events have a writer branch, so
  # forks and pull_request_target never save. Uses recorded before writer
  # branches were recorded only carry the default-branch flag.
  defp writer_allowed?(%Profile{cache_writer_all_branches: true}, default_branch?, branch),
    do: default_branch? or is_binary(branch)

  defp writer_allowed?(%Profile{} = profile, default_branch?, branch) do
    (default_branch? and profile.cache_writer_default_branch) or
      Profile.cache_writer_branch?(profile.cache_writer_branches || [], branch)
  end

  defp ensure_job_capacity!(job, identity, attrs) do
    count =
      Repo.aggregate(
        from(u in Usage,
          join: v in Volume,
          on: v.id == u.volume_id,
          where: v.account_id == ^job.account_id and u.pod_uid == ^attrs.pod_uid and is_nil(v.builtin_name)
        ),
        :count
      )

    if count >= 8 and not existing_allocation?(job, identity, attrs), do: Repo.rollback(:volume_limit)
  end

  defp volume_query(job, identity, attrs) do
    from(v in Volume,
      where: is_nil(v.builtin_name),
      where:
        v.account_id == ^job.account_id and v.provider == ^identity.provider and
          v.provider_instance == ^identity.provider_instance and v.scope_id == ^identity.scope_id and
          v.key == ^attrs.key and v.platform == ^attrs.platform and v.architecture == ^attrs.architecture and
          v.uid == ^attrs.uid
    )
  end

  defp existing_allocation?(job, identity, attrs) do
    Repo.exists?(
      from(v in volume_query(job, identity, attrs),
        join: u in Usage,
        on: v.id == u.volume_id,
        where: u.pod_uid == ^attrs.pod_uid and u.generation == v.generation
      )
    )
  end

  # Cross-account maintenance. The same row lock guards mounts, expiration and
  # publication, so a sweep cannot evict a volume using a stale last-use value.
  def expire_inactive(now \\ DateTime.utc_now()) do
    threshold = DateTime.add(now, -@retention_seconds)

    Repo.transaction(fn ->
      volumes =
        Repo.all(
          from(v in Volume,
            where: is_nil(v.builtin_name) and is_nil(v.deleted_at) and v.last_used_at <= ^threshold,
            order_by: [asc: v.last_used_at, asc: v.id],
            limit: 500,
            lock: "FOR UPDATE SKIP LOCKED"
          )
        )

      Enum.each(volumes, &expire_locked(&1, now))
      length(volumes)
    end)
  end

  defp expire_locked(volume, now) do
    if is_nil(volume.deleted_at) and not is_nil(volume.last_used_at) and
         DateTime.compare(volume.last_used_at, DateTime.add(now, -@retention_seconds)) != :gt do
      Runners.clear_volume_master(volume.account_id, storage_name(volume))

      Repo.update!(
        Ecto.Changeset.change(volume,
          generation: volume.generation + 1,
          head_id: nil,
          deleted_at: now
        )
      )
    else
      volume
    end
  end

  def full?(size, capacity) when is_integer(size) and is_integer(capacity) and capacity > 0,
    do: size * 100 >= capacity * @full_percent

  def full?(_size, _capacity), do: false

  def out_of_space?(size, capacity) when is_integer(size) and is_integer(capacity) and capacity > 0,
    do: size * 100 >= capacity * @out_of_space_percent

  def out_of_space?(_size, _capacity), do: false

  defp clone_ran_out_of_space?(head_id) do
    Repo.exists?(
      from(u in Usage,
        where:
          u.parent_id == ^head_id and u.capacity_bytes > 0 and
            u.size_bytes * 100 >= u.capacity_bytes * @out_of_space_percent
      )
    )
  end

  @doc """
  Whether a use mounted an older saved generation because its base was not on
  its runner host.
  """
  def older_copy?(%Usage{mounted_generation: mounted, base_generation: base}),
    do: is_integer(mounted) and is_integer(base) and mounted < base

  def scope(volume) do
    :sha256 |> :crypto.hash("#{volume.id}:#{volume.generation}") |> Base.encode16(case: :lower)
  end

  # Internal cross-tenant agent protocol. A node can report only leases allocated
  # to it. Row locking serializes publication and deletion.
  def report(node, id, params) when is_binary(node) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Usage{} = usage <- Repo.get_by(Usage, id: id, node_name: node) do
      Repo.transaction(fn ->
        volume = Repo.one!(from(v in Volume, where: v.id == ^usage.volume_id, lock: "FOR UPDATE"))
        if volume.builtin_name, do: Repo.rollback(:unsupported)
        usage = Repo.get_by!(Usage, id: id, node_name: node)
        report_locked(volume, usage, params)
      end)
    else
      _ -> {:error, :not_found}
    end
  end

  def report(_, _, _), do: {:error, :not_found}

  defp report_locked(volume, usage, %{"state" => "deleted"}) do
    now = DateTime.utc_now()

    if is_nil(usage.deleted_at), do: record_measurement(usage, %{size_bytes: 0, capacity_bytes: 0}, now, true)

    Repo.update!(
      Ecto.Changeset.change(usage,
        last_reported_at: now,
        deleted_at: usage.deleted_at || now,
        finished_at: usage.finished_at || now,
        status: if(usage.status == "published", do: "published", else: "discarded")
      )
    )

    if volume.head_id == usage.id, do: Repo.update!(Ecto.Changeset.change(volume, head_id: nil))
    %{action: "forget"}
  end

  defp report_locked(volume, usage, params) do
    now = DateTime.utc_now()
    metrics = report_metrics!(params)

    if usage.deleted_at, do: Repo.rollback(:deleted)

    volume = expire_locked(volume, now)
    valid = volume.generation == usage.generation and is_nil(volume.deleted_at)

    if valid and is_nil(usage.attached_at) do
      Repo.update!(Ecto.Changeset.change(volume, last_used_at: now))
    end

    usage = update_reported_usage(usage, params, metrics, now)
    report_action(volume, usage, params, valid, now)
  end

  defp report_metrics!(params) do
    if params["state"] not in ["active", "sealed"], do: Repo.rollback(:invalid_report)
    if not (is_boolean(params["gone"]) and is_boolean(params["warm"])), do: Repo.rollback(:invalid_report)

    for field <- ~w(size_bytes capacity_bytes attach_ms)a, into: %{} do
      value = Map.get(params, Atom.to_string(field))
      if not valid_metric?(value), do: Repo.rollback(:invalid_report)
      {field, value}
    end
  end

  # Only an older generation of the use's own base is meaningful; anything else
  # is ignored rather than failing an otherwise valid report.
  defp mounted_generation(usage, %{"mounted_generation" => generation})
       when is_integer(generation) and generation > 0 and generation < usage.base_generation, do: generation

  defp mounted_generation(_usage, _params), do: nil

  defp valid_metric?(nil), do: true
  defp valid_metric?(value), do: is_integer(value) and value >= 0 and value <= 9_000_000_000_000_000

  defp update_reported_usage(usage, params, metrics, now) do
    if is_nil(usage.last_reported_at) or usage.size_bytes != metrics.size_bytes or
         usage.capacity_bytes != metrics.capacity_bytes do
      record_measurement(usage, metrics, now, false)
    end

    Repo.update!(
      Ecto.Changeset.change(
        usage,
        Map.merge(metrics, %{
          last_reported_at: now,
          warm: params["warm"],
          mounted_generation: usage.mounted_generation || mounted_generation(usage, params),
          attached_at: usage.attached_at || now,
          status: if(usage.status == "allocated", do: "attached", else: usage.status)
        })
      )
    )
  end

  defp report_action(volume, usage, params, valid, now) do
    cond do
      not params["gone"] ->
        %{action: "hold"}

      not valid ->
        %{action: "delete"}

      usage.status == "published" ->
        published_action(volume, usage)

      usage.status == "discarded" ->
        %{action: "delete"}

      not usage.can_publish ->
        discard(usage, now)

      true ->
        completion_action(volume, usage, params["state"], now)
    end
  end

  # A checkout use publishes the host's master, never its own branch, so the branch
  # is not needed once the job is gone.
  defp published_action(%Volume{key: @checkout_key}, _usage), do: %{action: "delete"}

  defp published_action(volume, usage) do
    # Keep old parents until every referencing clone has finished. This prevents
    # deletion racing an allocated clone on a different host.
    referenced = Repo.exists?(from(u in Usage, where: u.parent_id == ^usage.id and is_nil(u.finished_at)))
    if volume.head_id == usage.id or referenced, do: %{action: "keep"}, else: %{action: "delete"}
  end

  defp completion_action(volume, usage, state, now) do
    completion = Repo.get_by(JobCompletion, workflow_job_id: usage.workflow_job_id, account_id: volume.account_id)

    cond do
      is_nil(completion) and DateTime.diff(now, usage.inserted_at) < 24 * 60 * 60 ->
        %{action: "wait"}

      is_nil(completion) or completion.conclusion != "success" ->
        discard(usage, now)

      state == "active" ->
        %{action: "seal"}

      state == "sealed" ->
        # Publication is committed only after the immutable image was uploaded.
        discard(usage, now)
    end
  end

  def storage_name(volume), do: volume.platform <> "-" <> scope(volume)

  @doc """
  The capacity a volume under `key` starts at when no size is requested.
  """
  def default_volume_bytes(key), do: Map.get(@managed_volume_bytes, key, @volume_bytes)

  @doc """
  The volume's capacity: the capacity its saved head was allocated at, or the
  capacity its next empty copy gets when nothing is saved. `head_volume_bytes`
  is the saved head use's `volume_bytes`; heads allocated before uses recorded
  it have the key's default. `nil` for the built-in volume, which its hosts size.
  """
  def volume_bytes(%Volume{builtin_name: name}, _head_volume_bytes) when is_binary(name), do: nil

  def volume_bytes(%Volume{head_id: nil, key: key} = volume, _head_volume_bytes),
    do: Map.get(@managed_volume_bytes, key) || volume.requested_volume_bytes || @volume_bytes

  def volume_bytes(%Volume{key: key}, head_volume_bytes), do: saved_volume_bytes(key, %{volume_bytes: head_volume_bytes})

  @doc """
  A smaller size requested for the volume, which applies once it next starts
  empty. `nil` when the volume keeps its capacity.
  """
  def pending_volume_bytes(%Volume{requested_volume_bytes: requested} = volume, head_volume_bytes) do
    if is_integer(requested) and requested < volume_bytes(volume, head_volume_bytes), do: requested
  end

  @doc """
  The capacity the volume's next job gets when it asks for the volume's
  requested size: the saved capacity, grown to a larger request.
  """
  def next_volume_bytes(%Volume{} = volume, head_volume_bytes),
    do: max(volume_bytes(volume, head_volume_bytes), volume.requested_volume_bytes || 0)

  @doc """
  The runner profile a default volume belongs to, or `nil` for named volumes
  and a repository's default volume.
  """
  def default_profile_id(%{key: @default_key <> "/" <> id}) do
    case Integer.parse(id) do
      {id, ""} -> id
      _ -> nil
    end
  end

  def default_profile_id(_volume), do: nil

  def default_volume?(volume), do: not is_nil(default_profile_id(volume))

  # A default volume is listed only while its runner profile exists. Deleting the
  # profile clears it (`clear_profile_volumes/1`); its rows remain until hosts
  # acknowledge reclaiming its data.
  defp visible(query) do
    prefix = @default_key <> "/"

    where(
      query,
      [volume: v],
      not like(v.key, ^(prefix <> "%")) or
        exists(
          from(p in Profile,
            where:
              p.account_id == parent_as(:volume).account_id and
                fragment("? = ? || ?::text", parent_as(:volume).key, ^prefix, p.id)
          )
        )
    )
  end

  @doc """
  Clears the default volumes of a deleted runner profile, like a clear from the
  dashboard. Call inside the transaction that deleted the profile, after the
  profile row, matching the lock order of allocation.
  """
  def clear_profile_volumes(%Profile{id: id, account_id: account_id}) do
    key = "#{@default_key}/#{id}"

    for volume <-
          Repo.all(from(v in Volume, where: v.account_id == ^account_id and v.key == ^key, lock: "FOR UPDATE")),
        is_nil(volume.deleted_at) do
      Runners.clear_volume_master(volume.account_id, storage_name(volume))
      Repo.update!(Ecto.Changeset.change(volume, clear_changes(volume)))
    end

    :ok
  end

  @doc """
  The current names of the runner profiles `volumes` are the default volumes
  of, keyed by volume ID. Deleted profiles are absent.
  """
  def default_profile_names(account_id, volumes) do
    ids = volumes |> Enum.map(&default_profile_id/1) |> Enum.reject(&is_nil/1) |> Enum.uniq()

    names =
      if ids == [],
        do: %{},
        else:
          Map.new(
            Repo.all(from(p in Profile, where: p.account_id == ^account_id and p.id in ^ids, select: {p.id, p.name}))
          )

    for volume <- volumes, name = Map.get(names, default_profile_id(volume)), into: %{}, do: {volume.id, name}
  end

  defp saved_volume_bytes(key, saved_head),
    do: Map.get(@managed_volume_bytes, key) || (saved_head && saved_head.volume_bytes) || @volume_bytes

  @doc """
  The lineage scopes of the custom volumes that jobs of `repository` attached
  since `since`, keyed by the `{workflow_name, job_name}` of the job. A job
  attaches its volumes at runtime, so this history is how dispatch predicts the
  volumes a queued job will attach.
  """
  def recent_job_scopes(account_id, repository, %DateTime{} = since)
      when is_integer(account_id) and is_binary(repository) do
    from(v in Volume,
      join: u in Usage,
      on: u.volume_id == v.id,
      join: j in WorkflowJob,
      on: j.workflow_job_id == u.workflow_job_id and j.account_id == v.account_id,
      where:
        v.account_id == ^account_id and v.repository == ^repository and is_nil(v.builtin_name) and
          is_nil(v.deleted_at) and u.inserted_at >= ^since,
      distinct: true,
      select: {j.workflow_name, j.job_name, v.id, v.generation}
    )
    |> Repo.all()
    |> Enum.group_by(
      fn {workflow_name, job_name, _id, _generation} -> {workflow_name, job_name} end,
      fn {_workflow_name, _job_name, id, generation} -> scope(%{id: id, generation: generation}) end
    )
  end

  def recent_job_scopes(_account_id, _repository, _since), do: %{}

  @doc """
  The saved HEADs of the macOS custom volumes jobs used on `node_names` since
  `since`, most recently used first. Each is the identity a host restores and
  then retains its master under: the use that published the HEAD.
  """
  def recent_macos_heads(node_names, %DateTime{} = since, limit) do
    since = DateTime.truncate(since, :second)

    from(u in Usage,
      join: v in Volume,
      on: v.id == u.volume_id,
      where:
        u.node_name in ^node_names and u.inserted_at >= ^since and v.platform == "macos" and is_nil(v.builtin_name) and
          is_nil(v.deleted_at) and v.key != ^@checkout_key,
      group_by: v.id,
      order_by: [desc: max(u.inserted_at)],
      limit: ^limit,
      select: v
    )
    |> Repo.all()
    |> Enum.flat_map(&head_identity/1)
  end

  defp head_identity(volume) do
    with %{generation: generation, tree_digest: digest, content_digest: content}
         when generation > 0 and is_binary(digest) and is_binary(content) <-
           VolumeHeads.get_head(volume.account_id, storage_name(volume)),
         %Usage{} = saved_head <-
           Repo.one(
             from(u in Usage,
               where:
                 u.volume_id == ^volume.id and u.generation == ^volume.generation and
                   u.published_generation == ^generation and u.status == "published",
               limit: 1
             )
           ) do
      [
        %{
          kind: "custom",
          id: saved_head.id,
          account_id: volume.account_id,
          scope: scope(volume),
          generation: generation,
          image_digest: digest,
          content_digest: content,
          volume_bytes: saved_volume_bytes(volume.key, saved_head),
          head_size_bytes: saved_head.size_bytes
        }
      ]
    else
      _ -> []
    end
  end

  # Reuse macOS HEAD arbitration, immutable objects, checksums and delayed
  # reclamation. The custom-volume lock also serializes clearing with publication.
  def image(node, id, params) do
    with {:ok, id} <- Ecto.UUID.cast(id),
         %Usage{} = usage <- image_usage(id, node, params) do
      Repo.transaction(fn ->
        volume = Repo.one!(from(v in Volume, where: v.id == ^usage.volume_id, lock: "FOR UPDATE"))
        if volume.builtin_name, do: Repo.rollback(:unsupported)
        usage = Repo.get!(Usage, id)
        volume = expire_locked(volume, DateTime.utc_now())
        image_action(volume, usage, params)
      end)
    else
      _ -> {:error, :not_found}
    end
  end

  # Retaining a master and downloading a saved master only read the lineage, so a
  # host may name a use allocated elsewhere: the server lists HEADs for hosts to
  # prefetch under the use that published them. Writes stay bound to the node.
  defp image_usage(id, _node, %{"operation" => operation}) when operation in ["retain", "download"],
    do: Repo.get(Usage, id)

  defp image_usage(id, node, _params), do: Repo.get_by(Usage, id: id, node_name: node)

  # A host validates each local master against the HEAD. The HEAD digests let it
  # name the newer master it can refresh into before discarding the stale one.
  defp image_action(volume, usage, %{"operation" => "retain"}) do
    if usage.generation != volume.generation or not is_nil(volume.deleted_at), do: Repo.rollback(:conflict)

    case VolumeHeads.get_head(volume.account_id, storage_name(volume)) do
      nil -> %{generation: 0}
      head -> %{generation: head.generation, image_digest: head.tree_digest, content_digest: head.content_digest}
    end
  end

  # A host holding a master of this lineage may refresh it to the current HEAD,
  # named by its generation, even after the use that installed it has finished.
  # Clearing bumps the lineage and still fails with a conflict.
  defp image_action(volume, usage, %{"operation" => "download", "generation" => generation})
       when is_integer(generation) and generation > 0 and generation != usage.base_generation do
    if usage.generation != volume.generation or not is_nil(volume.deleted_at), do: Repo.rollback(:conflict)
    head_download(volume, generation)
  end

  # A host restores a checkout HEAD in the background, possibly after the job that
  # asked for it is gone, so the use only has to name the current lineage.
  defp image_action(%Volume{key: @checkout_key} = volume, usage, %{"operation" => "download"}) do
    if usage.base_generation == 0 or usage.generation != volume.generation or not is_nil(volume.deleted_at),
      do: Repo.rollback(:conflict)

    head_download(volume, usage.base_generation)
  end

  defp image_action(volume, usage, %{"operation" => "download"}) do
    if not is_nil(usage.deleted_at) or usage.generation != volume.generation or not is_nil(volume.deleted_at),
      do: Repo.rollback(:conflict)

    if usage.base_generation == 0 do
      %{generation: 0}
    else
      case Runners.volume_master_download_url(
             volume.account_id,
             storage_name(volume),
             usage.image_digest,
             usage.content_digest
           ) do
        {:ok, url} -> %{download_url: url, generation: usage.base_generation, content_digest: usage.content_digest}
        _ -> Repo.rollback(:unavailable)
      end
    end
  end

  defp image_action(%Volume{key: @checkout_key} = volume, usage, %{
         "operation" => operation,
         "image_digest" => digest,
         "content_digest" => content
       })
       when operation in ["upload", "publish"] do
    if not valid_image_digests?(digest, content), do: Repo.rollback(:invalid_digest)
    checkout_publish(volume, usage, operation, digest, content)
  end

  defp image_action(volume, usage, %{"operation" => operation, "image_digest" => digest, "content_digest" => content})
       when operation in ["upload", "publish"] do
    if not valid_image_digests?(digest, content), do: Repo.rollback(:invalid_digest)

    cond do
      retired_image?(volume, usage) ->
        Repo.rollback(:conflict)

      published_image?(usage, digest, content) ->
        %{generation: usage.published_generation}

      not usage.can_publish or usage.status in ["published", "discarded"] ->
        Repo.rollback(:conflict)

      true ->
        completion = Repo.get_by(JobCompletion, workflow_job_id: usage.workflow_job_id, account_id: volume.account_id)
        if is_nil(completion) or completion.conclusion != "success", do: Repo.rollback(:conflict)
        image_publish(volume, usage, operation, digest, content)
    end
  end

  defp image_action(_, _, _), do: Repo.rollback(:invalid_request)

  # The host builds a checkout master from exports it verified itself, so the job's
  # outcome and the use's state after the job do not matter: the use only names
  # the lineage and the HEAD the master fast-forwards, once.
  defp checkout_publish(volume, usage, operation, digest, content) do
    cond do
      usage.generation != volume.generation or not is_nil(volume.deleted_at) ->
        Repo.rollback(:conflict)

      published_image?(usage, digest, content) ->
        %{generation: usage.published_generation}

      usage.status == "published" ->
        Repo.rollback(:conflict)

      true ->
        image_publish(volume, usage, operation, digest, content)
    end
  end

  defp head_download(volume, generation) do
    name = storage_name(volume)

    case VolumeHeads.get_head(volume.account_id, name) do
      %{generation: ^generation, content_digest: content} = head when is_binary(content) ->
        case Runners.volume_master_download_url(volume.account_id, name, head.tree_digest, content) do
          {:ok, url} -> %{download_url: url, generation: generation, content_digest: content}
          _ -> Repo.rollback(:unavailable)
        end

      _ ->
        Repo.rollback(:conflict)
    end
  end

  defp valid_image_digests?(digest, content) do
    is_binary(digest) and Regex.match?(~r/\A[a-f0-9]{40}\z/, digest) and
      is_binary(content) and Regex.match?(~r/\A[a-f0-9]{64}\z/, content)
  end

  defp retired_image?(volume, usage) do
    usage.generation != volume.generation or not is_nil(volume.deleted_at) or not is_nil(usage.deleted_at)
  end

  defp published_image?(usage, digest, content) do
    usage.status == "published" and usage.image_digest == digest and usage.content_digest == content
  end

  defp image_publish(volume, usage, "upload", digest, content) do
    name = storage_name(volume)

    if not Runners.fast_forward_viable?(volume.account_id, name, usage.base_generation),
      do: Repo.rollback(:conflict)

    case Runners.volume_master_upload_url(volume.account_id, name, digest, content) do
      {:ok, url, checksum} ->
        Runners.track_volume_master_upload(volume.account_id, name, digest, content)
        %{upload_url: url, checksum_sha256: checksum}

      _ ->
        Repo.rollback(:unavailable)
    end
  end

  defp image_publish(volume, usage, "publish", digest, content) do
    case Runners.report_volume_head(
           volume.account_id,
           storage_name(volume),
           usage.node_name,
           digest,
           usage.base_generation,
           nil,
           content
         ) do
      {:ok, generation} ->
        Repo.update!(
          Ecto.Changeset.change(usage,
            status: "published",
            finished_at: DateTime.utc_now(),
            published_generation: generation,
            image_digest: digest,
            content_digest: content
          )
        )

        Repo.update!(Ecto.Changeset.change(volume, head_id: usage.id))
        %{generation: generation}

      :conflict ->
        # Commit the orphan tracking from report_volume_head, even on rejection.
        discard(usage, DateTime.utc_now())
        %{conflict: true}

      _ ->
        Repo.rollback(:unavailable)
    end
  end

  defp discard(usage, now) do
    Repo.update!(Ecto.Changeset.change(usage, status: "discarded", finished_at: usage.finished_at || now))
    %{action: "delete"}
  end

  defp record_measurement(usage, metrics, now, deleted) do
    Repo.insert!(%Measurement{
      usage_id: usage.id,
      size_bytes: metrics.size_bytes,
      capacity_bytes: metrics.capacity_bytes,
      observed_at: now,
      deleted: deleted
    })
  end

  def get(account_id, id) do
    case Ecto.UUID.cast(id) do
      {:ok, id} -> Repo.one(visible(from(v in Volume, as: :volume, where: v.id == ^id and v.account_id == ^account_id)))
      _ -> nil
    end
  end

  def delete(account_id, id) do
    mutate(account_id, id, fn volume ->
      if volume.builtin_name, do: Repo.rollback(:unsupported)
      Runners.clear_volume_master(volume.account_id, storage_name(volume))
      clear_changes(volume)
    end)
  end

  defp clear_changes(volume), do: [generation: volume.generation + 1, head_id: nil, deleted_at: DateTime.utc_now()]

  defp mutate(account_id, id, changes) do
    case Ecto.UUID.cast(id) do
      {:ok, id} ->
        Repo.transaction(fn ->
          case Repo.one(from(v in Volume, where: v.id == ^id and v.account_id == ^account_id, lock: "FOR UPDATE")) do
            nil -> Repo.rollback(:not_found)
            volume -> Repo.update!(Ecto.Changeset.change(volume, changes.(volume)))
          end
        end)

      _ ->
        {:error, :not_found}
    end
  end

  def list(account_id, search \\ "", page \\ 1, opts \\ []) do
    query = inventory_query(account_id, search, opts)
    page_size = Keyword.get(opts, :page_size, 20)
    query = sort_volumes(query, account_id, opts)
    volumes = Repo.all(from(v in query, limit: ^(page_size + 1), offset: ^((page - 1) * page_size)))
    ids = Enum.map(volumes, & &1.id)
    %{volumes: Enum.take(volumes, page_size), more?: length(volumes) > page_size, stats: statistics(ids)}
  end

  def count(account_id, search \\ "", opts \\ []) do
    Repo.aggregate(inventory_query(account_id, search, opts), :count)
  end

  defp inventory_query(account_id, search, opts) do
    query = visible(from(v in Volume, as: :volume, where: v.account_id == ^account_id))

    query =
      if search == "",
        do: query,
        else: where(query, [v], ilike(v.key, ^"%#{search}%") or ilike(v.repository, ^"%#{search}%"))

    query = if name = opts[:name], do: where(query, [v], v.key == ^name), else: query
    if repository = opts[:repository], do: where(query, [v], v.repository == ^repository), else: query
  end

  def history_count(account_id, volume_id) do
    Repo.aggregate(
      from(u in Usage,
        join: v in Volume,
        on: v.id == u.volume_id,
        where: v.account_id == ^account_id and v.id == ^volume_id
      ),
      :count
    )
  end

  defp sort_volumes(query, account_id, opts) do
    direction = if Keyword.get(opts, :sort_order) == "asc", do: :asc_nulls_last, else: :desc_nulls_last

    case Keyword.get(opts, :sort_by, "last_used") do
      size when size in ["used_space", "capacity"] ->
        sizes =
          from(u in Usage,
            join: v in Volume,
            on: v.id == u.volume_id,
            where: v.account_id == ^account_id,
            group_by: u.volume_id,
            select: %{
              volume_id: u.volume_id,
              copies: filter(count(u.id), is_nil(coalesce(u.deleted_at, u.superseded_at))),
              used_space: filter(sum(u.size_bytes), is_nil(coalesce(u.deleted_at, u.superseded_at))),
              capacity: filter(sum(u.capacity_bytes), is_nil(coalesce(u.deleted_at, u.superseded_at)))
            }
          )

        value =
          if size == "used_space" do
            dynamic(
              [v, s],
              fragment(
                "CASE WHEN ? = 0 OR (? IS NULL AND ? IS NULL AND ? IS NULL) THEN 0 ELSE ? END",
                s.copies,
                v.head_id,
                v.deleted_at,
                s.used_space,
                s.used_space
              )
            )
          else
            dynamic([v, s], fragment("CASE WHEN ? = 0 THEN 0 ELSE ? END", s.copies, s.capacity))
          end

        query
        |> join(:left, [v], s in subquery(sizes), on: s.volume_id == v.id)
        |> order_by(^[{direction, value}])
        |> order_by([v], asc: v.id)

      column ->
        field =
          case column do
            "volume" -> :key
            "repository" -> :repository
            _ -> :last_used_at
          end

        order_by(query, ^[{direction, field}, {:asc, :id}])
    end
  end

  def statistics(ids) do
    since = DateTime.add(DateTime.utc_now(), -30 * 24 * 60 * 60)

    from(u in Usage,
      join: v in Volume,
      on: v.id == u.volume_id,
      where: u.volume_id in ^ids,
      group_by: u.volume_id,
      select:
        {u.volume_id,
         %{
           saved_bytes: type(filter(max(u.size_bytes), u.id == v.head_id), :integer),
           saved_capacity_bytes: type(filter(max(u.capacity_bytes), u.id == v.head_id), :integer),
           head_volume_bytes: type(filter(max(u.volume_bytes), u.id == v.head_id), :integer),
           uses: filter(count(u.id), not is_nil(u.attached_at) and u.inserted_at >= ^since),
           hits: filter(count(u.id), u.warm == true and u.inserted_at >= ^since),
           active: filter(count(u.id), is_nil(u.finished_at) and is_nil(coalesce(u.deleted_at, u.superseded_at))),
           retained_bytes: type(filter(sum(u.size_bytes), is_nil(coalesce(u.deleted_at, u.superseded_at))), :integer),
           retained_capacity_bytes:
             type(filter(sum(u.capacity_bytes), is_nil(coalesce(u.deleted_at, u.superseded_at))), :integer),
           unmeasured_copies:
             filter(count(u.id), is_nil(coalesce(u.deleted_at, u.superseded_at)) and is_nil(u.size_bytes)),
           unmeasured_capacity_copies:
             filter(count(u.id), is_nil(coalesce(u.deleted_at, u.superseded_at)) and is_nil(u.capacity_bytes)),
           retained_copies: filter(count(u.id), is_nil(coalesce(u.deleted_at, u.superseded_at))),
           reported_at: max(u.last_reported_at),
           attach_ms: filter(avg(u.attach_ms), not is_nil(u.attached_at) and u.inserted_at >= ^since)
         }}
    )
    |> Repo.all()
    |> Map.new()
  end

  # Account totals deliberately ignore the list's search and pagination.
  def storage_summary(account_id) do
    Repo.one(
      from(u in Usage,
        join: v in Volume,
        on: v.id == u.volume_id,
        where: v.account_id == ^account_id and (is_nil(u.deleted_at) and is_nil(u.superseded_at)),
        select: %{
          volumes: count(v.id, :distinct),
          retained_copies: count(u.id),
          retained_bytes: sum(u.size_bytes),
          retained_capacity_bytes: sum(u.capacity_bytes),
          unmeasured_copies: filter(count(u.id), is_nil(u.size_bytes)),
          unmeasured_capacity_copies: filter(count(u.id), is_nil(u.capacity_bytes))
        }
      )
    )
  end

  # Roll up per-copy changes before summing: summing measurement rows would count
  # every historical report as additional storage. Older reports seed the window.
  def storage_history(account_id, period \\ DateTime.utc_now(), volume_id \\ nil)

  def storage_history(account_id, %DateTime{} = now, volume_id) do
    storage_history(account_id, {DateTime.add(now, -7, :day), now}, volume_id)
  end

  def storage_history(account_id, {%DateTime{} = start, %DateTime{} = now}, volume_id) do
    result =
      Ecto.Adapters.SQL.query!(
        Repo,
        """
        WITH measurements AS (
          SELECT m.id, m.usage_id, u.volume_id, m.observed_at,
            CASE WHEN (m.deleted OR m.retired) THEN 0 ELSE COALESCE(m.size_bytes, 0) END AS used,
            CASE WHEN (m.deleted OR m.retired) THEN 0 ELSE COALESCE(m.capacity_bytes, 0) END AS capacity,
            CASE WHEN (m.deleted OR m.retired) THEN 0 ELSE 1 END AS copies,
            CASE WHEN NOT (m.deleted OR m.retired) AND m.size_bytes IS NOT NULL THEN 1 ELSE 0 END AS measured_used,
            CASE WHEN NOT (m.deleted OR m.retired) AND m.capacity_bytes IS NOT NULL THEN 1 ELSE 0 END AS measured_capacity
          FROM runner_cache_volume_measurements m
          JOIN runner_cache_volume_uses u ON u.id = m.usage_id
          JOIN runner_cache_volumes v ON v.id = u.volume_id
          WHERE v.account_id = $1 AND m.observed_at <= $2 AND ($4::uuid IS NULL OR v.id = $4::uuid)
          UNION ALL
          SELECT 0, u.id, u.volume_id, u.inserted_at, 0, 0, 1, 0, 0
          FROM runner_cache_volume_uses u
          JOIN runner_cache_volumes v ON v.id = u.volume_id
          WHERE v.account_id = $1 AND u.inserted_at <= $2 AND ($4::uuid IS NULL OR v.id = $4::uuid)
        ), changes AS (
          SELECT volume_id, CASE WHEN observed_at <= $3 THEN $3::timestamptz
            ELSE LEAST($2::timestamptz, date_trunc('hour', observed_at) + interval '1 hour') END AS bucket,
            used - LAG(used, 1, 0::bigint) OVER copy AS used,
            capacity - LAG(capacity, 1, 0::bigint) OVER copy AS capacity,
            copies - LAG(copies, 1, 0) OVER copy AS copies,
            measured_used - LAG(measured_used, 1, 0) OVER copy AS measured_used,
            measured_capacity - LAG(measured_capacity, 1, 0) OVER copy AS measured_capacity
          FROM measurements
          WINDOW copy AS (PARTITION BY usage_id ORDER BY observed_at, id)
        ), volume_hours AS (
          SELECT volume_id, bucket, SUM(used) AS used, SUM(capacity) AS capacity,
            SUM(copies) AS copies, SUM(measured_used) AS measured_used,
            SUM(measured_capacity) AS measured_capacity
          FROM changes GROUP BY volume_id, bucket
        ), volume_totals AS (
          SELECT *, SUM(copies) OVER (PARTITION BY volume_id ORDER BY bucket) AS retained
          FROM volume_hours
        ), volume_changes AS (
          SELECT *, (CASE WHEN retained > 0 THEN 1 ELSE 0 END) -
            LAG(CASE WHEN retained > 0 THEN 1 ELSE 0 END, 1, 0)
              OVER (PARTITION BY volume_id ORDER BY bucket) AS volumes
          FROM volume_totals
        ), hourly AS (
          SELECT bucket, SUM(used) AS used, SUM(capacity) AS capacity,
            SUM(copies) AS copies, SUM(measured_used) AS measured_used,
            SUM(measured_capacity) AS measured_capacity, SUM(volumes) AS volumes
          FROM volume_changes GROUP BY bucket
        )
        SELECT bucket, (SUM(used) OVER timeline)::bigint, (SUM(capacity) OVER timeline)::bigint,
          (SUM(copies) OVER timeline)::bigint, (SUM(measured_used) OVER timeline)::bigint,
          (SUM(measured_capacity) OVER timeline)::bigint, (SUM(volumes) OVER timeline)::bigint
        FROM hourly
        WINDOW timeline AS (ORDER BY bucket)
        ORDER BY bucket
        """,
        [
          account_id,
          now,
          start,
          if(volume_id, do: Ecto.UUID.dump!(volume_id))
        ]
      )

    points =
      Enum.map(result.rows, fn [at, used, capacity, copies, measured_used, measured_capacity, volumes] ->
        %{
          at: at,
          volumes: volumes,
          unmeasured_copies: copies - measured_used,
          unmeasured_capacity_copies: copies - measured_capacity,
          used_bytes: if(copies > 0 and measured_used == 0, do: nil, else: used),
          capacity_bytes: if(copies > 0 and measured_capacity == 0, do: nil, else: capacity)
        }
      end)

    case List.last(points) do
      nil -> []
      last -> if DateTime.before?(last.at, now), do: points ++ [%{last | at: now}], else: points
    end
  end

  def usage_analytics(account_id, period), do: usage_analytics(account_id, nil, period)

  def usage_analytics(account_id, volume_id, {start, finish}) do
    {bucket, seconds} = if DateTime.diff(finish, start) <= 2 * 86_400, do: {"hour", 3600}, else: {"day", 86_400}

    mounts =
      from(u in Usage,
        join: v in Volume,
        on: v.id == u.volume_id,
        where: v.account_id == ^account_id,
        where: u.attached_at >= ^start and u.attached_at <= ^finish,
        select: %{
          at: type(fragment("date_trunc(?, ? AT TIME ZONE 'UTC')", ^bucket, u.attached_at), :utc_datetime),
          warm: u.warm
        }
      )

    mounts = if volume_id, do: where(mounts, [u, v], v.id == ^volume_id), else: mounts

    rows =
      Repo.all(
        from(u in subquery(mounts),
          group_by: u.at,
          select: %{
            at: u.at,
            uses: count(),
            hits: filter(count(), u.warm == true),
            known: count(u.warm)
          }
        )
      )

    by_bucket = Map.new(rows, &{DateTime.to_unix(&1.at), &1})
    first_bucket = div(DateTime.to_unix(start), seconds) * seconds
    last_bucket = div(DateTime.to_unix(finish), seconds) * seconds

    points =
      Enum.map(first_bucket..last_bucket//seconds, fn timestamp ->
        row = Map.get(by_bucket, timestamp, %{uses: 0, hits: 0, known: 0})
        at = DateTime.from_unix!(timestamp)

        %{
          at: if(DateTime.before?(at, start), do: start, else: at),
          uses: row.uses,
          hit_rate: if(row.known > 0, do: Float.round(row.hits / row.known * 100, 1))
        }
      end)

    uses = Enum.sum(Enum.map(rows, & &1.uses))
    hits = Enum.sum(Enum.map(rows, & &1.hits))
    known = Enum.sum(Enum.map(rows, & &1.known))
    %{points: points, uses: uses, hit_rate: if(known > 0, do: Float.round(hits / known * 100, 1))}
  end

  def size_history(account_id, volume_id, page \\ 1) do
    Repo.all(
      from(m in Measurement,
        join: u in Usage,
        on: u.id == m.usage_id,
        join: v in Volume,
        on: v.id == u.volume_id,
        where: v.account_id == ^account_id and v.id == ^volume_id,
        order_by: [desc: m.observed_at, desc: m.id],
        limit: 20,
        offset: ^((page - 1) * 20),
        select: %{measurement: m, workflow_job_id: u.workflow_job_id, workflow_run_id: u.workflow_run_id}
      )
    )
  end

  # Cross-tenant maintenance: prune deleted copies and superseded built-in observations.
  def prune_history do
    threshold = DateTime.add(DateTime.utc_now(), -90 * 24 * 60 * 60)
    Repo.delete_all(from(u in Usage, where: u.deleted_at < ^threshold or u.superseded_at < ^threshold))
    :ok
  end

  def for_job(account_id, workflow_run_id, workflow_job_id) do
    Usage
    |> join(:inner, [u], v in Volume, as: :volume, on: v.id == u.volume_id)
    |> visible()
    |> where(
      [u, v],
      v.account_id == ^account_id and u.workflow_run_id == ^workflow_run_id and
        u.workflow_job_id == ^workflow_job_id and not is_nil(u.attached_at)
    )
    |> distinct([u], u.volume_id)
    |> order_by([u], asc: u.volume_id, desc: u.attached_at, desc: u.id)
    |> preload([u, v], volume: v)
    |> Repo.all()
    |> Enum.sort_by(&{&1.volume.key, &1.volume.id})
  end

  def history(account_id, volume_id, page \\ 1, limit \\ 20) do
    Repo.all(
      from(u in Usage,
        join: v in Volume,
        on: v.id == u.volume_id,
        left_join: j in WorkflowJob,
        on:
          j.account_id == v.account_id and j.workflow_job_id == u.workflow_job_id and
            j.workflow_run_id == u.workflow_run_id,
        where: v.account_id == ^account_id and v.id == ^volume_id,
        order_by: [desc: u.inserted_at, desc: u.id],
        limit: ^limit,
        offset: ^((page - 1) * limit),
        select: %{u | job_name: j.job_name, workflow_name: j.workflow_name}
      )
    )
  end
end
