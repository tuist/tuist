defmodule Cache.DistributedKV.Cleanup do
  @moduledoc false

  import Ecto.Query

  alias Cache.Config
  alias Cache.DistributedKV.Project
  alias Cache.DistributedKV.Repo
  alias Cache.DistributedKV.State
  alias Cache.KeyValueRepo

  @project_insert_types %{account_handle: :string, project_handle: :string}
  @discovery_watermark "cleanup_discovery_watermark"
  @applied_generation_prefix "cleanup_applied:"

  def begin_project_cleanup(account_handle, project_handle) do
    lease_ms = Config.distributed_kv_cleanup_lease_ms()

    insert_query =
      from(
        project in values([%{account_handle: account_handle, project_handle: project_handle}], @project_insert_types),
        select: %{
          account_handle: project.account_handle,
          project_handle: project.project_handle,
          active_cleanup_cutoff_at: fragment("clock_timestamp()::timestamp"),
          cleanup_lease_expires_at:
            fragment("(clock_timestamp() + (? * INTERVAL '1 millisecond'))::timestamp", ^lease_ms),
          updated_at: fragment("clock_timestamp()::timestamp")
        }
      )

    on_conflict =
      from(project in Project,
        where:
          is_nil(project.active_cleanup_cutoff_at) or
            project.cleanup_lease_expires_at <= fragment("clock_timestamp()::timestamp"),
        update: [
          set: [
            active_cleanup_cutoff_at: fragment("clock_timestamp()::timestamp"),
            cleanup_lease_expires_at:
              fragment("(clock_timestamp() + (? * INTERVAL '1 millisecond'))::timestamp", ^lease_ms),
            updated_at: fragment("clock_timestamp()::timestamp")
          ]
        ]
      )

    case Repo.insert_all(
           Project,
           insert_query,
           on_conflict: on_conflict,
           conflict_target: [:account_handle, :project_handle],
           returning: [:active_cleanup_cutoff_at]
         ) do
      {1, [%{active_cleanup_cutoff_at: active_cleanup_cutoff_at}]} -> {:ok, active_cleanup_cutoff_at}
      {0, []} -> {:error, :cleanup_already_in_progress}
    end
  end

  def renew_project_cleanup_lease(account_handle, project_handle, active_cleanup_cutoff_at) do
    lease_ms = Config.distributed_kv_cleanup_lease_ms()

    {count, _} =
      Repo.update_all(
        from(project in Project,
          where:
            project.account_handle == ^account_handle and project.project_handle == ^project_handle and
              project.active_cleanup_cutoff_at == ^active_cleanup_cutoff_at and
              project.cleanup_lease_expires_at > fragment("clock_timestamp()::timestamp"),
          update: [
            set: [
              cleanup_lease_expires_at:
                fragment("(clock_timestamp() + (? * INTERVAL '1 millisecond'))::timestamp", ^lease_ms),
              updated_at: fragment("clock_timestamp()::timestamp")
            ]
          ]
        ),
        []
      )

    if count == 1 do
      :ok
    else
      {:error, :cleanup_lease_lost}
    end
  end

  def publish_project_cleanup(account_handle, project_handle, active_cleanup_cutoff_at) do
    {count, _} =
      Repo.update_all(
        from(project in Project,
          where:
            project.account_handle == ^account_handle and project.project_handle == ^project_handle and
              project.active_cleanup_cutoff_at == ^active_cleanup_cutoff_at,
          update: [
            set: [
              published_cleanup_generation: fragment("COALESCE(?, 0) + 1", project.published_cleanup_generation),
              published_cleanup_cutoff_at: fragment("date_trunc('second', ?)", project.active_cleanup_cutoff_at),
              cleanup_published_at: fragment("clock_timestamp()::timestamp"),
              cleanup_event_id: fragment("nextval('cleanup_event_id_seq')"),
              active_cleanup_cutoff_at: nil,
              cleanup_lease_expires_at: nil,
              updated_at: fragment("clock_timestamp()::timestamp")
            ]
          ]
        ),
        []
      )

    case count do
      1 ->
        published =
          Project
          |> where([p], p.account_handle == ^account_handle and p.project_handle == ^project_handle)
          |> select([p], %{
            published_cleanup_generation: p.published_cleanup_generation,
            published_cleanup_cutoff_at: p.published_cleanup_cutoff_at,
            cleanup_event_id: p.cleanup_event_id
          })
          |> Repo.one!()

        {:ok, published}

      0 ->
        {:error, :cleanup_not_active}
    end
  end

  def expire_project_cleanup_lease(account_handle, project_handle, active_cleanup_cutoff_at) do
    _ =
      Repo.update_all(
        from(project in Project,
          where:
            project.account_handle == ^account_handle and project.project_handle == ^project_handle and
              project.active_cleanup_cutoff_at == ^active_cleanup_cutoff_at,
          update: [
            set: [
              active_cleanup_cutoff_at: nil,
              cleanup_lease_expires_at: nil,
              updated_at: fragment("clock_timestamp()::timestamp")
            ]
          ]
        ),
        []
      )

    :ok
  end

  def effective_project_barriers(scopes) do
    scope_pairs =
      scopes
      |> Enum.map(&{&1.account_handle, &1.project_handle})
      |> Enum.uniq()

    case scope_pairs do
      [] ->
        %{}

      _ ->
        requested_scopes =
          Enum.map(scope_pairs, fn {account_handle, project_handle} ->
            %{account_handle: account_handle, project_handle: project_handle}
          end)

        Project
        |> join(
          :inner,
          [project],
          requested_scope in values(requested_scopes, %{account_handle: :string, project_handle: :string}),
          on:
            project.account_handle == requested_scope.account_handle and
              project.project_handle == requested_scope.project_handle
        )
        |> select(
          [project, _requested_scope],
          {project.account_handle, project.project_handle, project.active_cleanup_cutoff_at,
           project.cleanup_lease_expires_at, project.published_cleanup_cutoff_at}
        )
        |> Repo.all(timeout: Config.distributed_kv_database_timeout_ms())
        |> Map.new(fn {account_handle, project_handle, active_cutoff, lease_expires, published_cutoff} ->
          barrier = compute_effective_barrier(active_cutoff, lease_expires, published_cutoff)
          {{account_handle, project_handle}, barrier}
        end)
        |> Enum.reject(fn {_key, barrier} -> is_nil(barrier) end)
        |> Map.new()
    end
  end

  def latest_project_cleanup_cutoff(account_handle, project_handle) do
    Project
    |> where([project], project.account_handle == ^account_handle)
    |> where([project], project.project_handle == ^project_handle)
    |> select(
      [project],
      {project.active_cleanup_cutoff_at, project.cleanup_lease_expires_at, project.published_cleanup_cutoff_at}
    )
    |> Repo.one()
    |> case do
      nil ->
        nil

      {active_cutoff, lease_expires, published_cutoff} ->
        barrier = compute_effective_barrier(active_cutoff, lease_expires, published_cutoff)
        if barrier, do: DateTime.truncate(barrier, :second)
    end
  end

  def list_published_cleanups_after_event_id(watermark_event_id, limit) do
    query =
      Project
      |> where([project], not is_nil(project.cleanup_event_id))
      |> apply_event_id_filter(watermark_event_id)
      |> order_by([project], asc: project.cleanup_event_id)
      |> limit(^limit)
      |> select([project], %{
        account_handle: project.account_handle,
        project_handle: project.project_handle,
        published_cleanup_generation: project.published_cleanup_generation,
        published_cleanup_cutoff_at: project.published_cleanup_cutoff_at,
        cleanup_event_id: project.cleanup_event_id
      })

    events = Repo.all(query, timeout: Config.distributed_kv_database_timeout_ms())

    next_watermark =
      case List.last(events) do
        nil -> watermark_event_id
        event -> event.cleanup_event_id
      end

    {events, next_watermark}
  end

  def published_cleanup_barriers_for_projects(scope_pairs) do
    case scope_pairs do
      [] ->
        %{}

      _ ->
        requested_scopes =
          Enum.map(scope_pairs, fn {account_handle, project_handle} ->
            %{account_handle: account_handle, project_handle: project_handle}
          end)

        Project
        |> join(
          :inner,
          [project],
          requested_scope in values(requested_scopes, %{account_handle: :string, project_handle: :string}),
          on:
            project.account_handle == requested_scope.account_handle and
              project.project_handle == requested_scope.project_handle
        )
        |> where([project, _], not is_nil(project.published_cleanup_cutoff_at))
        |> select(
          [project, _],
          {project.account_handle, project.project_handle, project.published_cleanup_cutoff_at}
        )
        |> Repo.all(timeout: Config.distributed_kv_database_timeout_ms())
        |> Map.new(fn {ah, ph, cutoff} -> {{ah, ph}, truncate_or_nil(cutoff)} end)
    end
  end

  def gc_shared_entries(batch_size) do
    {count, _} =
      """
      WITH doomed AS (
        SELECT entry.key
        FROM key_value_entries entry
        JOIN projects project
          ON entry.account_handle = project.account_handle
         AND entry.project_handle = project.project_handle
        WHERE project.published_cleanup_cutoff_at IS NOT NULL
          AND entry.source_updated_at <= project.published_cleanup_cutoff_at
        ORDER BY entry.account_handle, entry.project_handle, entry.source_updated_at, entry.key
        LIMIT $1
      )
      DELETE FROM key_value_entries entry
      USING doomed
      WHERE entry.key = doomed.key
      """
      |> Repo.query!(
        [batch_size],
        timeout: Config.distributed_kv_database_timeout_ms()
      )
      |> then(fn %{num_rows: count} -> {count, nil} end)

    count
  end

  def get_local_discovery_watermark do
    case KeyValueRepo.get(State, @discovery_watermark) do
      nil -> nil
      %State{watermark_key: nil} -> nil
      %State{watermark_key: value} -> String.to_integer(value)
    end
  end

  def put_local_discovery_watermark(event_id) do
    attrs = %{
      name: @discovery_watermark,
      watermark_updated_at: DateTime.utc_now(),
      watermark_key: Integer.to_string(event_id)
    }

    %State{name: @discovery_watermark}
    |> State.changeset(attrs)
    |> KeyValueRepo.insert!(
      on_conflict: [set: [watermark_updated_at: attrs.watermark_updated_at, watermark_key: attrs.watermark_key]],
      conflict_target: :name
    )

    :ok
  end

  def local_applied_generation(account_handle, project_handle) do
    name = applied_generation_key(account_handle, project_handle)

    case KeyValueRepo.get(State, name) do
      nil -> 0
      %State{watermark_key: nil} -> 0
      %State{watermark_key: value} -> String.to_integer(value)
    end
  end

  def put_local_applied_generation(account_handle, project_handle, generation) do
    name = applied_generation_key(account_handle, project_handle)
    attrs = %{name: name, watermark_updated_at: DateTime.utc_now(), watermark_key: Integer.to_string(generation)}

    %State{name: name}
    |> State.changeset(attrs)
    |> KeyValueRepo.insert!(
      on_conflict: [set: [watermark_updated_at: attrs.watermark_updated_at, watermark_key: attrs.watermark_key]],
      conflict_target: :name
    )

    :ok
  end

  defp compute_effective_barrier(active_cutoff, lease_expires, published_cutoff) do
    active_barrier = active_barrier_if_alive(active_cutoff, lease_expires)
    published_barrier = truncate_or_nil(published_cutoff)
    max_barrier(active_barrier, published_barrier)
  end

  defp active_barrier_if_alive(cutoff, lease_expires) when not is_nil(cutoff) and not is_nil(lease_expires) do
    if DateTime.after?(lease_expires, DateTime.utc_now()), do: DateTime.truncate(cutoff, :second)
  end

  defp active_barrier_if_alive(_cutoff, _lease_expires), do: nil

  defp truncate_or_nil(nil), do: nil
  defp truncate_or_nil(dt), do: DateTime.truncate(dt, :second)

  defp max_barrier(nil, right), do: right
  defp max_barrier(left, nil), do: left
  defp max_barrier(left, right), do: if(DateTime.after?(left, right), do: left, else: right)

  defp apply_event_id_filter(query, nil), do: query

  defp apply_event_id_filter(query, watermark_event_id) do
    from(project in query, where: project.cleanup_event_id > ^watermark_event_id)
  end

  defp applied_generation_key(account_handle, project_handle) do
    "#{@applied_generation_prefix}#{account_handle}/#{project_handle}"
  end
end
