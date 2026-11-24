defmodule Symptoms.DeploysTest do
  use Symptoms.DataCase

  alias Symptoms.Deploys
  alias Symptoms.Evidence.VersionTest
  alias Symptoms.Store
  alias Symptoms.Store.Reanchor
  alias Symptoms.Store.Symptom

  @t0 ~U[2026-11-16 10:00:00.000000Z]
  @route %{service: "tuist-server", kind: "route", key: "GET /runs"}
  @other %{service: "tuist-server", kind: "route", key: "GET /other"}

  test "extreme concurrent evidence is capped only after retaining the log statistic" do
    deploy()
    Store.put_version_counts("traces", counts("v2", 1200, 2000, [1]) ++ counts("v1", 0, 2000, [1]))
    assert [row] = Deploys.version_records(60, DateTime.shift(@t0, minute: 1))
    assert row.statistic > 700
    assert row.e == 20.0
    assert %{status: "rejected", e: e} = Repo.one!(Symptoms.Store.VersionTest)
    assert is_float(e)

    Store.put_version_counts("traces", counts("v2", 0, 2000, [2]) ++ counts("v1", 1200, 2000, [2]))
    assert [reverse] = Deploys.version_records(60, DateTime.shift(@t0, minute: 2))
    assert reverse.statistic < -260
    assert reverse.e >= 0

    Store.put_version_counts("traces", counts("v2", 0, 4000, [3]) ++ counts("v1", 4000, 4000, [3]))
    assert [underflow] = Deploys.version_records(60, DateTime.shift(@t0, minute: 3))
    assert underflow.statistic < -890
    assert underflow.e == 0.0
    assert %{status: "rejected"} = Repo.one!(Symptoms.Store.VersionTest)
  end

  test "sustained version updates never overflow and rejection is sticky" do
    deploy()
    # A deploy is evaluated for two hours; use 170 successive distinct
    # windows within that horizon to exercise the persisted process.
    for i <- 1..170 do
      at = DateTime.shift(@t0, second: i)

      Store.put_version_counts("traces", [
        %{entity: @route, version: "v2", window_start: at, window_seconds: 60, errors: 10, total: 100},
        %{entity: @route, version: "v1", window_start: at, window_seconds: 60, errors: 1, total: 100}
      ])

      assert [_] = Deploys.version_records(60, at)
    end

    state = Repo.one!(Symptoms.Store.VersionTest)
    assert state.status == "rejected"
    assert Enum.max(state.log_weights) > 709
    assert is_float(state.e)
  end

  test "the prior decays over 30 minutes and is capped at ×3" do
    assert Deploys.prior_multiplier([{"code", @t0}], @t0) == 1.5
    # Halfway: 1 + 0.5 · 0.5.
    assert Deploys.prior_multiplier([{"code", @t0}], DateTime.shift(@t0, minute: 15)) == 1.25
    assert Deploys.prior_multiplier([{"code", @t0}], DateTime.shift(@t0, minute: 30)) == 1.0
    # Config ×2 and migration ×3 multiply to 6, capped at 3.
    assert Deploys.prior_multiplier([{"config", @t0}, {"migration", @t0}], @t0) == 3.0
  end

  defp deploy(before \\ "v1") do
    Store.resolve_entities([@route, @other], DateTime.shift(@t0, day: -1))

    [id] =
      Deploys.record_changes(
        "traces",
        [
          %{
            kind: :deploy,
            ref: "v2",
            at: DateTime.to_unix(@t0),
            service: "tuist-server",
            touched_entities: [@route],
            before: before,
            after: "v2"
          }
        ],
        @t0
      )

    id
  end

  defp counts(version, errors, total, minutes) do
    for m <- minutes do
      %{
        entity: @route,
        version: version,
        window_start: DateTime.shift(@t0, minute: m),
        window_seconds: 60,
        errors: errors,
        total: total
      }
    end
  end

  test "the prior applies only to touched entities" do
    deploy()
    [route_id, other_id] = Enum.map([@route, @other], &Store.entity_id/1)

    assert Deploys.prior_terms([route_id, other_id], DateTime.shift(@t0, minute: 1)) == %{
             route_id => :math.log(1 + 0.5 * (1 - 60 / 1800))
           }
  end

  test "version-against-version evidence uses concurrent per-version counts" do
    deploy()
    Store.put_version_counts("traces", counts("v2", 10, 100, [1]) ++ counts("v1", 1, 100, [1]))

    assert [row] = Deploys.version_records(60, DateTime.shift(@t0, minute: 1))
    assert row.source == "deploy.version_error_share"
    assert_in_delta row.e, min(VersionTest.window_e(10, 100, 1, 100), 20.0), 1.0e-12
    assert row.e > 1
  end

  test "version-against-version evidence on latency exceedance above the old version's p95 bucket" do
    deploy()

    five = fn version, minute, histogram ->
      %{
        entity: @route,
        version: version,
        window_start: DateTime.shift(@t0, minute: minute),
        window_seconds: 300,
        errors: 0,
        total: histogram |> Map.values() |> Enum.sum(),
        histogram: histogram
      }
    end

    # Before the deploy v1 has 95 of 100 requests in bucket 10, so its p95
    # bucket is 10. In the window both versions serve 100 requests: v2 has 50
    # above bucket 10, v1 5.
    Store.put_version_counts(
      "traces",
      [
        five.("v1", -10, %{10 => 95, 30 => 5}),
        five.("v1", 5, %{10 => 95, 30 => 5}),
        five.("v2", 5, %{10 => 50, 30 => 50})
      ]
    )

    rows = Map.new(Deploys.version_records(300, DateTime.shift(@t0, minute: 5)), &{&1.source, &1})
    # No errors on either version: the error-share window is uninformative.
    assert rows["deploy.version_error_share"].e == 1.0
    row = rows["deploy.version_latency_exceedance"]
    assert row.phenomenon == :latency
    assert row.observed == 0.5
    assert row.expected == 0.05

    # Closed form: π₀ = 1/2, k = 55, x_new = 50; for odds ratio ψ, θ = ψ/(ψ+1)
    # and LR = (2θ)^50 · (2(1−θ))^5. The e-value is the mean over the grid.
    e =
      Enum.sum(for psi <- [1.5, 2, 3, 5, 10], do: :math.pow(2 * psi / (psi + 1), 50) * :math.pow(2 / (psi + 1), 5)) / 5

    assert_in_delta row.statistic, :math.log(e), 1.0e-9
    assert row.e == 20.0
  end

  test "a shift above the error cap is an intended? board symptom, not a re-anchor" do
    deploy()
    # Error share before: (5 + 0.5)/(1000 + 1); after: (30 + 0.5)/(1000 + 1). Ratio 5.5 > 3.
    Store.put_version_counts("traces", counts("v1", 5, 1000, [-10]) ++ counts("v2", 30, 1000, [10]))

    assert [{"intended", _, _}] = Deploys.reanchor(DateTime.shift(@t0, hour: 2))
    assert [%Symptom{kind: "intended", tier: "board", revision: 1} = symptom] = Repo.all(Symptom)
    assert symptom.document["title"] =~ "intended?"
    assert symptom.document["phenomenon"] == "request_errors"
    assert %{status: "intended", error_ratio: ratio} = Repo.one!(Reanchor)
    assert_in_delta ratio, 30.5 / 5.5, 1.0e-12
    assert Store.baseline_anchor(@route) == nil
  end

  defp intended do
    deploy()
    Store.put_version_counts("traces", counts("v1", 5, 1000, [-10]) ++ counts("v2", 30, 1000, [10]))
    opened_at = DateTime.shift(@t0, hour: 2)
    assert [{"intended", _, _}] = Deploys.reanchor(opened_at)
    {Repo.one!(Symptom), opened_at}
  end

  test "an intended? symptom resolves 72 hours after it opened, and its baseline freeze ends" do
    {%{id: id}, opened_at} = intended()
    assert Store.baselines_frozen?(@route)

    Symptoms.Pipeline.run_pending(60, DateTime.shift(opened_at, hour: 71), sources: [])
    assert %{state: "open"} = Repo.get!(Symptom, id)

    Symptoms.Pipeline.run_pending(60, DateTime.shift(opened_at, day: 3), sources: [])
    assert %{state: "resolved", document: %{"transition" => "resolved", "state" => "resolved"}} = Repo.get!(Symptom, id)
    refute Store.baselines_frozen?(@route)
  end

  test "an intended? symptom never tags stream windows and resolves once its outcome is confirmed" do
    {%{id: id}, opened_at} = intended()
    entity_id = Store.entity_id(@route)
    assert Store.open_symptom_ids([entity_id]) == %{}

    Repo.insert!(%Symptoms.Store.HumanOutcome{
      symptom_id: id,
      outcome: "fine",
      confirmed_at: DateTime.shift(opened_at, hour: 1),
      change_seq: 1
    })

    Symptoms.Pipeline.run_pending(60, DateTime.shift(opened_at, hour: 1, minute: 1), sources: [])
    assert %{state: "resolved"} = Repo.get!(Symptom, id)
  end

  test "a quiet deploy re-anchors after 2 hours; an open symptom freezes the baseline" do
    deploy()
    Store.put_version_counts("traces", counts("v1", 5, 1000, [-10]) ++ counts("v2", 6, 1000, [10]))

    assert Deploys.reanchor(DateTime.shift(@t0, second: 7_199)) == []

    Repo.insert!(%Symptom{
      id: Symptoms.Log.uuid7(@t0),
      symptom_key: "k",
      root_key: "r",
      entity_id: Store.entity_id(@route),
      phenomenon: "latency",
      state: "open",
      tier: "audit",
      max_tier: "audit",
      opened_at: @t0
    })

    assert Deploys.reanchor(DateTime.shift(@t0, hour: 2)) == []
    Repo.update_all(Symptom, set: [state: "resolved"])

    assert [{"accepted", _, _}] = Deploys.reanchor(DateTime.shift(@t0, second: 7_300))
    assert %{version: "v2", change_ref: "v2"} = Store.baseline_anchor(@route)
  end

  test "adjacent windows give per-window evidence but never step the version e-process" do
    deploy()
    # v1 served only before the deploy (its 30-minute reference: 1 error in
    # 100); v2 alone serves windows 1–3 with 10 errors in 100 each.
    Store.put_version_counts("traces", counts("v1", 1, 100, [-5]) ++ counts("v2", 10, 100, [1, 2, 3]))

    for m <- [1, 2, 3] do
      assert [row] = Deploys.version_records(60, DateTime.shift(@t0, minute: m))
      assert row.source == "deploy.version_error_share_adjacent"
      # Each window is compared with the same reference: π₀ = 1/2, k = 11,
      # x_new = 10, LR_ψ = (2θ)^10 · 2(1 − θ) with θ = ψ/(ψ + 1): 4.95, 11.84,
      # 28.8, 55.1, 71.7 over the grid, mean 34.5, capped at 20.
      assert row.e == 20.0
    end

    # Stepping on the same reference every window would count it again each
    # time (34.5³ after three windows) and reject the deploy on reused data.
    assert Repo.all(Symptoms.Store.VersionTest) == []
  end
end
