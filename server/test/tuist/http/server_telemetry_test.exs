defmodule Tuist.HTTP.ServerTelemetryTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Plug.Conn
  import Plug.Test

  alias Tuist.HTTP.ServerTelemetry

  describe "handle_event/4 for Bandit request stop" do
    test "re-emits a normalized request event" do
      event_name = Tuist.Telemetry.event_name_http_server_request()
      event_ref = :telemetry_test.attach_event_handlers(self(), [event_name])

      conn =
        :post
        |> conn("/webhooks/github", "")
        |> put_resp_header("x-request-id", "req-123")
        |> Map.put(:status, 408)

      measurements = %{
        duration: System.convert_time_unit(120, :millisecond, :native),
        req_body_start_time: 100,
        req_body_end_time: 140,
        req_body_bytes: 1024,
        resp_start_time: 145,
        resp_end_time: 160
      }

      metadata = %{
        conn: conn,
        error: "Body read timeout"
      }

      ServerTelemetry.handle_event([:bandit, :request, :stop], measurements, metadata, nil)

      assert_receive {^event_name, ^event_ref, normalized_measurements, normalized_metadata}

      assert normalized_measurements.duration == measurements.duration
      assert normalized_measurements.req_body_bytes == 1024
      assert normalized_measurements.req_body_read_duration == 40
      assert normalized_measurements.resp_send_duration == 15
      assert normalized_metadata.request_method == "POST"
      assert normalized_metadata.request_path == "/webhooks/github"
      assert normalized_metadata.route == "/webhooks/github"
      assert normalized_metadata.status == 408
      assert normalized_metadata.status_class == "4xx"
      assert normalized_metadata.request_id == "req-123"
      assert normalized_metadata.result == "request_timeout"
      assert normalized_metadata.error == "Body read timeout"
    end

    test "logs a structured warning when Bandit reports a body timeout" do
      conn =
        :post
        |> conn("/webhooks/cache", "")
        |> put_resp_header("x-request-id", "req-timeout")
        |> Map.put(:status, 408)

      measurements = %{
        duration: System.convert_time_unit(75, :millisecond, :native),
        req_body_start_time: 10,
        req_body_end_time: 50,
        req_body_bytes: 2048
      }

      metadata = %{
        conn: conn,
        error: "Body read timeout"
      }

      log =
        capture_log(fn ->
          ServerTelemetry.handle_event([:bandit, :request, :stop], measurements, metadata, nil)
        end)

      assert log =~ "Bandit request body timeout"
      assert log =~ "route=/webhooks/cache"
      assert log =~ "request_id=req-timeout"
    end
  end

  describe "handle_event/4 for Bandit request exception" do
    test "re-emits a normalized exception event" do
      event_name = Tuist.Telemetry.event_name_http_server_request_exception()
      event_ref = :telemetry_test.attach_event_handlers(self(), [event_name])

      conn =
        :get
        |> conn("/api/projects", "")
        |> Map.put(:status, 500)
        |> Map.put(:private, %{phoenix_route: "/api/projects"})

      metadata = %{
        conn: conn,
        kind: :error,
        exception: %RuntimeError{message: "boom"}
      }

      ServerTelemetry.handle_event([:bandit, :request, :exception], %{}, metadata, nil)

      assert_receive {^event_name, ^event_ref, %{}, normalized_metadata}
      assert normalized_metadata.request_method == "GET"
      assert normalized_metadata.route == "/api/projects"
      assert normalized_metadata.error_kind == :error
      assert normalized_metadata.exception == "RuntimeError"
    end
  end

  describe "handle_event/4 for Thousand Island connection errors" do
    test "re-emits a normalized connection error event" do
      event_name = Tuist.Telemetry.event_name_http_server_connection_error()
      event_ref = :telemetry_test.attach_event_handlers(self(), [event_name])

      metadata = %{telemetry_span_context: make_ref()}
      measurements = %{error: :timeout}

      ServerTelemetry.handle_event(
        [:thousand_island, :connection, :recv_error],
        measurements,
        metadata,
        nil
      )

      assert_receive {^event_name, ^event_ref, %{}, normalized_metadata}
      assert normalized_metadata.event == "recv_error"
      assert normalized_metadata.error == :timeout
      assert normalized_metadata.telemetry_span_context == metadata.telemetry_span_context
    end
  end
end
