defmodule TuistWeb.SandboxAllocationsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Repo
  alias Tuist.Sandboxes.SandboxNode

  defp payload do
    %{
      "node" => "allocation-#{TuistTestSupport.Utilities.unique_integer()}",
      "pod" => "sandboxd-test",
      "observed_at" => DateTime.to_iso8601(DateTime.utc_now()),
      "memory_bytes" => 10_737_418_240,
      "free_bytes" => 1_073_741_824,
      "reclaim" => false
    }
  end

  test "only the controller service account can publish allocations", %{conn: conn} do
    assert conn |> post("/api/internal/sandboxes/allocation", payload()) |> response(401)
    stub(K8sClient, :create_controller_token_review, fn "other" -> {:ok, %{namespace: "tuist", name: "other"}} end)

    assert conn
           |> put_req_header("authorization", "Bearer other")
           |> post("/api/internal/sandboxes/allocation", payload())
           |> response(401)
  end

  test "persists a grant, rejects replay and validates the payload", %{conn: conn} do
    stub(K8sClient, :create_controller_token_review, fn "controller" ->
      {:ok, %{namespace: "tuist", name: "tuist-runners-controller"}}
    end)

    conn = put_req_header(conn, "authorization", "Bearer controller")
    payload = payload()
    assert conn |> post("/api/internal/sandboxes/allocation", payload) |> response(204)
    assert Repo.get!(SandboxNode, payload["node"]).allocation_memory_bytes == payload["memory_bytes"]
    assert conn |> post("/api/internal/sandboxes/allocation", payload) |> response(409)
    assert conn |> post("/api/internal/sandboxes/allocation", Map.put(payload, "memory_bytes", -1)) |> response(400)

    for field <- ["node", "pod", "observed_at"] do
      assert conn |> post("/api/internal/sandboxes/allocation", Map.put(payload, field, 123)) |> response(400)
    end
  end
end
