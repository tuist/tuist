defmodule Symptoms.Store do
  @moduledoc """
  The evaluator's detection state in its own database (README "Systems of
  record"). This module is the boundary sources use; the pipeline, deploy and
  label code use the rest.

  ## For sources

  - `put_edges/2`: replace the caller → callee edges a source knows (span
    parent edges, resource clients), used by `Symptoms.Evidence.Roots`.
  - `put_version_counts/2`: per-version request and error counts, for the
    deploy version-against-version tests (`Symptoms.Deploys`).
  - `put_aliases/2`: other keys that resolve to one entity (shared resources
    such as Postgres poolers).
  - `baseline_anchor/1` and `baselines_frozen?/1`: where a source's baseline
    for an entity starts, and whether it must not move.

  ## Entities

  An entity is a map with `environment` (default `"production"`), `service`,
  `kind` and `key`, and optionally `family` (default
  `"<environment>/<service>/<kind>"`), with atom or string keys. A key that
  is an alias of another entity of the same environment and kind resolves to
  that entity.
  """

  import Ecto.Query

  alias Symptoms.Repo
  alias Symptoms.Store.AuditEvent
  alias Symptoms.Store.Change
  alias Symptoms.Store.DegradedRun
  alias Symptoms.Store.Edge
  alias Symptoms.Store.Entity
  alias Symptoms.Store.Label
  alias Symptoms.Store.Reanchor
  alias Symptoms.Store.SourceEntity
  alias Symptoms.Store.StreamWindow
  alias Symptoms.Store.Symptom
  alias Symptoms.Store.VersionCount

  @type entity :: map()
  @type entity_tuple :: {String.t(), String.t(), String.t(), String.t()}

  ## Source API

  @doc """
  Replaces every edge previously written by `source` with `edges`, a list of
  `{caller, callee}` entity maps (see the module doc) or maps with `:caller`
  and `:callee` (the shape `Symptoms.Sources.PulseSpanEdges` builds; other
  keys are ignored). Unknown entities enter
  the catalogue. Call it whenever the source's edge table refreshes (hourly
  for Pulse span parent edges); edges of other sources are untouched.
  Returns `{:ok, count}`.
  """
  @spec put_edges(String.t(), [{entity(), entity()}]) :: {:ok, non_neg_integer()}
  def put_edges(source, edges) when is_binary(source) and is_list(edges) do
    now = DateTime.utc_now()
    edges = Enum.map(edges, &edge_pair/1)
    ids = resolve_entities(Enum.flat_map(edges, fn {a, b} -> [a, b] end), now)

    rows =
      edges
      |> Enum.map(fn {a, b} -> {ids[entity_tuple(a)], ids[entity_tuple(b)]} end)
      |> Enum.reject(fn {a, b} -> a == b end)
      |> Enum.uniq()
      |> Enum.map(fn {a, b} -> %{source: source, caller_id: a, callee_id: b, updated_at: now} end)

    Repo.transaction(fn ->
      Repo.delete_all(from(e in Edge, where: e.source == ^source))
      rows |> Enum.chunk_every(5_000) |> Enum.each(&Repo.insert_all(Edge, &1))
    end)

    {:ok, length(rows)}
  end

  defp edge_pair({caller, callee}), do: {caller, callee}
  defp edge_pair(%{} = edge), do: {fetch(edge, :caller), fetch(edge, :callee)}

  @doc """
  Stores per-version counts. Each count is a map with `entity`, `version`
  (the `service.version` string), `window_start` (`DateTime`),
  `window_seconds`, `errors`, `total` and optionally `p95_ms` and
  `histogram` (`%{bucket => count}`, for the latency version test). A count for a
  window already stored replaces it. Returns `{:ok, count}`.

  `Symptoms.Deploys` compares a deploy's new version against the version it
  replaced on the entities the deploy touched, so sources should report every
  version that served traffic, not only the newest.
  """
  @spec put_version_counts(String.t(), [map()]) :: {:ok, non_neg_integer()}
  def put_version_counts(_source, counts) when is_list(counts) do
    ids = resolve_entities(Enum.map(counts, &fetch(&1, :entity)), DateTime.utc_now())

    rows =
      Enum.map(counts, fn count ->
        %{
          entity_id: ids[entity_tuple(fetch(count, :entity))],
          version: to_string(fetch(count, :version)),
          window_start: usec(fetch(count, :window_start)),
          window_seconds: fetch(count, :window_seconds),
          errors: fetch(count, :errors),
          total: fetch(count, :total),
          p95_ms: if(p95 = fetch(count, :p95_ms), do: p95 * 1.0),
          histogram: if(histogram = fetch(count, :histogram), do: Map.new(histogram, fn {b, c} -> {to_string(b), c} end))
        }
      end)

    Repo.insert_all(VersionCount, rows,
      on_conflict: {:replace, [:errors, :total, :p95_ms, :histogram]},
      conflict_target: [:entity_id, :version, :window_seconds, :window_start]
    )

    {:ok, length(rows)}
  end

  @doc """
  Sets the aliases of `entity`: other keys of the same environment and kind
  that resolve to it from now on. History stored under an alias before it
  was declared stays with the alias's own row. Returns `{:ok, entity_id}`.
  """
  @spec put_aliases(entity(), [String.t()]) :: {:ok, integer()}
  def put_aliases(entity, aliases) when is_list(aliases) do
    id = Map.fetch!(resolve_entities([entity], DateTime.utc_now()), entity_tuple(entity))
    Repo.update_all(from(e in Entity, where: e.id == ^id), set: [aliases: Enum.uniq(aliases)])
    {:ok, id}
  end

  @doc """
  The latest accepted re-anchor of `entity`: `%{version, change_ref,
  anchored_at}`, or `nil`. A source's baseline for the entity should use only
  the anchored version from `anchored_at` on, once one exists.
  """
  @spec baseline_anchor(entity()) :: map() | nil
  def baseline_anchor(entity) do
    with id when is_integer(id) <- entity_id(entity) do
      Repo.one(
        from(r in Reanchor,
          join: c in Change,
          on: c.id == r.change_id,
          where: r.entity_id == ^id and r.status == "accepted",
          order_by: [desc: r.at],
          limit: 1,
          select: %{version: r.to_version, change_ref: c.ref, anchored_at: r.at}
        )
      )
    end
  end

  @doc """
  Whether a symptom on `entity` is open: while it is, the entity's baselines
  must not update (README "Deploys"). Sources check it before rolling a
  baseline forward.
  """
  @spec baselines_frozen?(entity() | integer()) :: boolean()
  def baselines_frozen?(id) when is_integer(id), do: open_symptom_entities([id]) != MapSet.new()

  def baselines_frozen?(entity) do
    case entity_id(entity) do
      nil -> false
      id -> baselines_frozen?(id)
    end
  end

  @doc """
  Records that `source` reported entities (maps) at `at`; they enter the
  catalogue if new. `expected_entities/2` returns them for a day.
  """
  @spec touch_source_entities(String.t(), [entity()], DateTime.t()) :: :ok
  def touch_source_entities(_source, [], _at), do: :ok

  def touch_source_entities(source, entities, at) do
    rows =
      entities
      |> resolve_entities(at)
      |> Map.values()
      |> Enum.uniq()
      |> Enum.map(&%{source: source, entity_id: &1, last_seen_at: at})

    rows
    |> Enum.chunk_every(5_000)
    |> Enum.each(
      &Repo.insert_all(SourceEntity, &1,
        on_conflict: {:replace, [:last_seen_at]},
        conflict_target: [:source, :entity_id]
      )
    )
  end

  @doc """
  The non-retired entities `source` reported in the day before `at`, as maps
  with `environment`, `service`, `kind` and `key`: the source's `:entities`
  option.
  """
  @spec expected_entities(String.t(), DateTime.t()) :: [map()]
  def expected_entities(source, at) do
    since = DateTime.shift(at, day: -1)

    Repo.all(
      from(s in SourceEntity,
        join: e in Entity,
        on: e.id == s.entity_id,
        where: s.source == ^source and s.last_seen_at >= ^since and is_nil(e.retired_at),
        order_by: [e.service, e.kind, e.key],
        select: %{environment: e.environment, service: e.service, kind: e.kind, key: e.key}
      )
    )
  end

  @doc "The entity tuples among `tuples` with an open symptom."
  @spec frozen_tuples([entity_tuple()]) :: [entity_tuple()]
  def frozen_tuples([]), do: []

  def frozen_tuples(tuples) do
    keys = tuples |> Enum.map(&elem(&1, 3)) |> Enum.uniq()

    from(s in Symptom,
      join: e in Entity,
      on: e.id == s.entity_id,
      where: s.state == "open" and e.key in ^keys,
      select: {e.environment, e.service, e.kind, e.key}
    )
    |> Repo.all()
    |> Enum.uniq()
    |> Enum.filter(&(&1 in tuples))
  end

  ## Entities

  @doc "Normalizes an entity map (see the module doc)."
  @spec normalize_entity(entity()) :: %{
          environment: String.t(),
          service: String.t(),
          kind: String.t(),
          key: String.t(),
          family: String.t()
        }
  def normalize_entity(entity) do
    environment = to_string(fetch(entity, :environment) || "production")
    service = to_string(fetch(entity, :service))
    kind = to_string(fetch(entity, :kind))

    %{
      environment: environment,
      service: service,
      kind: kind,
      key: to_string(fetch(entity, :key)),
      family: to_string(fetch(entity, :family) || "#{environment}/#{service}/#{kind}")
    }
  end

  @doc "The `{environment, service, kind, key}` identity of an entity map."
  @spec entity_tuple(entity()) :: entity_tuple()
  def entity_tuple(entity) do
    e = normalize_entity(entity)
    {e.environment, e.service, e.kind, e.key}
  end

  @doc "The id of an existing entity (or the entity it is an alias of), or `nil`."
  @spec entity_id(entity()) :: integer() | nil
  def entity_id(entity) do
    {environment, service, kind, key} = entity_tuple(entity)

    Repo.one(
      from(e in Entity,
        where:
          e.environment == ^environment and e.kind == ^kind and
            ((e.service == ^service and e.key == ^key) or fragment("? = ANY(?)", ^key, e.aliases)),
        order_by: [asc: fragment("? = ANY(?)", ^key, e.aliases)],
        limit: 1,
        select: e.id
      )
    )
  end

  @doc """
  Upserts entities seen at `at` and returns `%{entity_tuple => id}`. Aliases
  resolve to their entity; new entities get `first_seen_at: at`.
  """
  @spec resolve_entities([entity()], DateTime.t()) :: %{optional(entity_tuple()) => integer()}
  def resolve_entities([], _at), do: %{}

  def resolve_entities(entities, at) do
    normalized = entities |> Enum.map(&normalize_entity/1) |> Enum.uniq_by(&{&1.environment, &1.service, &1.kind, &1.key})
    aliased = aliased_ids(normalized)

    rows =
      for e <- normalized, not Map.has_key?(aliased, {e.environment, e.service, e.kind, e.key}) do
        e
        |> Map.merge(%{first_seen_at: at, last_seen_at: at, inserted_at: at, updated_at: at})
        |> Map.put(:aliases, [])
      end

    inserted =
      rows
      |> Enum.chunk_every(2_000)
      |> Enum.flat_map(fn chunk ->
        {_, returned} =
          Repo.insert_all(Entity, chunk,
            on_conflict:
              from(e in Entity,
                update: [set: [last_seen_at: fragment("GREATEST(?, EXCLUDED.last_seen_at)", e.last_seen_at)]]
              ),
            conflict_target: [:environment, :service, :kind, :key],
            returning: [:id, :environment, :service, :kind, :key]
          )

        returned
      end)

    Map.merge(aliased, Map.new(inserted, &{{&1.environment, &1.service, &1.kind, &1.key}, &1.id}))
  end

  defp aliased_ids(normalized) do
    keys = normalized |> Enum.map(& &1.key) |> Enum.uniq()

    candidates =
      Repo.all(
        from(e in Entity,
          where: fragment("? && ?", e.aliases, ^keys),
          select: {e.id, e.environment, e.kind, e.aliases}
        )
      )

    for e <- normalized,
        {id, environment, kind, aliases} <- candidates,
        environment == e.environment and kind == e.kind and e.key in aliases,
        into: %{},
        do: {{e.environment, e.service, e.kind, e.key}, id}
  end

  @doc "Marks entities unknown, optionally for a specific stream; they enter the catalogue if new."
  @spec mark_unknown([entity()], DateTime.t(), String.t() | nil) :: :ok
  def mark_unknown(entities, at, stream \\ nil)
  def mark_unknown([], _at, _stream), do: :ok

  def mark_unknown(entities, at, stream) do
    ids = entities |> resolve_entities(at) |> Map.values()

    if stream do
      Repo.update_all(from(e in Entity, where: e.id in ^ids),
        set: [
          unknown_streams:
            dynamic([e], fragment("array_append(array_remove(?, ?), ?)", e.unknown_streams, ^stream, ^stream))
        ]
      )
    end

    {_, newly_unknown} =
      Repo.update_all(from(e in Entity, where: e.id in ^ids and not e.unknown, select: e.id),
        set: [unknown: true, unknown_since: at]
      )

    Repo.delete_all(from(d in DegradedRun, where: d.entity_id in ^newly_unknown))

    :ok
  end

  @doc "Records evidence; scoped reads clear only their source and stream's failures."
  @spec mark_evidence([integer()], DateTime.t(), {String.t(), String.t()} | nil) :: :ok
  def mark_evidence(ids, at, scope \\ nil)

  def mark_evidence(ids, at, {source, stream}) do
    Repo.update_all(from(e in Entity, where: e.id in ^ids),
      set: [
        last_evidence_at: at,
        unknown_streams:
          dynamic([e], fragment("array_remove(array_remove(?, ?), ?)", e.unknown_streams, ^source, ^stream))
      ]
    )

    Repo.update_all(from(e in Entity, where: e.id in ^ids and e.unknown_streams == []),
      set: [unknown: false, unknown_since: nil]
    )

    :ok
  end

  def mark_evidence(ids, at, nil) do
    Repo.update_all(from(e in Entity, where: e.id in ^ids),
      set: [last_evidence_at: at, unknown: false, unknown_since: nil, unknown_streams: []]
    )

    :ok
  end

  @doc "Retires entities (maps) whose code a deploy deleted."
  @spec retire_entities([entity()], DateTime.t()) :: :ok
  def retire_entities([], _at), do: :ok

  def retire_entities(entities, at) do
    ids = entities |> Enum.map(&entity_id/1) |> Enum.reject(&is_nil/1)
    Repo.update_all(from(e in Entity, where: e.id in ^ids and is_nil(e.retired_at)), set: [retired_at: at])
    :ok
  end

  @doc "All edges as `{caller_id, callee_id}`."
  @spec edges() :: [{integer(), integer()}]
  def edges do
    Repo.all(from(e in Edge, distinct: true, select: {e.caller_id, e.callee_id}))
  end

  @doc "Entity ids with an open symptom (as its entity or a merged member's entity)."
  @spec open_symptom_entities([integer()]) :: MapSet.t()
  def open_symptom_entities(ids) do
    ids |> open_symptom_ids(~w(detected intended)) |> Map.keys() |> MapSet.new()
  end

  @doc """
  `%{entity_id => symptom_id}` for the entities among `ids` with an open
  symptom of one of `kinds` (default detected only: an "intended?" deploy
  symptom is not a degraded run, so stream windows are never tagged with
  it): the one with the highest `max_tier`, then the earliest opened.
  """
  @spec open_symptom_ids([integer()], [String.t()]) :: %{optional(integer()) => String.t()}
  def open_symptom_ids(ids, kinds \\ ["detected"]) do
    rank = %{"audit" => 0, "board" => 1, "page" => 2}

    from(s in Symptom,
      where: s.state == "open" and s.entity_id in ^ids and s.kind in ^kinds,
      select: {s.entity_id, s.id, s.max_tier, s.opened_at}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0))
    |> Map.new(fn {id, rows} ->
      {_, symptom_id, _, _} =
        Enum.min_by(rows, fn {_, _, tier, at} -> {-rank[tier], DateTime.to_unix(at, :microsecond)} end)

      {id, symptom_id}
    end)
  end

  ## Stream history

  @doc """
  The null-history candidates for each entity's stream `(source,
  window_seconds)` at `at`: windows of the trailing 28 days at the same hour
  of week, in the shape `Symptoms.Evidence.Calibration.null_history/3`
  takes. Left out are only windows of a degraded run whose symptom
  (`symptom_id`) was labelled `bad`, or is still open (or merged) and reached
  board tier or above, and the windows of the entity's current degraded run
  in this pipeline, which has not crossed yet and must not dilute its own
  evidence (it returns once the run ends). An entity with fewer than
  `min_history` own windows borrows its family's windows of the same source
  (README "Inputs": a new entity borrows its service family's baseline).
  Returns `%{entity_id => [window]}`.
  """
  @spec history([integer()], String.t(), pos_integer(), DateTime.t(), non_neg_integer()) :: %{
          optional(integer()) => [map()]
        }
  def history(entity_ids, source, window_seconds, at, min_history) do
    own =
      entity_ids
      |> history_query(source, window_seconds, at)
      |> Repo.all()
      |> Enum.group_by(& &1.entity_id, &Map.delete(&1, :entity_id))

    short = Enum.filter(entity_ids, &(length(Map.get(own, &1, [])) < min_history))
    Map.merge(Map.new(entity_ids, &{&1, Map.get(own, &1, [])}), family_history(short, source, window_seconds, at))
  end

  @doc """
  The query behind `history/5`. The same hour of week of the trailing 28
  days is up to 5 explicit ranges, `[hour_start − 7k days, hour_end − 7k
  days)` for k = 0..4 clipped to `[at − 28 days, at)`, so the
  `(entity_id, source, window_seconds, window_start)` index serves each one
  and no other hour is read.
  """
  @spec history_query([integer()], String.t(), pos_integer(), DateTime.t()) :: Ecto.Query.t()
  def history_query(entity_ids, source, window_seconds, at) do
    in_hours = hour_of_week_filter(at)

    from(w in StreamWindow,
      left_join: d in DegradedRun,
      on: d.entity_id == w.entity_id and d.window_seconds == w.window_seconds,
      left_join: s in Symptom,
      on: s.id == w.symptom_id,
      left_join: l in Label,
      on: l.symptom_id == w.symptom_id and l.outcome == "bad",
      where: w.entity_id in ^entity_ids and w.source == ^source and w.window_seconds == ^window_seconds,
      where: ^in_hours,
      where: is_nil(d.since) or w.window_start < d.since,
      where: is_nil(l.symptom_id),
      where: is_nil(s.id) or s.state not in ["open", "merged"] or s.max_tier not in ["board", "page"],
      select: %{entity_id: w.entity_id, window_start: w.window_start, statistic: w.statistic}
    )
  end

  defp hour_of_week_filter(at) do
    Enum.reduce(hour_of_week_ranges(at), dynamic(false), fn {from, to}, acc ->
      dynamic([w], ^acc or (w.window_start >= ^from and w.window_start < ^to))
    end)
  end

  defp hour_of_week_ranges(at) do
    at = usec(at)
    earliest = DateTime.shift(at, week: -4)
    hour_start = %{at | minute: 0, second: 0, microsecond: {0, 6}}

    for k <- 0..4,
        start = DateTime.shift(hour_start, week: -1 * k),
        from = Enum.max([start, earliest], DateTime),
        to = Enum.min([DateTime.shift(start, hour: 1), at], DateTime),
        DateTime.before?(from, to),
        do: {from, to}
  end

  defp family_history([], _source, _window_seconds, _at), do: %{}

  defp family_history(entity_ids, source, window_seconds, at) do
    families = Map.new(Repo.all(from(e in Entity, where: e.id in ^entity_ids, select: {e.id, e.family})))
    members = Repo.all(from(e in Entity, where: e.family in ^Map.values(families), select: {e.id, e.family}))

    windows =
      members
      |> Enum.map(&elem(&1, 0))
      |> history_query(source, window_seconds, at)
      |> Repo.all()

    family_of = Map.new(members)
    by_family = Enum.group_by(windows, &family_of[&1.entity_id], &Map.delete(&1, :entity_id))
    Map.new(entity_ids, &{&1, Map.get(by_family, families[&1], [])})
  end

  @doc "Inserts stream windows (maps of `Symptoms.Store.StreamWindow` fields), replacing a stored window."
  @spec insert_windows([map()]) :: :ok
  def insert_windows(rows) do
    rows
    |> Enum.chunk_every(2_000)
    |> Enum.each(
      &Repo.insert_all(StreamWindow, &1,
        on_conflict: {:replace_all_except, [:id]},
        conflict_target: [:entity_id, :source, :window_seconds, :window_start]
      )
    )
  end

  ## Audit

  @doc "Appends to the audit log."
  @spec audit(String.t(), DateTime.t(), keyword()) :: :ok
  def audit(kind, at, opts \\ []) do
    Repo.insert_all(AuditEvent, [
      %{
        kind: kind,
        at: at,
        entity_id: opts[:entity_id],
        symptom_id: opts[:symptom_id],
        data: Map.new(Keyword.get(opts, :data, %{}))
      }
    ])

    :ok
  end

  @doc "A `DateTime` (or Unix seconds) with microsecond precision, as every timestamp column stores."
  @spec usec(DateTime.t() | integer()) :: DateTime.t()
  def usec(unix) when is_integer(unix), do: unix |> DateTime.from_unix!(:second) |> usec()
  def usec(%DateTime{microsecond: {us, _}} = at), do: %{at | microsecond: {us, 6}}

  defp fetch(map, key) when is_map(map), do: Map.get(map, key, Map.get(map, Atom.to_string(key)))
end
