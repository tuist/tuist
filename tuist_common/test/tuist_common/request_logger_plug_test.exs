defmodule TuistCommon.RequestLoggerPlugTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog
  import Plug.Conn
  import Plug.Test

  alias TuistCommon.RequestLoggerPlug

  test "logs one structured entry when the request completes" do
    log =
      capture_log(
        [
          level: :info,
          format: "$metadata[$level] $message",
          metadata: [:method, :route, :request_path, :status, :duration_ms]
        ],
        fn ->
          :get
          |> conn("/projects/my-project?token=secret")
          |> put_private(:phoenix_route, "/projects/:project")
          |> RequestLoggerPlug.call([])
          |> send_resp(204, "")
        end
      )

    assert log =~ "[info] Request completed"
    assert log =~ "method=GET"
    assert log =~ "route=/projects/:project"
    assert log =~ "request_path=/projects/my-project"
    assert log =~ "status=204"
    assert log =~ "duration_ms="
    refute log =~ "token=secret"
    assert length(Regex.scan(~r/Request completed/, log)) == 1
  end
end
