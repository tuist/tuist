Code.require_file("source_helpers.ex", __DIR__)

defmodule Symptoms.Sources.PulseErrorsTest do
  use ExUnit.Case, async: true
  use Mimic

  import Symptoms.SourceHelpers

  alias Symptoms.Sources.PulseErrors

  @start 1_763_301_600
  @window %{start: @start, seconds: 300}
  @now @start + 300 + 200

  defp entity(fingerprint),
    do: %{environment: "production", service: "tuist-server", kind: "error_issue", key: fingerprint}

  defp issue(fingerprint, events, accounts) do
    %{
      "service" => "tuist-server",
      "fingerprint" => fingerprint,
      "events" => events,
      "accounts" => accounts,
      "latest_event_id" => "9f1c2b7e4a5d4c0e8b3f6a1d2e7c9b04",
      "latest_trace_id" => "4bf92f3577b34da6a3ce929d0e0e4736"
    }
  end

  test "negative binomial residual per issue, affected users as impact, novelty for new issues" do
    stub_pulse(fn sql ->
      assert sql =~ "FROM errors WHERE \"timestamp\" >= to_timestamp_seconds(#{@start})"
      [issue("fp1", 12, 6), issue("fp2", 3, 1)]
    end)

    opts =
      pulse_opts(
        now: @now,
        known?: &(&1.key in ["fp1", "fp3"]),
        entities: [entity("fp1"), entity("fp3")],
        baseline:
          baselines(%{
            {"error.negative_binomial", "fp1"} => %{mean: 2.0, alpha: 0.5, n: 8064},
            {"error.negative_binomial", "fp3"} => %{mean: 1.0, alpha: 0.0, n: 8064}
          })
      )

    assert {:ok, records} = PulseErrors.collect(@window, opts)
    by_key = Map.new(records, &{&1.entity.key, &1})

    # (12 - 2) / sqrt(2 + 0.5 · 4) = 10 / 2.
    assert_in_delta by_key["fp1"].statistic, 5.0, 1.0e-12
    # 6 accounts in 5 minutes.
    assert by_key["fp1"].impact == %{unit: "affected_users_per_min", rate: 1.2}
    assert by_key["fp1"].examples == ["9f1c2b7e4a5d4c0e8b3f6a1d2e7c9b04", "4bf92f3577b34da6a3ce929d0e0e4736"]
    # Expected issue without events: (0 - 1) / 1.
    assert_in_delta by_key["fp3"].statistic, -1.0, 1.0e-12
    assert %{phenomenon: :novelty, source: "error.novelty", statistic: 3.0} = by_key["fp2"]
  end

  test "a window that ingestion may not have finished is unknown" do
    stub_pulse(fn sql -> flunk(sql) end)
    assert {:unknown, [_]} = PulseErrors.collect(@window, pulse_opts(now: @start + 330, entities: [entity("fp1")]))
  end

  test "a failed query is unknown" do
    stub_pulse(fn _sql -> {:error, 500} end)
    assert {:unknown, [_]} = PulseErrors.collect(@window, pulse_opts(now: @now, entities: [entity("fp1")]))
  end

  test "baseline fit from sums counts quiet windows as zero" do
    # Counts 2, 4, 6, 8 over 4 windows: mean 5, s² = (120 - 4 · 25) / 3 = 20/3, alpha = (20/3 - 5) / 25 = 1/15.
    fit = PulseErrors.fit(%{"events" => 20, "events_sq" => 120}, 4)
    assert fit.mean == 5.0
    assert_in_delta fit.alpha, 1 / 15, 1.0e-12

    # The same 20 events over 8 windows (4 quiet): mean 2.5, s² = (120 - 50) / 7 = 10, alpha = 7.5 / 6.25 = 1.2.
    assert_in_delta PulseErrors.fit(%{"events" => 20, "events_sq" => 120}, 8).alpha, 1.2, 1.0e-12
  end
end
