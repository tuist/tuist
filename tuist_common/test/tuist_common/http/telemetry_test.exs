defmodule TuistCommon.HTTP.TelemetryTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Plug.Test

  alias TuistCommon.HTTP.Telemetry

  def handle_event(event, measurements, metadata, pid) do
    send(pid, {:telemetry_event, event, measurements, metadata})
  end

  setup do
    handler_id = "test-#{System.unique_integer([:positive])}"

    events = [
      Telemetry.request_timeout_event(),
      Telemetry.request_failure_event(),
      Telemetry.connection_drop_event(),
      Telemetry.connection_error_event()
    ]

    test_pid = self()

    :ok =
      :telemetry.attach_many(
        handler_id,
        events,
        &__MODULE__.handle_event/4,
        test_pid
      )

    on_exit(fn ->
      :telemetry.detach(handler_id)
    end)

    :ok
  end

  test "emits a timeout event for Bandit body read timeouts" do
    conn =
      :post
      |> conn("/webhooks/github", "")
      |> Map.put(:private, %{phoenix_route: "/webhooks/github"})

    measurements = %{
      duration: System.convert_time_unit(120, :millisecond, :native),
      req_body_start_time: System.convert_time_unit(10, :millisecond, :native),
      req_body_end_time: System.convert_time_unit(40, :millisecond, :native)
    }

    metadata = %{conn: conn, error: "Body read timeout"}

    Telemetry.handle_event([:bandit, :request, :stop], measurements, metadata, nil)

    assert_receive {:telemetry_event, event, timeout_measurements, timeout_metadata}
    assert event == Telemetry.request_timeout_event()
    assert timeout_measurements.duration == measurements.duration

    assert timeout_measurements.body_read_duration ==
             System.convert_time_unit(30, :millisecond, :native)

    assert timeout_metadata == %{method: "POST", route: "/webhooks/github"}
  end

  test "emits a failure event for 5xx responses" do
    conn =
      :get
      |> conn("/api/projects", "")
      |> Map.put(:status, 503)
      |> Map.put(:private, %{phoenix_route: "/api/projects"})

    Telemetry.handle_event([:bandit, :request, :stop], %{}, %{conn: conn}, nil)

    assert_receive {:telemetry_event, event, %{}, metadata}
    assert event == Telemetry.request_failure_event()
    assert metadata == %{method: "GET", route: "/api/projects", reason: "server_error"}
  end

  test "emits a failure event for Bandit exceptions" do
    conn = conn(:get, "/api/projects")

    Telemetry.handle_event(
      [:bandit, :request, :exception],
      %{},
      %{conn: conn, kind: :error, exception: %RuntimeError{message: "boom"}},
      nil
    )

    assert_receive {:telemetry_event, event, %{}, metadata}
    assert event == Telemetry.request_failure_event()
    assert metadata == %{method: "GET", route: "/api/projects", reason: "exception"}
  end

  test "emits a connection drop event for Thousand Island stop errors" do
    Telemetry.handle_event(
      [:thousand_island, :connection, :stop],
      %{},
      %{error: :timeout},
      nil
    )

    assert_receive {:telemetry_event, event, %{}, metadata}
    assert event == Telemetry.connection_drop_event()
    assert metadata == %{reason: "timeout"}
  end

  test "emits a connection error event for recv and send errors" do
    Telemetry.handle_event(
      [:thousand_island, :connection, :recv_error],
      %{},
      %{},
      nil
    )

    assert_receive {:telemetry_event, event, %{}, metadata}
    assert event == Telemetry.connection_error_event()
    assert metadata == %{event: "recv_error"}
  end

  test "logs request timeouts and connection drops" do
    log =
      capture_log(fn ->
        Telemetry.handle_event(
          [:bandit, :request, :stop],
          %{duration: System.convert_time_unit(50, :millisecond, :native)},
          %{conn: conn(:post, "/upload"), error: "Body read timeout"},
          nil
        )

        Telemetry.handle_event(
          [:thousand_island, :connection, :stop],
          %{},
          %{error: :closed},
          nil
        )
      end)

    assert log =~ "Bandit request body timeout"
    assert log =~ "Thousand Island connection dropped"
  end
end
