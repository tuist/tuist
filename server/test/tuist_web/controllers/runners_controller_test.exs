defmodule TuistWeb.RunnersControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.Claims
  alias Tuist.Runners.Jobs

  describe "GET /api/internal/runners/desired_replicas" do
    test "returns claimed + queued + p95 for the fleet", %{conn: conn} do
      account = account_fixture()

      :ok =
        Jobs.enqueue(%{
          workflow_job_id: 7_100_001,
          account_id: account.id,
          fleet_name: "fleet-scale",
          repository: "acme/cli",
          workflow_run_id: 10_001,
          run_attempt: 1,
          job_name: "build",
          head_branch: "main",
          head_sha: "deadbeef"
        })

      {:ok, _} = Claims.attempt(7_100_002, account.id, "fleet-scale", "pod-scale-1")

      stub(K8sClient, :create_controller_token_review, fn "valid-token" ->
        {:ok, %{namespace: "tuist-runners-controller", name: "runners-controller"}}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> get("/api/internal/runners/desired_replicas?fleet=fleet-scale")

      body = json_response(conn, 200)
      assert body["fleet"] == "fleet-scale"
      assert body["claimed"] == 1
      assert body["queued"] == 1
      assert is_integer(body["p95_concurrent_last_hour"])
    end

    test "returns zeros for an unknown fleet", %{conn: conn} do
      stub(K8sClient, :create_controller_token_review, fn "valid-token" ->
        {:ok, %{namespace: "tuist-runners-controller", name: "runners-controller"}}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> get("/api/internal/runners/desired_replicas?fleet=fleet-empty")

      body = json_response(conn, 200)
      assert body["fleet"] == "fleet-empty"
      assert body["claimed"] == 0
      assert body["queued"] == 0
      assert body["p95_concurrent_last_hour"] == 0
    end

    test "returns 400 when fleet is missing", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> get("/api/internal/runners/desired_replicas")

      assert json_response(conn, 400)["error"] =~ "fleet"
    end

    test "returns 401 when bearer token is missing", %{conn: conn} do
      conn = get(conn, "/api/internal/runners/desired_replicas?fleet=fleet-x")
      assert json_response(conn, 401)["error"] =~ "bearer"
    end

    test "returns 401 when TokenReview rejects the token", %{conn: conn} do
      stub(K8sClient, :create_controller_token_review, fn _ -> {:error, :unauthenticated} end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer bad-token")
        |> get("/api/internal/runners/desired_replicas?fleet=fleet-x")

      assert json_response(conn, 401)["error"] =~ "invalid"
    end

    test "returns 503 when not in cluster", %{conn: conn} do
      stub(K8sClient, :create_controller_token_review, fn _ -> {:error, :not_in_cluster} end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer any-token")
        |> get("/api/internal/runners/desired_replicas?fleet=fleet-x")

      assert json_response(conn, 503)["error"] =~ "kubernetes"
    end
  end
end
