defmodule TuistCommon.RequestLoggerPlugTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog
  import Plug.Conn
  import Plug.Test

  alias TuistCommon.RequestLoggerPlug

  @capture_opts [
    level: :info,
    format: "$metadata[$level] $message",
    metadata: [:method, :route, :request_path, :status, :duration_ms]
  ]

  defp run(request_path, status, opts \\ []) do
    delay = Keyword.get(opts, :delay_ms, 0)

    capture_log(@capture_opts, fn ->
      :get
      |> conn("#{request_path}?token=secret")
      |> put_private(:phoenix_route, "/projects/:project")
      |> RequestLoggerPlug.call([])
      |> then(fn conn ->
        if delay > 0, do: Process.sleep(delay)
        send_resp(conn, status, "")
      end)
    end)
  end

  defp entries(log, request_path) do
    log
    |> String.split("\n")
    |> Enum.filter(
      &(String.contains?(&1, "request_path=#{request_path}") and
          String.contains?(&1, "Request completed"))
    )
  end

  defp unique_path, do: "/projects/request-#{System.unique_integer([:positive, :monotonic])}"

  test "logs one structured entry when the request fails" do
    request_path = unique_path()

    assert [entry] = request_path |> run(500) |> entries(request_path)

    assert entry =~ "[info] Request completed"
    assert entry =~ "method=GET"
    assert entry =~ "route=/projects/:project"
    assert entry =~ "status=500"
    assert entry =~ "duration_ms="
    refute entry =~ "token=secret"
  end

  test "logs client errors" do
    request_path = unique_path()

    assert [entry] = request_path |> run(404) |> entries(request_path)
    assert entry =~ "status=404"
  end

  test "logs a slow successful request" do
    request_path = unique_path()

    assert [entry] = request_path |> run(204, delay_ms: 550) |> entries(request_path)
    assert entry =~ "status=204"
  end

  test "does not log a fast successful request" do
    request_path = unique_path()

    assert [] = request_path |> run(204) |> entries(request_path)
  end

  test "does not log a fast redirect" do
    request_path = unique_path()

    assert [] = request_path |> run(302) |> entries(request_path)
  end
end
