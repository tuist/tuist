defmodule Symptoms.Baselines do
  @moduledoc """
  The source baselines the pipeline injects as the `:baseline` option
  (`Symptoms.Sources.Source`), refreshed hourly by this Oban worker.

  - A source exporting `baselines(at_unix, opts)` returns `{:ok, %{entity =>
    baseline}}`; the map is stored per source (`Symptoms.Store.SourceBaseline`).
    A baseline that is a map keyed by stream names (`%{"trace.latency" =>
    ...}`) is looked up by stream; any other value serves every stream.
  - A source exporting `history(entity_key, stream, at_unix, opts)` (such as
    `Symptoms.Sources.PromMetrics`) gets, for each entity it reported in the
    last day, the windows of each stream in `history_streams/1`; the
    `:baseline` option then returns their hour-of-week values at the window
    (`Symptoms.Evidence.Statistics.hour_of_week_baseline/3`).
  - Otherwise the `:baseline` option returns the hour-of-week `observed`
    values of the entity's own stored windows for that stream.

  Baselines never update while a symptom on the entity is open (README
  "Deploys"): a refresh keeps the previous baseline of such an entity. A new
  entity without a baseline gets `nil`, so it counts only for novelty.
  History refreshes are atomic per source: any read error preserves its
  entire last good snapshot and computed time, returns the failed reads,
  audits the failure and fails the job. Successful empty reads are data.
  """
  use Oban.Worker, queue: :calibration, max_attempts: 1, unique: [period: 300]

  import Ecto.Query

  alias Symptoms.Evidence.Statistics
  alias Symptoms.Repo
  alias Symptoms.Store
  alias Symptoms.Store.SourceBaseline
  alias Symptoms.Store.StreamWindow

  @history_streams %{"metric" => ~w(metric.error_share metric.robust_residual metric.backlog_growth)}

  @impl Oban.Worker
  def perform(_job) do
    now = DateTime.utc_now()

    errors =
      for source <- Symptoms.Pipeline.sources(),
          {:error, reason} <- [refresh(source, now)],
          do: {source.name(), reason}

    if errors == [], do: :ok, else: {:error, {:baseline_refresh_failed, errors}}
  end

  @doc "The streams `history/4` is fetched for, per source name."
  @spec history_streams(String.t()) :: [String.t()]
  def history_streams(name), do: Map.get(@history_streams, name, [])

  @doc "Refreshes one source's stored baselines. Returns `:ok`, `:skipped` or `{:error, reason}`."
  @spec refresh(module(), DateTime.t()) :: :ok | :skipped | {:error, term()}
  def refresh(source, now) do
    Code.ensure_loaded(source)
    name = source.name()
    opts = Symptoms.Pipeline.source_opts(source, now)

    result =
      cond do
        function_exported?(source, :baselines, 2) -> source.baselines(DateTime.to_unix(now), opts)
        function_exported?(source, :history, 4) -> histories(source, name, now, opts)
        true -> :skipped
      end

    case result do
      {:ok, baselines} ->
        store(name, baselines, now)

      {:error, reason} ->
        Store.audit("baselines_failed", now, data: %{source: name, reason: inspect(reason)})
        {:error, reason}

      other ->
        other
    end
  end

  defp histories(source, name, now, opts) do
    entities = Store.expected_entities(name, now)

    {baselines, errors} =
      Enum.reduce(entities, {%{}, []}, fn entity, {baselines, errors} ->
        {streams, failed_reads} = entity_history(source, name, entity, now, opts)
        {Map.put(baselines, entity, streams), failed_reads ++ errors}
      end)

    # Publish a source snapshot only if every read succeeded. A partial
    # response is not an empty history and must not replace last good data
    # (or advance computed_at). A successful empty history remains valid.
    if errors == [], do: {:ok, baselines}, else: {:error, {:history_failed, Enum.reverse(errors)}}
  end

  defp entity_history(source, name, entity, now, opts) do
    Enum.reduce(history_streams(name), {%{}, []}, fn stream, {streams, errors} ->
      case source.history(entity.key, stream, DateTime.to_unix(now), opts) do
        {:ok, windows} ->
          {Map.put(streams, stream, {:history, Enum.map(windows, &history_window/1)}), errors}

        {:error, reason} ->
          {streams, [%{entity: entity, stream: stream, reason: reason} | errors]}
      end
    end)
  end

  defp history_window(%{window_start: start} = window) when is_integer(start),
    do: %{window | window_start: DateTime.from_unix!(start)}

  defp history_window(window), do: window

  defp store(name, baselines, now) do
    previous = load(name)
    tuples = Map.new(baselines, fn {entity, baseline} -> {Store.entity_tuple(entity), baseline} end)
    frozen = Store.frozen_tuples(Map.keys(previous))

    merged =
      Enum.reduce(frozen, tuples, fn tuple, acc ->
        case Map.fetch(previous, tuple) do
          {:ok, baseline} -> Map.put(acc, tuple, baseline)
          :error -> acc
        end
      end)

    Repo.insert_all(
      SourceBaseline,
      [%{source: name, data: :erlang.term_to_binary(merged), entities: map_size(merged), computed_at: now}],
      on_conflict: {:replace, [:data, :entities, :computed_at]},
      conflict_target: [:source]
    )

    if frozen != [], do: Store.audit("baselines_frozen", now, data: %{source: name, entities: length(frozen)})
    :ok
  end

  @doc "The stored baselines of a source, `%{entity_tuple => baseline}`."
  @spec load(String.t()) :: map()
  def load(name) do
    case Repo.one(from(b in SourceBaseline, where: b.source == ^name, select: b.data)) do
      nil -> %{}
      data -> :erlang.binary_to_term(data)
    end
  end

  @doc """
  The `:baseline` option for a source at window start `at`: `(stream,
  entity) -> baseline | nil` (see the module doc).
  """
  @spec lookup(String.t(), DateTime.t()) :: (String.t(), map() -> term())
  def lookup(name, at) do
    stored = load(name)

    fn stream, entity -> stored |> Map.get(Store.entity_tuple(entity)) |> pick(stream, entity, at) end
  end

  defp pick(nil, stream, entity, at), do: observed_history(entity, stream, at)

  defp pick(%{} = baseline, stream, _entity, at),
    do: if(stream_map?(baseline), do: by_stream(baseline[stream], at), else: baseline)

  defp pick(baseline, _stream, _entity, _at), do: baseline

  defp stream_map?(map), do: map_size(map) > 0 and Enum.all?(Map.keys(map), &is_binary/1)

  defp by_stream({:history, windows}, at), do: non_empty(Statistics.hour_of_week_baseline(windows, at))
  defp by_stream(baseline, _at), do: baseline

  defp observed_history(entity, stream, at) do
    with id when is_integer(id) <- Store.entity_id(entity) do
      earliest = DateTime.shift(at, week: -4)
      dow = Date.day_of_week(DateTime.to_date(at))

      from(w in StreamWindow,
        where:
          w.entity_id == ^id and w.source == ^stream and w.window_start >= ^earliest and w.window_start < ^at and
            not w.open_symptom and not is_nil(w.observed) and
            fragment("extract(isodow from ?)::int = ?", w.window_start, ^dow) and
            fragment("extract(hour from ?)::int = ?", w.window_start, ^at.hour),
        select: w.observed
      )
      |> Repo.all()
      |> non_empty()
    end
  end

  defp non_empty([]), do: nil
  defp non_empty(list), do: list
end
