defmodule Tuist.Readiness.PlugTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  import Plug.Conn
  import Plug.Test

  alias Tuist.Readiness

  test "GET /ready answers 200 when every check passes" do
    stub(Oban, :check_queue, fn [queue: :process_xcresult] -> %{paused: false} end)

    conn = call(:get, "/ready", checks: [:postgres, {:oban_queue, :process_xcresult}])

    assert conn.status == 200
    assert ["application/json" <> _] = get_resp_header(conn, "content-type")

    assert JSON.decode!(conn.resp_body) == %{
             "status" => "ok",
             "checks" => %{"postgres" => "ok", "oban_queue_process_xcresult" => "ok"}
           }
  end

  test "GET /ready answers 503 without the failure reason when a check fails" do
    stub(Tuist.Repo, :query, fn "SELECT 1", [], _opts ->
      {:error, %DBConnection.ConnectionError{message: "tcp connect (pooler.tailnet:5432): nxdomain"}}
    end)

    conn = call(:get, "/ready", checks: [:postgres])

    assert conn.status == 503
    assert JSON.decode!(conn.resp_body) == %{"status" => "error", "checks" => %{"postgres" => "error"}}
    refute conn.resp_body =~ "pooler"
  end

  test "other routes are not found" do
    assert call(:get, "/metrics", checks: []).status == 404
    assert call(:post, "/ready", checks: []).status == 404
  end

  defp call(method, path, opts) do
    method
    |> conn(path)
    |> Readiness.Plug.call(Readiness.Plug.init(opts))
  end
end
