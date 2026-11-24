defmodule Symptoms.FakeSource do
  @moduledoc """
  A source driven by the test process: `collect/2` calls the function in
  `Process.put(:fake_source, fun)` with the window (the pipeline calls
  sources in the caller's process). `records/3` builds one error record per
  entity with the given statistic.
  """
  @behaviour Symptoms.Sources.Source

  alias Symptoms.Evidence.Record

  @source "fake.errors"

  def source, do: @source

  @impl true
  def name, do: "fake"

  @impl true
  def window_seconds, do: 60

  @impl true
  def collect(window, opts) do
    case Process.get(:fake_source, fn _ -> {:ok, []} end) do
      fun when is_function(fun, 2) -> fun.(window, opts)
      fun -> fun.(window)
    end
  end

  def records(window, entities, statistic, rate \\ 50.0) do
    for entity <- entities do
      %Record{
        entity: entity,
        phenomenon: :request_errors,
        source: @source,
        window_start: DateTime.from_unix!(window.start),
        window_seconds: 60,
        statistic: statistic,
        e: 0.0,
        impact: %{unit: "failed_requests_per_min", rate: rate}
      }
    end
  end

  @doc """
  Seeds each entity's null history: the same hour of week in each of the 3
  previous weeks, every minute, 180 windows with statistics
  `rem(37 i, 100) / 100` (spread over 0.00–0.99). The entities enter the
  catalogue 30 days before `at`, so they are not new.
  """
  def seed_history(entities, %DateTime{} = at) do
    hour = %{at | minute: 0, second: 0, microsecond: {0, 6}}
    ids = Symptoms.Store.resolve_entities(entities, DateTime.shift(at, day: -30))

    rows =
      for entity <- entities,
          week <- 1..3,
          minute <- 0..59 do
        i = (week - 1) * 60 + minute

        %{
          entity_id: ids[Symptoms.Store.entity_tuple(entity)],
          source: @source,
          phenomenon: "request_errors",
          window_seconds: 60,
          window_start: DateTime.shift(hour, week: -1 * week, minute: minute),
          statistic: rem(37 * i, 100) / 100,
          e: 1.0,
          open_symptom: false,
          examples: [],
          inserted_at: at
        }
      end

    Symptoms.Store.insert_windows(rows)
    ids
  end
end
