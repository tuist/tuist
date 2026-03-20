defmodule TuistCommon.HTTP.TransportLoggerTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias TuistCommon.HTTP.TransportLogger

  test "logs Bandit body read timeouts with route and connection context" do
    log =
      capture_log(
        [
          format: "$metadata$message",
          metadata: [:request_id, :method, :route, :connection_span_context]
        ],
        fn ->
          TransportLogger.handle_event(
            [:bandit, :request, :stop],
            %{duration: System.convert_time_unit(2, :millisecond, :native), req_body_bytes: 128},
            %{
              error: "Body read timeout",
              telemetry_span_context: make_ref(),
              connection_telemetry_span_context: make_ref(),
              conn: %{
                method: "POST",
                private: %{phoenix_route: "/upload"},
                resp_headers: [{"x-request-id", "req_123"}]
              }
            },
            nil
          )
        end
      )

    assert log =~ "Bandit request body read timed out"
    assert log =~ "request_id=req_123"
    assert log =~ "method=POST"
    assert log =~ "route=/upload"
    assert log =~ "connection_span_context="
  end

  test "logs Thousand Island drops with normalized reason and remote address" do
    log =
      capture_log(
        [format: "$metadata$message", metadata: [:reason, :remote_address, :recv_oct]],
        fn ->
          TransportLogger.handle_event(
            [:thousand_island, :connection, :stop],
            %{
              duration: System.convert_time_unit(3, :millisecond, :native),
              recv_oct: 64,
              send_oct: 32
            },
            %{
              telemetry_span_context: make_ref(),
              remote_address: {127, 0, 0, 1},
              remote_port: 4000,
              error: :closed
            },
            nil
          )
        end
      )

    assert log =~ "Thousand Island connection dropped"
    assert log =~ "reason=closed"
    assert log =~ "remote_address=127.0.0.1"
    assert log =~ "recv_oct=64"
  end
end
