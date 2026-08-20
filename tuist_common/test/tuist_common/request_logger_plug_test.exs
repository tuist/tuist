defmodule TuistCommon.RequestLoggerPlugTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Plug.Conn
  import Plug.Test

  alias TuistCommon.RequestLoggerPlug

  test "logs one structured entry when the request completes" do
    request_path = "/projects/request-#{System.unique_integer([:positive, :monotonic])}"

    log =
      capture_log(
        [
          level: :info,
          format: "$metadata[$level] $message",
          metadata: [:method, :route, :request_path, :status, :duration_ms]
        ],
        fn ->
          :get
          |> conn("#{request_path}?token=secret")
          |> put_private(:phoenix_route, "/projects/:project")
          |> RequestLoggerPlug.call([])
          |> send_resp(204, "")
        end
      )

    assert [entry] =
             log
             |> String.split("\n")
             |> Enum.filter(
               &(String.contains?(&1, "request_path=#{request_path}") and
                   String.contains?(&1, "Request completed"))
             )

    assert entry =~ "[info] Request completed"
    assert entry =~ "method=GET"
    assert entry =~ "route=/projects/:project"
    assert entry =~ "status=204"
    assert entry =~ "duration_ms="
    refute entry =~ "token=secret"
  end
end
