defmodule Tuist.OnceEvents.ActionHistory do
  @moduledoc """
  Project-scoped logical action history, distinct from individual run occurrences.
  Only producer-owned keys participate; legacy rows are never matched by labels.
  """
  import Ecto.Query

  alias Phoenix.PubSub
  alias Tuist.OnceEvents.Action
  alias Tuist.OnceEvents.Run
  alias Tuist.Repo

  def fields(project_id, history, capability \\ "build") do
    case normalize(history) do
      nil ->
        %{history_id: nil, history_namespace: nil, history_key: nil, history_ambiguous: false}

      %{namespace: namespace, key: key} ->
        identity =
          <<project_id::unsigned-big-64, byte_size(namespace)::unsigned-big-16, namespace::binary,
            byte_size(key)::unsigned-big-16, key::binary, byte_size(capability)::unsigned-big-16, capability::binary>>

        <<a::32, b::16, c::16, d::16, e::48, _::binary>> =
          :crypto.hash(:sha256, "once.action-history.v1\0" <> identity)

        id = Ecto.UUID.cast!(<<a::32, b::16, 8::4, c::12, 2::2, d::14, e::48>>)
        %{history_id: id, history_namespace: namespace, history_key: key, history_ambiguous: false}
    end
  end

  def normalize(history) when is_map(history) do
    namespace = Map.get(history, :namespace, Map.get(history, "namespace"))
    key = Map.get(history, :key, Map.get(history, "key"))

    if is_binary(namespace) and byte_size(namespace) in 1..64 and
         Regex.match?(~r/\A[A-Za-z0-9._-]+\z/, namespace) and is_binary(key) and
         byte_size(key) in 1..128 and String.valid?(key) and
         not Regex.match?(~r/[\p{Cc}]/u, key) do
      %{namespace: namespace, key: key}
    end
  end

  def normalize(_), do: nil

  def available?(%Action{history_id: id, history_ambiguous: ambiguous}), do: not is_nil(id) and not ambiguous

  def get_occurrence(project_id, run_id, action_id) do
    with {:ok, id} <- Ecto.UUID.cast(action_id),
         %Action{} = action <-
           Repo.one(
             from(a in Action,
               join: r in Run,
               on: r.id == a.once_run_id and r.project_id == ^project_id,
               where: a.project_id == ^project_id and r.run_id == ^run_id and a.id == ^id,
               preload: [run: r]
             )
           ) do
      {:ok, action}
    else
      _ -> {:error, :not_found}
    end
  end

  def guard_identity(repo, attrs) do
    if attrs.history_id do
      # Serialize only matching keys within this run so concurrent completions
      # cannot both declare a colliding key unambiguous.
      repo.query!("SELECT pg_advisory_xact_lock(hashtextextended($1, 0))", [
        attrs.once_run_id <> ":" <> attrs.history_id
      ])
    end

    :ok
  end

  def subscribe(project_id, history_id), do: PubSub.subscribe(Tuist.PubSub, topic(project_id, history_id))

  def broadcast(%Action{history_id: id, project_id: project_id}) when not is_nil(id) do
    PubSub.broadcast(Tuist.PubSub, topic(project_id, id), {:action_history_updated, id})
  end

  def broadcast(_), do: :ok

  defp topic(project_id, history_id), do: "once:action-history:#{project_id}:#{history_id}"

  def mark_collisions(_repo, %Action{history_id: nil}), do: false

  def mark_collisions(repo, %Action{} = action) do
    query =
      from(a in Action,
        where:
          a.project_id == ^action.project_id and a.once_run_id == ^action.once_run_id and
            a.history_id == ^action.history_id
      )

    if repo.aggregate(query, :count) > 1 do
      repo.update_all(query, set: [history_ambiguous: true])
      true
    else
      false
    end
  end

  def list_occurrences(%Action{} = action, opts \\ []) do
    if available?(action) do
      page = opts |> Keyword.get(:page, 1) |> max(1) |> min(10_000)
      page_size = opts |> Keyword.get(:page_size, 20) |> max(1) |> min(50)
      query = action |> cohort(opts) |> in_period(opts)
      count = Repo.aggregate(query, :count)

      rows =
        Repo.all(
          from([a, r] in query,
            order_by: [desc: a.started_at, desc: a.id],
            limit: ^page_size,
            offset: ^((page - 1) * page_size),
            preload: [run: r]
          )
        )

      {rows, %{page: page, page_size: page_size, total_count: count, total_pages: max(ceil(count / page_size), 1)}}
    else
      {[], %{page: 1, page_size: 20, total_count: 0, total_pages: 1}}
    end
  end

  def analytics(%Action{} = action, opts \\ []) do
    if available?(action) do
      query = cohort(action, opts)

      observed =
        Repo.one(
          from([a] in query,
            select: %{
              first_seen: min(a.started_at),
              first_failure: filter(min(a.started_at), a.result == "failed" and not a.was_cached)
            }
          )
        )

      period = in_period(query, opts)

      stats =
        Repo.one(
          from([a] in period,
            select: %{
              total: count(a.id),
              executions: filter(count(a.id), not a.was_cached),
              failures: filter(count(a.id), a.result == "failed" and not a.was_cached),
              hits: filter(count(a.id), a.was_cached),
              cache_observations: filter(count(a.id), a.was_cached or (not is_nil(a.cache_key) and a.cache_key != "")),
              duration: filter(avg(a.duration_ms), not a.was_cached)
            }
          )
        )

      bucket = if period_days(opts) > 40, do: "week", else: "day"

      series = query_series(period, bucket)

      Map.merge(stats, Map.put(observed, :series, series))
    else
      %{
        total: 0,
        executions: 0,
        failures: 0,
        hits: 0,
        cache_observations: 0,
        duration: nil,
        first_seen: nil,
        first_failure: nil,
        series: []
      }
    end
  end

  defp query_series(period, bucket) do
    Repo.all(
      from([a] in period,
        group_by: selected_as(:history_bucket),
        order_by: selected_as(:history_bucket),
        limit: 40,
        select: %{
          day: selected_as(fragment("date_trunc(?, ? AT TIME ZONE 'UTC')", ^bucket, a.started_at), :history_bucket),
          executions: filter(count(a.id), not a.was_cached),
          failures: filter(count(a.id), a.result == "failed" and not a.was_cached),
          hits: filter(count(a.id), a.was_cached),
          cache_observations: filter(count(a.id), a.was_cached or (not is_nil(a.cache_key) and a.cache_key != "")),
          total: count(a.id),
          duration: filter(avg(a.duration_ms), not a.was_cached)
        }
      )
    )
  end

  defp cohort(action, opts) do
    query =
      from(a in Action,
        join: r in Run,
        on: r.id == a.once_run_id and r.project_id == ^action.project_id,
        where:
          a.project_id == ^action.project_id and a.history_id == ^action.history_id and
            not a.history_ambiguous and a.capability != "_phase"
      )

    case Keyword.get(opts, :branch) do
      branch when is_binary(branch) and branch != "" -> where(query, [_a, r], r.git_branch == ^branch)
      _ -> query
    end
  end

  defp period_days(opts) do
    until = Keyword.get(opts, :until, DateTime.utc_now())
    since = Keyword.get(opts, :since, DateTime.add(until, -30, :day))
    DateTime.diff(until, since, :day)
  end

  defp in_period(query, opts) do
    until = Keyword.get(opts, :until, DateTime.utc_now())
    since = Keyword.get(opts, :since, DateTime.add(until, -30, :day))
    since = if DateTime.diff(until, since, :day) > 90, do: DateTime.add(until, -90, :day), else: since
    where(query, [a], a.started_at >= ^since and a.started_at < ^until)
  end
end
