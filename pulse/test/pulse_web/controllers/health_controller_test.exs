defmodule PulseWeb.HealthControllerTest do
  use PulseWeb.ConnCase, async: true

  test "liveness always answers ok", %{conn: conn} do
    assert %{"status" => "ok"} = conn |> get("/healthz") |> json_response(200)
  end

  test "readiness is ok with the in-memory adapter", %{conn: conn} do
    body = conn |> get("/readyz") |> json_response(200)
    assert body["status"] == "ok"
    assert body["checks"] == %{"query_workers" => "ok"}
  end
end
