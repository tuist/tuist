defmodule Atlas.Engineering.Errors.DropAlerterTest do
  # credo:disable-for-next-line Credo.Check.Warning.AsyncTests
  use Atlas.DataCase, async: false
  use Mimic

  alias Atlas.Engineering.Errors.DropAlerter
  alias Atlas.Slack.API

  setup :verify_on_exit!

  setup context do
    name = :"drop_alerter_#{System.unique_integer([:positive])}"

    {:ok, pid} =
      start_supervised(
        {DropAlerter,
         [
           name: name,
           flush_interval_ms: 60_000
         ]}
      )

    Mimic.allow(API, self(), pid)

    previous_channel = Application.get_env(:atlas, :default_alert_slack_channel)
    on_exit(fn -> Application.put_env(:atlas, :default_alert_slack_channel, previous_channel) end)

    {:ok, Map.merge(context, %{alerter: name, pid: pid})}
  end

  describe "coalescing" do
    test "coalesces repeated flush failures into a single Slack post",
         %{pid: pid} = ctx do
      test_pid = self()

      expect(API, :post_message, fn _app_key, channel, text, blocks ->
        send(test_pid, {:posted, %{channel: channel, text: text, blocks: blocks}})
        {:ok, %{}}
      end)

      Application.put_env(:atlas, :default_alert_slack_channel, "C_TEST_CHANNEL")

      Enum.each(1..25, fn _ ->
        GenServer.cast(
          pid,
          {:report, :flush_failure,
           %{
             name: "Atlas.Engineering.Errors.Event.Buffer",
             byte_size: 1_024,
             sample: "Ch.Error 81"
           }}
        )
      end)

      _ = :sys.get_state(pid)
      :ok = DropAlerter.flush(ctx.alerter)

      assert_receive {:posted, payload}, 1_000
      assert payload.text =~ "ATLAS INGEST BROKEN" or payload.text =~ "INGEST BROKEN"
      assert payload.text =~ "25"
      assert payload.text =~ "Atlas.Engineering.Errors.Event.Buffer"
      assert payload.channel == "C_TEST_CHANNEL"

      refute_receive {:posted, _}, 100
    end

    test "resets the bucket after flushing", %{pid: pid} = ctx do
      test_pid = self()

      expect(API, :post_message, 2, fn _app_key, channel, text, blocks ->
        send(test_pid, {:posted, %{channel: channel, text: text, blocks: blocks}})
        {:ok, %{}}
      end)

      Application.put_env(:atlas, :default_alert_slack_channel, "C_TEST_CHANNEL")

      GenServer.cast(pid, {:report, :ingest_failure, %{sample: "%Postgrex.Error{...}"}})
      _ = :sys.get_state(pid)
      :ok = DropAlerter.flush(ctx.alerter)

      assert_receive {:posted, payload1}, 1_000
      assert payload1.text =~ "INGEST BROKEN"

      GenServer.cast(pid, {:report, :ingest_failure, %{sample: "different"}})
      _ = :sys.get_state(pid)
      :ok = DropAlerter.flush(ctx.alerter)

      assert_receive {:posted, payload2}, 1_000
      assert payload2.text =~ "INGEST BROKEN"
    end
  end

  describe "fallbacks" do
    test "falls back to a Logger.warning on :atlas_alerts when no channel is configured",
         %{pid: pid} = ctx do
      Application.delete_env(:atlas, :default_alert_slack_channel)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          GenServer.cast(
            pid,
            {:report, :flush_failure, %{name: "X.Buffer", byte_size: 512, sample: "boom"}}
          )

          _ = :sys.get_state(pid)
          :ok = DropAlerter.flush(ctx.alerter)
        end)

      assert log =~ "INGEST BROKEN"
      assert log =~ "no_channel_configured"
    end

    test "falls back to Logger.warning when Slack post itself fails",
         %{pid: pid} = ctx do
      Application.put_env(:atlas, :default_alert_slack_channel, "C_TEST_CHANNEL")

      expect(API, :post_message, fn _app_key, _channel, _text, _blocks ->
        {:error, :slack_api_error}
      end)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          GenServer.cast(
            pid,
            {:report, :flush_failure, %{name: "X.Buffer", byte_size: 512, sample: "boom"}}
          )

          _ = :sys.get_state(pid)
          :ok = DropAlerter.flush(ctx.alerter)
        end)

      assert log =~ "INGEST BROKEN"
      assert log =~ ":slack_api_error"
    end
  end

  describe "telemetry" do
    test "emits [:atlas, :engineering, :errors, :ingest, :dropped] on each flush",
         %{pid: pid} = ctx do
      Application.delete_env(:atlas, :default_alert_slack_channel)
      handler_id = "test-handler-#{System.unique_integer([:positive])}"
      test_pid = self()

      :telemetry.attach(
        handler_id,
        [:atlas, :engineering, :errors, :ingest, :dropped],
        fn _event, measurements, meta, _ ->
          send(test_pid, {:telemetry, measurements, meta})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      GenServer.cast(
        pid,
        {:report, :flush_failure, %{name: "X.Buffer", byte_size: 100, sample: "s"}}
      )

      GenServer.cast(
        pid,
        {:report, :flush_failure, %{name: "X.Buffer", byte_size: 100, sample: "s"}}
      )

      _ = :sys.get_state(pid)
      :ok = DropAlerter.flush(ctx.alerter)

      assert_receive {:telemetry, %{count: 2}, %{reason: :flush_failure}}, 1_000
    end
  end
end
