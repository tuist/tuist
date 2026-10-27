defmodule TuistOpsWeb.HealthControllerTest do
  use TuistOpsWeb.ConnCase, async: true

  test "healthz does not require the database", %{conn: conn} do
    conn = get(conn, "/api/v1/healthz")

    assert conn.status == 200
    assert Jason.decode!(conn.resp_body) == %{"status" => "ok"}
  end

  test "readyz checks the database", %{conn: conn} do
    conn = get(conn, "/api/v1/readyz")

    assert conn.status == 200
    assert Jason.decode!(conn.resp_body) == %{"status" => "ok"}
  end
end
