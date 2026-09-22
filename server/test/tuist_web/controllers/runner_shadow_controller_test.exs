defmodule TuistWeb.RunnerShadowControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.Shadow.Snapshot

  test "only the configured controller may read account-level demand", %{conn: conn} do
    expect(K8sClient, :create_controller_token_review, fn "controller-token" ->
      {:ok, %{namespace: "tuist", name: "tuist-runners-controller"}}
    end)

    expect(Snapshot, :capture, fn -> %{version: 1, complete: true, demand: [], claims: [], accounts: []} end)

    conn =
      conn |> put_req_header("authorization", "Bearer controller-token") |> get("/api/internal/runners/shadow_snapshot")

    assert json_response(conn, 200)["complete"]
    assert get_resp_header(conn, "cache-control") == ["private, no-store"]
  end

  test "rejects runner and unrelated service accounts before reading demand", %{conn: conn} do
    reject(Snapshot, :capture, 0)

    expect(K8sClient, :create_controller_token_review, fn "runner-token" ->
      {:ok, %{namespace: "tuist-runners", name: "runner-pod"}}
    end)

    conn = conn |> put_req_header("authorization", "Bearer runner-token") |> get("/api/internal/runners/shadow_snapshot")
    assert json_response(conn, 401)["error"] == "unauthorized principal"
  end

  test "rejects missing credentials", %{conn: conn} do
    reject(Snapshot, :capture, 0)
    assert conn |> get("/api/internal/runners/shadow_snapshot") |> json_response(401)
  end

  test "fails closed when authentication is unavailable", %{conn: conn} do
    reject(Snapshot, :capture, 0)
    expect(K8sClient, :create_controller_token_review, fn _ -> {:error, :not_in_cluster} end)
    conn = conn |> put_req_header("authorization", "Bearer token") |> get("/api/internal/runners/shadow_snapshot")
    assert json_response(conn, 503)
  end
end
