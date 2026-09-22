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

  alias Tuist.Repo
  alias Tuist.Runners.CacheVolumes.Identity
  alias Tuist.Runners.CacheVolumes.Measurement
  alias Tuist.Runners.CacheVolumes.Usage
  alias Tuist.Runners.CacheVolumes.Volume
  alias Tuist.Runners.JobCompletion
  alias Tuist.Runners.RunnerSession
  alias Tuist.Runners.WorkflowJob

  @retention_seconds 7 * 24 * 60 * 60

  def allocate(%{
        "pod_name" => pod,
        "pod_uid" => uid,
        "node_name" => node,
        "key" => key,
        "architecture" => arch,
        "uid" => user_id
      }) do
    with true <- valid_key?(key),
         true <- arch in ["amd64", "arm64"],
         true <- is_integer(user_id) and user_id >= 0 and user_id <= 2_147_483_647,
         true <- is_binary(uid) and Regex.match?(~r/^[a-zA-Z0-9-]{1,128}$/, uid),
         %WorkflowJob{} = job <- executing_job(pod, node),
         {:ok, identity} <- Identity.resolve(job) do
      allocate_for_job(job, identity, %{
        pod_name: pod,
        pod_uid: uid,
        node_name: node,
        key: key,
        architecture: arch,
        uid: user_id
      })
    else
      _ -> {:error, :unavailable}
    end
  end

  def allocate(_), do: {:error, :unavailable}

  def valid_key?(key), do: is_binary(key) and Regex.match?(~r/^[a-zA-Z0-9][a-zA-Z0-9_.\/-]{0,199}$/, key)

  defp executing_job(pod, node) do
    Repo.one(
      from(s in RunnerSession,
        join: j in WorkflowJob,
        on: j.workflow_job_id == s.executed_workflow_job_id and j.account_id == s.account_id,
        where:
          s.pod_name == ^pod and s.node_name == ^node and is_nil(s.ended_at) and s.platform == :linux and
            j.provider in ["github", "buildkite", "gitlab"] and j.status == "running",
        order_by: [desc: s.started_at],
        limit: 1,
        select: j
      )
    )
  end

  defdelegate run_identity(job, run), to: Identity, as: :github_identity

  # Also used by lifecycle tests with already verified provider metadata.
  def allocate_for_job(job, identity, attrs) do
    identity = Identity.storage_scope(identity)

    Repo.transaction(fn ->
      # One admission lock per pod also bounds concurrent requests for new keys.
      Repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
        "cache-volume:#{job.account_id}:#{attrs.pod_uid}"
      ])

      ensure_job_capacity!(job, identity, attrs)
      now = DateTime.utc_now()
      timestamp = DateTime.truncate(now, :second)
      fields = Map.take(attrs, [:key, :architecture, :uid])

      row =
        Map.merge(fields, %{
          id: Ecto.UUID.generate(),
          account_id: job.account_id,
          repository_id: identity.repository_id,
          provider: identity.provider,
          provider_instance: identity.provider_instance,
          scope_id: identity.scope_id,
          repository: job.repository,
          inserted_at: timestamp,
          updated_at: timestamp
        })

      Repo.insert_all(Volume, [row],
        on_conflict: :nothing,
        conflict_target: [:account_id, :provider, :provider_instance, :scope_id, :key, :architecture, :uid]
      )

      volume =
        Repo.one!(from(v in volume_query(job, identity, attrs), lock: "FOR UPDATE"))

      volume = expire_locked(volume, now)

      use_attrs =
        Map.merge(Map.take(attrs, [:pod_name, :pod_uid, :node_name]), %{
          id: Ecto.UUID.generate(),
          volume_id: volume.id,
          generation: volume.generation,
          parent_id: volume.head_id,
          workflow_job_id: job.workflow_job_id,
          workflow_run_id: job.workflow_run_id,
          can_publish: identity.trusted,
          inserted_at: timestamp,
          updated_at: timestamp
        })

      Repo.insert_all(Usage, [use_attrs],
        on_conflict: :nothing,
        conflict_target: [:volume_id, :generation, :pod_uid]
      )

      usage = Repo.get_by!(Usage, volume_id: volume.id, generation: volume.generation, pod_uid: attrs.pod_uid)

      if usage.node_name != attrs.node_name or usage.workflow_job_id != job.workflow_job_id do
        Repo.rollback(:unavailable)
      end

      Repo.update!(
        Ecto.Changeset.change(volume,
          last_used_at: if(volume.deleted_at, do: nil, else: volume.last_used_at),
          deleted_at: nil,
          repository: job.repository
        )
      )

      %{
        id: usage.id,
        account_id: volume.account_id,
        scope: scope(volume),
        parent_id: usage.parent_id,
        can_publish: usage.can_publish,
        uid: volume.uid
      }
    end)
  end

  defp ensure_job_capacity!(job, identity, attrs) do
    count =
      Repo.aggregate(
        from(u in Usage,
          join: v in Volume,
          on: v.id == u.volume_id,
          where: v.account_id == ^job.account_id and u.pod_uid == ^attrs.pod_uid
        ),
        :count
      )

    if count >= 8 and not existing_allocation?(job, identity, attrs), do: Repo.rollback(:capacity)
  end

  defp volume_query(job, identity, attrs) do
    from(v in Volume,
      where:
        v.account_id == ^job.account_id and v.provider == ^identity.provider and
          v.provider_instance == ^identity.provider_instance and v.scope_id == ^identity.scope_id and
          v.key == ^attrs.key and v.architecture == ^attrs.architecture and v.uid == ^attrs.uid
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
            where: is_nil(v.deleted_at) and v.last_used_at <= ^threshold,
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
        Repo.update!(Ecto.Changeset.change(usage, status: "published", finished_at: now))
        Repo.update!(Ecto.Changeset.change(volume, head_id: usage.id))
        %{action: "keep"}
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
      {:ok, id} -> Repo.get_by(Volume, id: id, account_id: account_id)
      _ -> nil
    end
  end

  def delete(account_id, id) do
    mutate(account_id, id, fn volume ->
      [generation: volume.generation + 1, head_id: nil, deleted_at: DateTime.utc_now()]
    end)
  end

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
    query =
      from(v in Volume,
        where: v.account_id == ^account_id
      )

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
              copies: filter(count(u.id), is_nil(u.deleted_at)),
              used_space: filter(sum(u.size_bytes), is_nil(u.deleted_at)),
              capacity: filter(sum(u.capacity_bytes), is_nil(u.deleted_at))
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
      where: u.volume_id in ^ids,
      group_by: u.volume_id,
      select:
        {u.volume_id,
         %{
           uses: filter(count(u.id), not is_nil(u.attached_at) and u.inserted_at >= ^since),
           hits: filter(count(u.id), u.warm == true and u.inserted_at >= ^since),
           active: filter(count(u.id), is_nil(u.finished_at) and is_nil(u.deleted_at)),
           retained_bytes: filter(sum(u.size_bytes), is_nil(u.deleted_at)),
           retained_capacity_bytes: filter(sum(u.capacity_bytes), is_nil(u.deleted_at)),
           unmeasured_copies: filter(count(u.id), is_nil(u.deleted_at) and is_nil(u.size_bytes)),
           unmeasured_capacity_copies: filter(count(u.id), is_nil(u.deleted_at) and is_nil(u.capacity_bytes)),
           retained_copies: filter(count(u.id), is_nil(u.deleted_at)),
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
        where: v.account_id == ^account_id and is_nil(u.deleted_at),
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
            CASE WHEN m.deleted THEN 0 ELSE COALESCE(m.size_bytes, 0) END AS used,
            CASE WHEN m.deleted THEN 0 ELSE COALESCE(m.capacity_bytes, 0) END AS capacity,
            CASE WHEN m.deleted THEN 0 ELSE 1 END AS copies,
            CASE WHEN NOT m.deleted AND m.size_bytes IS NOT NULL THEN 1 ELSE 0 END AS measured_used,
            CASE WHEN NOT m.deleted AND m.capacity_bytes IS NOT NULL THEN 1 ELSE 0 END AS measured_capacity
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
        [account_id, now, start, if(volume_id, do: Ecto.UUID.dump!(volume_id))]
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

  # Cross-tenant maintenance: only acknowledged deletions can lose their history.
  def prune_history do
    threshold = DateTime.add(DateTime.utc_now(), -90 * 24 * 60 * 60)
    Repo.delete_all(from(u in Usage, where: u.deleted_at < ^threshold))
    :ok
  end

  def for_job(account_id, workflow_run_id, workflow_job_id) do
    Usage
    |> join(:inner, [u], v in Volume, on: v.id == u.volume_id)
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
