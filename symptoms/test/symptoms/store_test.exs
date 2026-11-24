defmodule Symptoms.StoreTest do
  use Symptoms.DataCase

  alias Symptoms.Evidence.Calibration
  alias Symptoms.Lifecycle
  alias Symptoms.Log
  alias Symptoms.Store
  alias Symptoms.Store.Label
  alias Symptoms.Store.Symptom

  # Monday 10:00 UTC.
  @at ~U[2026-11-16 10:00:00.000000Z]
  @route %{service: "tuist-server", kind: "route", key: "GET /runs"}
  @source "fake.errors"

  defp entity_id do
    Store.resolve_entities([@route], DateTime.shift(@at, day: -30))
    Store.entity_id(@route)
  end

  defp symptom(state, max_tier) do
    Repo.insert!(%Symptom{
      id: Log.uuid7(@at),
      symptom_key: "k",
      root_key: "60:entity:1",
      phenomenon: "request_errors",
      state: state,
      tier: max_tier,
      max_tier: max_tier,
      opened_at: DateTime.shift(@at, week: -1)
    })
  end

  defp label(symptom, outcome) do
    Repo.insert!(%Label{
      symptom_id: symptom.id,
      outcome: outcome,
      independent: true,
      weight: 1.0,
      score: 7.0,
      max_tier: symptom.max_tier,
      missed: false,
      confirmed_at: @at
    })
  end

  # Window k is one week before `at`, minute k: the same hour of week. Its
  # statistic is k, so the returned statistics name the windows kept.
  defp put_windows(id, minutes, symptom_id \\ nil, seconds \\ 60, base \\ DateTime.shift(@at, week: -1)) do
    Store.insert_windows(
      for k <- minutes do
        %{
          entity_id: id,
          source: @source,
          phenomenon: "request_errors",
          window_seconds: seconds,
          window_start: DateTime.shift(base, minute: k),
          statistic: k * 1.0,
          e: 1.0,
          examples: [],
          # What the pipeline marks for windows of a symptom's run.
          open_symptom: symptom_id != nil,
          symptom_id: symptom_id,
          inserted_at: @at
        }
      end
    )
  end

  defp history(id, seconds \\ 60, at \\ @at) do
    %{^id => windows} = Store.history([id], @source, seconds, at, 0)
    windows |> Enum.map(& &1.statistic) |> Enum.sort()
  end

  test "the null history leaves out only runs labelled bad or still open at board tier or above" do
    id = entity_id()
    put_windows(id, 0..9)
    # Resolved at audit tier, unlabelled: kept.
    put_windows(id, 10..14, symptom("resolved", "audit").id)
    # Labelled bad: left out.
    put_windows(id, 15..19, "resolved" |> symptom("page") |> label("bad") |> Map.fetch!(:symptom_id))
    # Still open at board tier: left out.
    put_windows(id, 20..24, symptom("open", "board").id)
    # Still open, audit only: kept.
    put_windows(id, 25..29, symptom("open", "audit").id)
    # Paged, then labelled fine: kept.
    put_windows(id, 30..34, "resolved" |> symptom("page") |> label("fine") |> Map.fetch!(:symptom_id))

    assert history(id) == Enum.map(Enum.concat([0..14, 25..34]), &(&1 * 1.0))
  end

  # Every 15 minutes over the 5 weeks before `at` (Monday 10:37), plus the
  # window at exactly `at` − 28 days and the minute before it.
  defp grid_windows(id, at) do
    starts =
      for minute <- 0..(36 * 24 * 4 - 1),
          start = DateTime.shift(~U[2026-10-12 00:00:00.000000Z], minute: minute * 15),
          DateTime.before?(start, DateTime.shift(at, hour: 1)),
          do: start

    edges = [~U[2026-10-19 10:37:00.000000Z], ~U[2026-10-19 10:36:00.000000Z]]

    Store.insert_windows(
      for start <- starts ++ edges do
        %{
          entity_id: id,
          source: @source,
          phenomenon: "request_errors",
          window_seconds: 60,
          window_start: start,
          statistic: 0.0,
          e: 1.0,
          examples: [],
          open_symptom: false,
          symptom_id: nil,
          inserted_at: at
        }
      end
    )
  end

  test "the null history is the same hour of week of the last 28 days, up to the window" do
    id = entity_id()
    at = ~U[2026-11-16 10:37:00.000000Z]
    grid_windows(id, at)

    # By hand: [at − 28 d, at) holds Monday 10:xx of Oct 19 (from 10:37 on),
    # Oct 26, Nov 2, Nov 9, and Nov 16 before 10:37. On the 15-minute grid
    # that is Oct 19 10:45, the full hours of the three middle Mondays and
    # Nov 16 10:00, 10:15 and 10:30, plus the edge window Oct 19 10:37
    # (`>=`). Oct 19 10:36, Oct 12, 09:45, 11:00, Sunday and Tuesday 10:xx
    # and Nov 16 10:45 are outside.
    full = fn date -> Enum.map([0, 15, 30, 45], &DateTime.new!(date, Time.new!(10, &1, 0, {0, 6}))) end

    expected =
      [~U[2026-10-19 10:37:00.000000Z], ~U[2026-10-19 10:45:00.000000Z]] ++
        full.(~D[2026-10-26]) ++
        full.(~D[2026-11-02]) ++
        full.(~D[2026-11-09]) ++
        Enum.take(full.(~D[2026-11-16]), 3)

    %{^id => windows} = Store.history([id], @source, 60, at, 0)
    assert windows |> Enum.map(& &1.window_start) |> Enum.sort(DateTime) == expected
  end

  test "the null history query reads only the matching hour ranges through the index" do
    id = entity_id()
    at = ~U[2026-11-16 10:37:00.000000Z]
    grid_windows(id, at)
    Repo.query!("ANALYZE stream_windows")
    Repo.query!("SET LOCAL enable_seqscan = off")

    [plan] = Repo.explain(:all, Store.history_query([id], @source, 60, at), analyze: true, format: :map)

    scans =
      plan |> List.wrap() |> Enum.flat_map(&nodes(&1["Plan"])) |> Enum.filter(&(&1["Relation Name"] == "stream_windows"))

    # 17 windows match (previous test); every row the scans read is one of them.
    assert scans != []
    refute Enum.any?(scans, &(&1["Node Type"] == "Seq Scan"))
    assert scans |> Enum.map(&(&1["Rows Removed by Filter"] || 0)) |> Enum.sum() == 0
    assert scans |> Enum.map(&(&1["Rows Removed by Index Recheck"] || 0)) |> Enum.sum() == 0
    assert scans |> Enum.map(&(&1["Actual Rows"] * &1["Actual Loops"])) |> Enum.sum() == 17
  end

  defp nodes(node), do: [node | Enum.flat_map(node["Plans"] || [], &nodes/1)]

  defp degraded_score, do: %{x: 2.0, phenomena: [], impact_unit: nil, impact_rate: 0.0, examples: []}
  defp quiet_score, do: %{x: -0.5, phenomena: [], impact_unit: nil, impact_rate: 0.0, examples: []}

  test "the 1- and 5-minute pipelines keep their own degraded runs" do
    id = entity_id()
    # The 1-minute run starts at 10:00 (x = 2 > degraded_nats 1, CUSUM 2 < h
    # 6: nothing opens), and 10:00 and 10:01 are its windows.
    put_windows(id, 0..1, nil, 60, @at)
    Lifecycle.step(60, @at, %{id => degraded_score()}, DateTime.shift(@at, minute: 1))
    # The 5-minute pipeline sees the entity quiet in its own window.
    Lifecycle.step(300, DateTime.shift(@at, minute: -5), %{id => quiet_score()}, DateTime.shift(@at, minute: 2))
    Lifecycle.step(60, DateTime.shift(@at, minute: 1), %{id => degraded_score()}, DateTime.shift(@at, minute: 2))

    # At 10:02 the 1-minute run still starts at 10:00, so neither of its
    # windows is null history. Had the 5-minute step cleared the run, it
    # would restart at 10:01 and window 10:00 (statistic 0) would count.
    assert history(id, 60, DateTime.shift(@at, minute: 2)) == []
  end

  test "a full own history caps a window's e-value at 7.76 on 1-minute and 3.5 on 5-minute windows" do
    id = entity_id()
    # Every window of the last 5 weeks at this hour, and today's before 10:37.
    at = DateTime.shift(@at, minute: 37)

    for seconds <- [60, 300], week <- 0..5 do
      base = DateTime.shift(@at, week: -week)
      per_hour = div(3600, seconds)
      put_windows(id, Enum.map(0..(per_hour - 1), &div(&1 * seconds, 60)), nil, seconds, base)
    end

    # Same hour of week within 28 days: weeks −1 to −3 whole (3 · 60), week
    # −4 from 10:37 on (23), and today before 10:37 (37): 240 = 4 · 60 at any
    # minute. Likewise 4 · 12 = 48 five-minute windows.
    n60 = length(Store.history([id], @source, 60, at, 0)[id])
    n300 = length(Store.history([id], @source, 300, DateTime.shift(@at, minute: 35), 0)[id])
    assert {n60, n300} == {240, 48}

    # The smallest conformal p-value is 1/(n + 1), so with κ = 0.5 the
    # largest e-value is 0.5 · √(n + 1): 0.5 · √241 = 7.762 (2.05 nats) and
    # 0.5 · √49 = 3.5 (1.25 nats), both under the nominal cap of 20.
    assert_in_delta Calibration.max_e(n60), 7.762087, 1.0e-6
    assert Calibration.max_e(n300) == 3.5
    assert Calibration.e_value(1 / (n60 + 1)) == Calibration.max_e(n60)
    # The cap binds only from n + 1 = 1600 (0.5 · 40 = 20), e.g. on borrowed
    # family history.
    assert Calibration.max_e(1599) == 20.0
    assert Calibration.max_e(1598) < 20.0
  end
end
