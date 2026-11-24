defmodule Symptoms.CalibrateDbTest do
  use Symptoms.DataCase
  use Mimic

  alias Symptoms.Calibrate
  alias Symptoms.Decision.Platt
  alias Symptoms.Log
  alias Symptoms.Settings
  alias Symptoms.Store
  alias Symptoms.Store.Label
  alias Symptoms.Store.SourceBaseline
  alias Symptoms.Store.Symptom
  alias Symptoms.Store.Threshold

  @now ~U[2026-11-16 10:00:00.000000Z]

  defmodule HistorySource do
    @moduledoc false
    def name, do: "metric"
    def history(_key, stream, _at, _opts), do: Process.get({__MODULE__, stream})
  end

  test "price calibration excludes unknown costs but keeps known zero" do
    # Twelve day roots fill the four-week budget (3/week). Unknown roots
    # must not become a thirteenth zero-cost sample that lowers the price.
    # Stub the stored rows so this also tests nullable reads independently
    # of the migration adding nullable root_scores.impact.
    known =
      for i <- 1..12 do
        %{root_key: "known:#{i}", symptom_id: nil, window_seconds: 60, window_start: @now, score: 9.0, impact: 100.0}
      end

    unknown = %{hd(known) | root_key: "unknown", impact: nil}
    current = Settings.prices()
    expect(Repo, :all, fn _ -> known ++ [unknown] end)
    assert Calibrate.update_prices(@now) == current

    expect(Repo, :all, fn _ -> known ++ [%{unknown | impact: 0.0}] end)
    assert Calibrate.update_prices(@now).day_price == 1.0e-9
  end

  test "failed baseline histories preserve the complete last good snapshot and return errors" do
    route = %{service: "tuist-server", kind: "route", key: "GET /baseline"}
    Store.touch_source_entities("metric", [route], @now)
    streams = Symptoms.Baselines.history_streams("metric")
    old = [%{window_start: DateTime.to_unix(DateTime.shift(@now, week: -1)), statistic: 10.0}]
    for stream <- streams, do: Process.put({HistorySource, stream}, {:ok, old})
    assert :ok = Symptoms.Baselines.refresh(HistorySource, @now)
    previous = Symptoms.Baselines.load("metric")
    snapshot = Repo.one!(SourceBaseline)
    assert Symptoms.Baselines.lookup("metric", @now).(hd(streams), route) == [10.0]

    for failures <- [streams, [hd(streams)]] do
      for stream <- streams do
        reply = if stream in failures, do: {:error, :timeout}, else: {:ok, []}
        Process.put({HistorySource, stream}, reply)
      end

      assert {:error, {:history_failed, errors}} =
               Symptoms.Baselines.refresh(HistorySource, DateTime.shift(@now, hour: 1))

      assert length(errors) == length(failures)
      assert Symptoms.Baselines.load("metric") == previous
      assert Repo.one!(SourceBaseline) == snapshot
    end

    for stream <- streams, do: Process.put({HistorySource, stream}, {:ok, []})
    assert :ok = Symptoms.Baselines.refresh(HistorySource, DateTime.shift(@now, hour: 1))
    assert Symptoms.Baselines.load("metric") != previous
    assert Symptoms.Baselines.lookup("metric", @now).(hd(streams), route) == nil
  end

  defp entity(key) do
    entity = %{service: "tuist-server", kind: "route", key: key}
    Store.resolve_entities([entity], DateTime.shift(@now, day: -30))
    Store.entity_id(entity)
  end

  defp symptom do
    Repo.insert!(%Symptom{
      id: Log.uuid7(@now),
      symptom_key: "k",
      root_key: "60:entity:1",
      phenomenon: "request_errors",
      state: "resolved",
      tier: "page",
      max_tier: "page",
      opened_at: DateTime.shift(@now, day: -2)
    })
  end

  # `es` are the e-values of consecutive windows starting a day before now.
  defp series(id, seconds, es, symptom_id \\ nil) do
    start = DateTime.shift(@now, day: -1)

    Store.insert_windows(
      for {e, i} <- Enum.with_index(es) do
        %{
          entity_id: id,
          source: "fake.errors",
          phenomenon: "request_errors",
          window_seconds: seconds,
          window_start: DateTime.shift(start, second: i * seconds),
          statistic: 0.0,
          e: e,
          examples: [],
          open_symptom: symptom_id != nil,
          symptom_id: symptom_id,
          inserted_at: @now
        }
      end
    )
  end

  test "Platt is fitted per pipeline, centred on that pipeline's h" do
    # h = 6 on 1-minute windows (the default) and 4 on 5-minute windows.
    Repo.insert!(%Threshold{
      h: 4.0,
      crossings: 0,
      entity_days: 1.0,
      rate: 0.0,
      window_seconds: 300,
      inserted_at: @now
    })

    # Per pipeline, 20 independent labels at that pipeline's h, half bad and
    # half fine. At the prior (a, b) = (−h, 1) every sample has p = σ(0) =
    # 1/2, so the log-likelihood gradient Σ (y − p)(1, s) is 0 and so is the
    # penalty's: the fit is exactly the prior, and P(h) = 1/2. A fit pooled
    # across pipelines or centred on the other pipeline's h is not.
    for {seconds, h} <- [{60, 6.0}, {300, 4.0}], i <- 1..20 do
      sym = %{symptom() | id: Log.uuid7(@now), root_key: "#{seconds}:entity:#{i}"}
      Repo.insert!(sym)

      Repo.insert!(%Label{
        symptom_id: sym.id,
        outcome: if(rem(i, 2) == 0, do: "bad", else: "fine"),
        independent: true,
        weight: 1.0,
        score: h,
        max_tier: "board",
        missed: false,
        confirmed_at: @now
      })
    end

    Calibrate.weekly_platt(@now)

    for {seconds, h} <- [{60, 6.0}, {300, 4.0}] do
      params = Settings.platt(seconds)
      assert_in_delta params.a, -h, 1.0e-9
      assert_in_delta params.b, 1.0, 1.0e-9
      assert_in_delta Platt.probability(params, h), 0.5, 1.0e-9
    end
  end

  test "the refit gate does not pass vacuously without independent bad labels" do
    # Only fine labels: the bounded refit lowers the intercept by 0.5 (fewer
    # pages), so recall 0 ≥ 0 and false pages ≤ would pass with no bad
    # symptom to lose. With fewer than :min_refit_bads (3) the gate rejects
    # and the prior stays in force.
    for i <- 1..5 do
      sym = %{symptom() | id: Log.uuid7(@now), root_key: "60:entity:#{i}"}
      Repo.insert!(sym)

      Repo.insert!(%Label{
        symptom_id: sym.id,
        outcome: "fine",
        independent: true,
        weight: 1.0,
        score: 7.0,
        max_tier: "page",
        missed: false,
        confirmed_at: @now
      })

      Repo.insert!(%Symptoms.Store.RootScore{
        root_key: sym.root_key,
        window_seconds: 60,
        window_start: DateTime.shift(@now, day: -1, minute: i),
        x: 2.0,
        score: 7.0,
        impact: 50.0,
        symptom_id: sym.id
      })
    end

    assert %{60 => {:rejected, %{reason: :too_few_bads, bads: 0}}} = Calibrate.refit(@now)
    assert Settings.platt(60) == Platt.prior(6.0)
  end

  test "threshold replay counts the same openings and reopenings as the live lifecycle" do
    cap = :math.log(20)

    for {quiet, case_index} <- Enum.with_index([0.0, -0.01]) do
      xs = [cap] ++ List.duplicate(quiet, 5) ++ [cap]
      choice = Symptoms.Evidence.Threshold.choose([xs ++ List.duplicate(0.0, 1433)], 1.0)

      for {h, expected} <- [{cap, 2}, {choice.h, 1}] do
        Repo.insert!(%Threshold{
          h: h,
          crossings: 0,
          entity_days: 1.0,
          rate: 0.0,
          window_seconds: 60,
          inserted_at: DateTime.shift(@now, second: case_index * 2 + 2 - expected)
        })

        id = entity("GET /replay/#{case_index}/#{expected}")

        actual =
          xs
          |> Enum.with_index()
          |> Enum.map(fn {x, minute} ->
            at = DateTime.shift(@now, minute: minute)
            score = %{x: x, phenomena: [], impact_unit: "failed_requests_per_min", impact_rate: 0.0, examples: []}
            result = Symptoms.Lifecycle.step(60, at, %{id => score}, at)
            length(result.opened) + length(result.reopened)
          end)
          |> Enum.sum()

        assert actual == expected
        assert Symptoms.Evidence.Threshold.crossings([xs], h, 0.0) == actual
      end
    end
  end

  test "the threshold replay reads entities in batches with the same result" do
    # 600 entities (more than one batch of 200), each with three
    # 1-minute windows on a different day of the last 4 weeks. All are quiet
    # (e = 1, x = 0) except the last entity's middle two at the cap: its
    # excursion peaks at 2 ln 20 = 5.9915, the largest replayed peak.
    rows =
      for i <- 0..599, j <- 0..2 do
        e = if i == 599 and j > 0, do: 20.0, else: 1.0

        %{
          entity_id: entity("GET /batch/#{i}"),
          source: "fake.errors",
          phenomenon: "request_errors",
          window_seconds: 60,
          window_start: DateTime.shift(@now, day: -1 - rem(i, 27), minute: j),
          statistic: 0.0,
          e: e,
          examples: [],
          open_symptom: false,
          symptom_id: nil,
          inserted_at: @now
        }
      end

    Store.insert_windows(rows)
    Calibrate.weekly_threshold(@now)

    # 1800 windows are 1800 · 60 / 86 400 = 1.25 entity-days; at 0.001
    # crossings per entity-day none is allowed, so h sits just above the
    # largest peak.
    assert_in_delta Settings.h(60), 2 * :math.log(20), 1.0e-6
    assert Settings.h(60) > 2 * :math.log(20)
  end

  test "the threshold replays every window but labelled incidents, per pipeline" do
    # One source, one phenomenon: a window's combined log-evidence is ln e
    # (weight 1, the phenomenon capped at ±ln 20). Drift 0.
    #
    # 1-minute, entity a: 50 quiet windows (e = 1, x = 0) around a run of
    # three at the cap that opened a symptom, unlabelled. Its excursion peaks
    # at 3 ln 20 = 8.9872.
    sym = symptom()
    a = entity("GET /a")
    series(a, 60, List.duplicate(1.0, 25) ++ [20.0, 20.0, 20.0] ++ List.duplicate(1.0, 25), sym.id)

    # Entity b: a run of five at the cap labelled bad, peak 5 ln 20 = 14.98:
    # a labelled incident, left out of the replay.
    bad = symptom()

    Repo.insert!(%Label{
      symptom_id: bad.id,
      outcome: "bad",
      independent: true,
      weight: 1.0,
      score: 9.0,
      max_tier: "page",
      missed: false,
      confirmed_at: @now
    })

    series(entity("GET /b"), 60, List.duplicate(20.0, 5), bad.id)

    # 5-minute: entity c, two windows at the cap: peak 2 ln 20 = 5.9915.
    series(entity("GET /c"), 300, [1.0, 20.0, 20.0, 1.0])

    Calibrate.weekly_threshold(@now)

    # 53 one-minute windows are 53 · 60 / 86 400 = 0.0368 entity-days; at
    # 0.001 crossings per entity-day none is allowed, so h sits just above the
    # largest replayed peak (and above the ln 20 floor).
    assert_in_delta Settings.h(60), 3 * :math.log(20), 1.0e-6
    assert Settings.h(60) > 3 * :math.log(20)
    assert_in_delta Settings.h(300), 2 * :math.log(20), 1.0e-6
  end
end
