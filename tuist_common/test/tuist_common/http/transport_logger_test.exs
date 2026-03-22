defmodule TuistCommon.HTTP.TransportLoggerTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias TuistCommon.HTTP.TransportLogger

  setup do
    handler_suffix = System.unique_integer([:positive])
    TransportLogger.attach(handler_suffix)

    on_exit(fn ->
      TransportLogger.detach(handler_suffix)
    end)

    %{handler_suffix: handler_suffix}
  end

  test "logs Bandit body read timeouts with route and connection context", %{
    handler_suffix: _handler_suffix
  } do
    log =
      capture_log(
        [
          format: "$metadata$message",
          metadata: [:request_id, :method, :route, :connection_span_context]
        ],
        fn ->
          :telemetry.execute(
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
            }
          )
        end
      )

    assert log =~ "Bandit request body read timed out"
    assert log =~ "request_id=req_123"
    assert log =~ "method=POST"
    assert log =~ "route=/upload"
    assert log =~ "connection_span_context="
  end

  test "logs Thousand Island drops with normalized reason and remote address", %{
    handler_suffix: _handler_suffix
  } do
    log =
      capture_log(
        [format: "$metadata$message", metadata: [:reason, :remote_address, :recv_oct]],
        fn ->
          :telemetry.execute(
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
            }
          )
        end
      )

    assert log =~ "Thousand Island connection dropped"
    assert log =~ "reason=closed"
    assert log =~ "remote_address=127.0.0.1"
    assert log =~ "recv_oct=64"
  end
end
