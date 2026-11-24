Code.require_file("source_helpers.ex", __DIR__)

defmodule Symptoms.Sources.PresenceTest do
  use ExUnit.Case, async: true
  use Mimic

  import Symptoms.SourceHelpers

  alias Symptoms.Sources.Presence

  @start 1_763_301_600
  @window %{start: @start, seconds: 60}
  @now @start + 120

  defp entity(service, type), do: %{environment: "production", service: service, kind: "telemetry", key: type}

  test "volume against the baseline, missing services count as zero, and Pulse lag" do
    stub_pulse(fn sql ->
      cond do
        sql =~ "AS latest FROM symptoms_trace_counts_1m" -> latest(@start + 60)
        # Logs stopped 10 minutes ago.
        sql =~ "AS latest FROM symptoms_log_totals_1m" -> latest(@start - 600)
        sql =~ "FROM symptoms_trace_counts_1m" -> [%{"service" => "tuist-server", "items" => 400}]
      end
    end)

    test = self()

    opts =
      pulse_opts(
        now: @now,
        entities: [entity("tuist-server", "traces"), entity("kura", "traces"), entity("tuist-server", "logs")],
        unknown: &send(test, {:unknown, &1, &2}),
        baseline: fn "presence.volume", e -> if e.key == "traces", do: [900, 1000, 1100] end
      )

    assert {:ok, records} = Presence.collect(@window, opts)
    by = Map.new(records, &{{&1.source, &1.entity.service, &1.entity.key}, &1})

    # 400 against median 1000, MAD 100: -(400 - 1000) / 148.26.
    server = by[{"presence.volume", "tuist-server", "traces"}]
    assert_in_delta server.statistic, 600 / 148.26, 1.0e-9
    assert server.impact.rate == 600.0
    # Kura sent nothing: zero, which is evidence.
    assert_in_delta by[{"presence.volume", "kura", "traces"}].statistic, 1000 / 148.26, 1.0e-9

    # Lag: now - (latest + 60).
    assert by[{"presence.pulse_lag", "pulse", "symptoms_trace_counts_1m"}].statistic == 0.0
    assert by[{"presence.pulse_lag", "pulse", "symptoms_log_totals_1m"}].statistic == 660.0
    # The lagging logs flow leaves its entities unknown.
    assert_received {:unknown, "presence.volume", [%{service: "tuist-server", key: "logs"}]}
  end

  test "an unreadable Pulse is unknown" do
    stub_pulse(fn _ -> {:error, 503} end)
    assert {:unknown, [_]} = Presence.collect(@window, pulse_opts(now: @now, entities: [entity("kura", "logs")]))
  end
end
