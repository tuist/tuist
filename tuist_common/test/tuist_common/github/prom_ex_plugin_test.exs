defmodule TuistCommon.GitHub.PromExPluginTest do
  use ExUnit.Case, async: true

  alias TuistCommon.GitHub
  alias TuistCommon.GitHub.PromExPlugin
  alias TuistCommon.GitHub.RateLimit

  describe "polling_metrics/1" do
    test "exposes the budget as gauges keyed by the measurements the client emits" do
      [polling] = PromExPlugin.polling_metrics([])
      [limit, used, reset] = polling.metrics

      assert polling.poll_rate == to_timeout(second: 15)

      assert polling.measurements_mfa ==
               {PromExPlugin, :execute_rate_limit_telemetry, [RateLimit]}

      assert limit.name == [:tuist, :github, :rate_limit, :limit]
      assert limit.event_name == PromExPlugin.poll_event_name()
      assert limit.measurement == :limit
      assert limit.tags == [:resource]

      assert used.name == [:tuist, :github, :rate_limit, :used]
      assert used.event_name == PromExPlugin.poll_event_name()
      assert used.measurement == :used
      assert used.tags == [:resource]

      assert reset.name == [:tuist, :github, :rate_limit, :reset, :timestamp, :seconds]
      assert reset.event_name == PromExPlugin.poll_event_name()
      assert reset.measurement == :reset
      assert reset.tags == [:resource]
    end
  end

  describe "execute_rate_limit_telemetry/0" do
    # Asserts against what `TuistCommon.GitHub` actually emits rather than a
    # hand-written map, so renaming a measurement key or dropping the
    # `:resource` metadata fails here instead of silently producing a gauge
    # that never yields a sample.
    test "re-emits every budget the client has reported" do
      unique = System.unique_integer([:positive])
      server = :"rate_limit_#{unique}"
      start_supervised!({RateLimit, name: server, handler_id: "tracker-#{unique}"})

      handler_id = "poll-#{unique}"
      test_pid = self()

      :telemetry.attach(
        handler_id,
        PromExPlugin.poll_event_name(),
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:poll, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      :telemetry.execute(
        GitHub.rate_limit_event_name(),
        %{limit: 5000, used: 4998, reset: 1_780_000_000},
        %{resource: "core"}
      )

      # The tracker records via a cast; the snapshot call behind
      # execute_rate_limit_telemetry/1 serialises behind it.
      PromExPlugin.execute_rate_limit_telemetry(server)

      assert_receive {:poll, %{limit: 5000, used: 4998, reset: 1_780_000_000},
                      %{resource: "core"}}
    end

    test "emits nothing, and does not raise, when the tracker is not running" do
      handler_id = "poll-#{System.unique_integer([:positive])}"
      test_pid = self()

      :telemetry.attach(
        handler_id,
        PromExPlugin.poll_event_name(),
        fn _event, measurements, metadata, _config ->
          send(test_pid, {:poll, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      PromExPlugin.execute_rate_limit_telemetry(:rate_limit_not_running)

      refute_received {:poll, _measurements, _metadata}
    end
  end
end
