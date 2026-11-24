defmodule Symptoms.Pipeline do
  @moduledoc """
  The window pipeline (README "Calibration", "Combining", "Deploys" and
  "Decision"). An Oban worker runs every minute with `window_seconds: 60`
  and every 5 minutes with `window_seconds: 300`; each job processes the
  windows that ended at least `:pipeline_delay_seconds` (default 60) ago and
  were not processed yet, at most 5 at a time.

  For one window, `run_window/3`:

  1. Calls `collect/2` on every configured source (`config :symptoms,
     :sources`) whose `window_seconds/0` matches, with the options in
     `config :symptoms, :source_opts` under the module. `{:unknown, entities}`
     marks those entities unknown; errors also mark expected entities
     unknown. Failed streams stay unknown until valid evidence for that
     stream arrives. Change sources' `changes/2` go to `Symptoms.Deploys`.
  2. Calibrates each record's raw statistic against its stream's stored null
     history (`Symptoms.Evidence.Calibration.p_value/4` and `e_value/2`) and
     stores it. An entity first seen less than `new_entity_minutes` ago
     counts only for novelty.
  3. Adds `Symptoms.Deploys.version_records/2`, combines per entity with the
     stored source weights (`Symptoms.Evidence.Combine.score/3`) and adds the
     deploy prior as a log term.
  4. Hands the scores to `Symptoms.Lifecycle.step/5`, atomically marking the
     entities' degraded run with its symptom (`open_symptom` and
     `symptom_id`) and completing the window in the lifecycle transaction.
     Completed windows are skipped on retry. The null history (`Symptoms.Store.history/5`) leaves a
     run out only while its symptom is open at board tier or above, or once
     it is labelled bad.
  5. Runs the attribute contrast (`Symptoms.Contrast`) on newly opened
     shared-cause roots.

  A record whose statistic reaches its source's `confirmed_statistic/0`
  (`Symptoms.Sources.Probes`) gets the e-value cap directly: a conformal
  p-value cannot fall below `1/(n+1)`, so ranking it would not reach the cap.

  The 5-minute pipeline waits `:pipeline_extra_delay_seconds` (default 90)
  longer than the 1-minute one, so `Symptoms.Sources.PulseErrors` sees its
  window after the errors table's ingest delay.

  A source in the 1-minute pipeline may also return 5-minute records (the
  trace latency on minutes that close a 5-minute window). They are
  calibrated and stored under their own window, and the 5-minute pipeline
  scores them with its own sources' records.

  Sources with windows longer than 5 minutes (the hourly span edges) run from
  the 1-minute pipeline 15 minutes after their window ends, for their side
  effects only.

  Only one job per `window_seconds` processes windows at a time
  (`run_pending/3`, a session advisory lock), so a run longer than its cron
  period never makes a second job process the same windows.
  """
  use Oban.Worker, queue: :pipeline, max_attempts: 1, unique: [period: 50, keys: [:window_seconds]]

  import Ecto.Query

  alias Symptoms.Deploys
  alias Symptoms.Evidence.Calibration
  alias Symptoms.Evidence.Combine
  alias Symptoms.Evidence.Record
  alias Symptoms.Lifecycle
  alias Symptoms.Repo
  alias Symptoms.Settings
  alias Symptoms.Store
  alias Symptoms.Store.DegradedRun
  alias Symptoms.Store.Entity
  alias Symptoms.Store.PipelineRun
  alias Symptoms.Store.SourceStatus
  alias Symptoms.Store.StreamWindow

  require Logger

  @max_catch_up 5
  @periodic_offset 900
  # Advisory lock class of `run_pending/3` (the second key is the window length).
  @lock_class 7_301

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"window_seconds" => window_seconds}}) do
    run_pending(window_seconds, DateTime.utc_now())
    :ok
  end

  @doc """
  Processes the pending windows of the pipeline of `window_seconds` at `now`
  (`run_window/3` options in `opts`), holding a session advisory lock keyed
  by `window_seconds` on one connection. A job that finds the lock held
  returns `:locked` without processing anything, so two jobs of one
  pipeline never process windows at the same time, even when a run outlasts
  its cron period. The lock goes with the connection if the node dies.
  """
  @spec run_pending(pos_integer(), DateTime.t(), keyword()) :: :ok | :locked
  def run_pending(window_seconds, now, opts \\ []) do
    with_lock(window_seconds, :try, fn ->
      Enum.each(pending_windows(window_seconds, now), &run_window(window_seconds, &1, Keyword.put(opts, :now, now)))

      if window_seconds == 60 do
        Deploys.reanchor(now)
        Deploys.resolve_intended(now)
      end

      :ok
    end)
  end

  defp with_lock(window_seconds, mode, fun) do
    Repo.checkout(fn ->
      locked =
        if mode == :try do
          %{rows: [[locked]]} = Repo.query!("SELECT pg_try_advisory_lock($1, $2)", [@lock_class, window_seconds])
          locked
        else
          Repo.query!("SELECT pg_advisory_lock($1, $2)", [@lock_class, window_seconds])
          true
        end

      if locked do
        try do
          fun.()
        after
          Repo.query!("SELECT pg_advisory_unlock($1, $2)", [@lock_class, window_seconds])
        end
      else
        :locked
      end
    end)
  end

  @doc """
  The window starts to process at `now`: from the window after the last
  finished one (or only the latest) up to the latest window that ended
  `:pipeline_delay_seconds` ago, at most #{@max_catch_up}.
  """
  @spec pending_windows(pos_integer(), DateTime.t()) :: [DateTime.t()]
  def pending_windows(window_seconds, now) do
    delay = Application.get_env(:symptoms, :pipeline_delay_seconds, 60)

    delay =
      if window_seconds > 60, do: delay + Application.get_env(:symptoms, :pipeline_extra_delay_seconds, 90), else: delay

    latest = div(DateTime.to_unix(now) - delay, window_seconds) * window_seconds - window_seconds

    last =
      Repo.one(from(r in PipelineRun, where: r.window_seconds == ^window_seconds, select: max(r.window_start)))

    first =
      case last do
        nil -> latest
        last -> max(DateTime.to_unix(last) + window_seconds, latest - (@max_catch_up - 1) * window_seconds)
      end

    if first > latest,
      do: [],
      else: Enum.map(first..latest//window_seconds, &Store.usec/1)
  end

  @doc """
  Processes one window. Options: `:now`, the decision time (default the
  window's end), and `:sources` (default the configured sources). Returns
  the `Symptoms.Lifecycle.step/4` summary plus `records`.
  """
  @spec run_window(pos_integer(), DateTime.t(), keyword()) :: map()
  def run_window(window_seconds, %DateTime{} = window_start, opts \\ []) do
    window_start = Store.usec(window_start)

    with_lock(window_seconds, :wait, fn ->
      case Repo.get_by(PipelineRun, window_seconds: window_seconds, window_start: window_start) do
        nil ->
          process_window(window_seconds, window_start, opts)

        run ->
          %{
            opened: [],
            reopened: [],
            resolved: [],
            charged_roots: [],
            revisions: 0,
            open_symptoms: %{},
            records: run.records
          }
      end
    end)
  end

  defp process_window(window_seconds, window_start, opts) do
    window_end = DateTime.shift(window_start, second: window_seconds)
    now = Keyword.get(opts, :now, window_end)
    sources = Keyword.get_lazy(opts, :sources, &sources/0)
    window = %{start: DateTime.to_unix(window_start), seconds: window_seconds}

    {collected, unknown} = collect_sources(sources, window, window_end, now)
    {records, longer} = Enum.split_with(collected, fn {_source, r} -> r.window_seconds == window_seconds end)

    store_longer(longer, now)
    rows = store_rows(calibrate(records, window_seconds, window_start, now))
    rows = rows ++ carried_rows(window_seconds, window_start, rows)

    version_rows = Deploys.version_records(window_seconds, window_start)

    Store.insert_windows(
      Enum.map(version_rows, &Map.merge(&1, %{open_symptom: false, symptom_id: nil, inserted_at: now}))
    )

    for {{source, stream}, records} <- Enum.group_by(collected, fn {source, record} -> {source.name(), record.source} end) do
      ids =
        records |> Enum.map(fn {_, record} -> Store.entity_id(record.entity) end) |> Enum.reject(&is_nil/1) |> Enum.uniq()

      Store.mark_evidence(ids, now, {source, stream})
    end

    # A healthy record must not overwrite another stream's failed read,
    # including failures reported by a different pipeline or earlier window.
    for {stream, entities} <- unknown, do: Store.mark_unknown(entities, now, stream)

    scores = score(rows ++ version_rows, window_start, now)

    result =
      Lifecycle.step(window_seconds, window_start, scores, now,
        complete: fn result ->
          mark_open_windows(result.open_symptoms, window_seconds, window_start)

          Repo.insert_all(
            PipelineRun,
            [
              %{
                window_seconds: window_seconds,
                window_start: window_start,
                records: length(rows),
                entities: map_size(scores),
                finished_at: DateTime.utc_now()
              }
            ],
            []
          )
        end
      )

    safely(fn -> Symptoms.Contrast.annotate(result.opened ++ result.reopened, now) end)
    Map.put(result, :records, length(rows))
  end

  defp collect_sources(sources, window, window_end, now) do
    unknown = :ets.new(:unknown_entities, [:set, :private])

    report = fn stream, entities ->
      :ets.insert(unknown, Enum.map(entities, &{{stream, Store.entity_tuple(&1)}, &1}))
    end

    try do
      own = Enum.filter(sources, &(&1.window_seconds() == window.seconds))
      records = Enum.flat_map(own, &collect(&1, window, window_end, now, report))
      if window.seconds == 60, do: run_periodic(sources, window_end, now, report)
      failures = Enum.group_by(:ets.tab2list(unknown), fn {{stream, _entity}, _} -> stream end, &elem(&1, 1))
      {records, failures}
    after
      :ets.delete(unknown)
    end
  end

  defp store_rows(rows) do
    open = Store.open_symptom_ids(Enum.map(rows, & &1.entity_id))

    rows =
      Enum.map(rows, &Map.merge(&1, %{open_symptom: Map.has_key?(open, &1.entity_id), symptom_id: open[&1.entity_id]}))

    Store.insert_windows(rows)
    rows
  end

  defp store_longer(longer, now) do
    longer
    |> Enum.group_by(fn {_source, r} -> {r.window_seconds, r.window_start} end)
    |> Enum.each(fn {{seconds, start}, records} -> store_rows(calibrate(records, seconds, Store.usec(start), now)) end)
  end

  # Records a shorter pipeline stored for this window (see the module doc).
  defp carried_rows(60, _window_start, _rows), do: []

  defp carried_rows(window_seconds, window_start, rows) do
    own = MapSet.new(rows, &{&1.entity_id, &1.source})

    from(w in StreamWindow,
      where: w.window_seconds == ^window_seconds and w.window_start == ^window_start and not is_nil(w.p)
    )
    |> Repo.all()
    |> Enum.reject(&MapSet.member?(own, {&1.entity_id, &1.source}))
    |> Enum.map(&(&1 |> Map.from_struct() |> Map.drop([:__meta__, :id])))
  end

  @doc "The configured source modules."
  @spec sources() :: [module()]
  def sources do
    disabled = Application.get_env(:symptoms, :disabled_sources, [])
    Application.get_env(:symptoms, :sources, []) -- disabled
  end

  @doc """
  The options a source gets at `now` (`Symptoms.Sources.Source`): the
  configured `config :symptoms, :source_opts` for the module, plus
  `:environment` (`config :symptoms, :environment`), `:entities` (what the
  source reported in the last day), `:baseline` (`Symptoms.Baselines.lookup/2`),
  `:known?`, `:unknown` (marks entities unknown), `:discovered` (adds them to
  the catalogue), `:now` (Unix seconds), `:put_edges`
  (`Symptoms.Store.put_edges/2` under the source's name),
  `:put_version_counts` (`Symptoms.Store.put_version_counts/2`), `:deploys`
  (deploys of the last 30 minutes), `:digest`
  (chronic Kubernetes reasons to the audit log, for the daily digest in
  `Symptoms.Board`) and `:novelty_disabled` (audited). Configured options win.
  """
  @spec source_opts(module(), DateTime.t(), DateTime.t() | nil) :: keyword()
  def source_opts(source, now, window_start \\ nil) do
    name = source.name()
    configured = :symptoms |> Application.get_env(:source_opts, []) |> Keyword.get(source, [])

    injected = [
      entities: Store.expected_entities(name, now),
      baseline: Symptoms.Baselines.lookup(name, window_start || now),
      known?: &(Store.entity_id(&1) != nil),
      unknown: fn stream, entities -> Store.mark_unknown(entities, now, stream) end,
      discovered: &Store.touch_source_entities(name, &1, now),
      now: DateTime.to_unix(now),
      environment: Application.get_env(:symptoms, :environment, "production"),
      put_edges: fn _hour, edges ->
        {:ok, _} = Store.put_edges(name, edges)
        :ok
      end,
      put_version_counts: fn counts ->
        {:ok, _} = Store.put_version_counts(name, counts)
        :ok
      end,
      deploys: Deploys.recent_deploys(now),
      digest: &Store.audit("k8s_chronic", now, data: %{items: &1}),
      novelty_disabled: &Store.audit("novelty_disabled", now, data: %{source: name, service: &1, unknown_keys: &2})
    ]

    Keyword.merge(injected, configured)
  end

  defp collect(source, window, window_end, now, report_unknown) do
    name = source.name()
    opts = source |> source_opts(now, DateTime.from_unix!(window.start)) |> Keyword.put(:unknown, report_unknown)
    record_changes(source, name, window, opts, now)

    case safely(fn -> source.collect(window, opts) end) do
      {:ok, records} ->
        source_status(name, now, window_end, nil)
        Store.touch_source_entities(name, Enum.map(records, & &1.entity), now)
        Enum.map(records, &{source, &1})

      {:unknown, entities} ->
        report_unknown.(name, entities)
        source_status(name, now, nil, "unknown")
        []

      {:error, reason} ->
        Logger.warning("symptoms: source #{name} failed: #{inspect(reason)}")
        report_unknown.(name, opts[:entities])
        source_status(name, now, nil, inspect(reason))
        []
    end
  end

  # Sources with windows longer than 5 minutes (hourly span edges) only have
  # side effects such as `put_edges`. They run from the 1-minute pipeline 15
  # minutes after their window ends; their records are not evidence.
  defp run_periodic(sources, window_end, now, report_unknown) do
    end_unix = DateTime.to_unix(window_end)

    for source <- sources,
        seconds = source.window_seconds(),
        seconds > 300,
        rem(end_unix - @periodic_offset, seconds) == 0 do
      collect(source, %{start: end_unix - seconds, seconds: seconds}, window_end, now, report_unknown)
    end
  end

  defp record_changes(source, name, window, opts, now) do
    Code.ensure_loaded(source)

    if function_exported?(source, :changes, 2) do
      store_changes(safely(fn -> source.changes(window, opts) end), name, now)
    end
  end

  defp store_changes({:ok, changes}, name, now), do: Deploys.record_changes(name, changes, now)

  defp store_changes(other, name, _now) do
    Logger.warning("symptoms: changes from #{name} failed: #{inspect(other)}")
  end

  defp safely(fun) do
    fun.()
  rescue
    error -> {:error, Exception.message(error)}
  end

  defp source_status(name, now, window_end, error) do
    {fields, replace} =
      if error,
        do: {%{last_error: String.slice(error, 0, 500), last_error_at: now}, [:last_error, :last_error_at]},
        else: {%{last_success_at: now, last_window_end: window_end}, [:last_success_at, :last_window_end]}

    Repo.insert_all(SourceStatus, [Map.merge(%{source: name, updated_at: now}, fields)],
      on_conflict: {:replace, [:updated_at | replace]},
      conflict_target: [:source]
    )
  end

  ## Calibration

  defp calibrate([], _window_seconds, _window_start, _now), do: []

  defp calibrate(records, window_seconds, window_start, now) do
    ids = records |> Enum.map(fn {_, %Record{entity: entity}} -> entity end) |> Store.resolve_entities(now)
    min_history = Settings.detector(:min_history)
    e_opts = [calibrator: Settings.detector(:calibrator), kappa: Settings.detector(:kappa)]

    records
    |> Enum.map(fn {source, record} -> {ids[Store.entity_tuple(record.entity)], record, confirmed(source)} end)
    |> Enum.group_by(fn {_id, record, _confirmed} -> record.source end)
    |> Enum.flat_map(fn {source, pairs} ->
      history =
        pairs |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Store.history(source, window_seconds, window_start, min_history)

      Enum.map(pairs, fn {id, record, confirmed} ->
        p = Calibration.p_value(record.statistic, window_start, history[id])
        row(id, record, window_seconds, window_start, p, e_value(record, p, confirmed, e_opts), now)
      end)
    end)
    |> Enum.uniq_by(&{&1.entity_id, &1.source})
  end

  defp e_value(record, _p, confirmed, _e_opts) when is_number(confirmed) and record.statistic >= confirmed,
    do: Calibration.cap()

  defp e_value(_record, p, _confirmed, e_opts), do: Calibration.e_value(p, e_opts)

  defp confirmed(source) do
    Code.ensure_loaded(source)
    if function_exported?(source, :confirmed_statistic, 0), do: source.confirmed_statistic()
  end

  defp row(id, record, window_seconds, window_start, p, e, now) do
    impact = record.impact || %{}

    %{
      entity_id: id,
      source: record.source,
      phenomenon: Atom.to_string(record.phenomenon),
      window_seconds: window_seconds,
      window_start: window_start,
      statistic: record.statistic * 1.0,
      p: p,
      e: e,
      observed: record.observed && record.observed * 1.0,
      expected: record.expected && record.expected * 1.0,
      n: record.n,
      impact_unit: impact[:unit],
      impact_rate: impact[:rate] && impact[:rate] * 1.0,
      examples: Enum.take(record.examples || [], 3),
      inserted_at: now
    }
  end

  ## Combining

  defp score([], _window_start, _now), do: %{}

  defp score(rows, window_start, now) do
    ids = rows |> Enum.map(& &1.entity_id) |> Enum.uniq()
    new_after = DateTime.shift(now, minute: -Settings.detector(:new_entity_minutes))
    new_ids = MapSet.new(Repo.all(from(e in Entity, where: e.id in ^ids and e.first_seen_at > ^new_after, select: e.id)))
    priors = Deploys.prior_terms(ids, window_start)
    weights = Settings.raw_weights()

    rows
    |> Enum.reject(&(MapSet.member?(new_ids, &1.entity_id) and &1.phenomenon != "novelty"))
    |> Enum.group_by(& &1.entity_id)
    |> Map.new(fn {id, entity_rows} ->
      records = Enum.map(entity_rows, &%{phenomenon: phenomenon(&1.phenomenon), source: &1.source, e: &1.e})
      combined = Combine.score(records, weights)

      impact =
        entity_rows
        |> Enum.filter(&(is_binary(&1.impact_unit) and is_number(&1.impact_rate)))
        |> Enum.max_by(& &1.impact_rate, fn -> nil end)

      {id,
       %{
         x: combined.log_evidence + Map.get(priors, id, 0.0),
         phenomena: combined.phenomena,
         impact_unit: impact && impact.impact_unit,
         impact_rate: impact && impact.impact_rate,
         examples: entity_rows |> Enum.flat_map(& &1.examples) |> Enum.uniq() |> Enum.take(3)
       }}
    end)
  end

  defp phenomenon(name), do: String.to_existing_atom(name)

  # The degraded run that led to an open symptom belongs to it: the null
  # history leaves it out while the symptom is open at board tier or above,
  # or once it is labelled bad.
  defp mark_open_windows(open_symptoms, window_seconds, window_start) do
    Enum.each(open_symptoms, fn {entity_id, symptom_id} ->
      since =
        Repo.one(
          from(d in DegradedRun,
            where: d.entity_id == ^entity_id and d.window_seconds == ^window_seconds,
            select: d.since
          )
        ) || window_start

      Repo.update_all(
        from(w in StreamWindow,
          where:
            w.entity_id == ^entity_id and w.window_seconds == ^window_seconds and w.window_start <= ^window_start and
              w.window_start >= ^since
        ),
        set: [open_symptom: true, symptom_id: symptom_id]
      )
    end)
  end
end
