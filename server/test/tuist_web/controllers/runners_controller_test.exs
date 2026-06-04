defmodule TuistWeb.RunnersControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import Ecto.Query
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Accounts.Account
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Repo
  alias Tuist.Runners
  alias Tuist.Runners.Claims
  alias Tuist.Runners.Jobs

  describe "GET /api/internal/runners/desired_replicas" do
    test "returns claimed + queued + p95 for the fleet", %{conn: conn} do
      account = enabled_account_fixture()

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

  describe "POST /api/internal/runners/dispatch" do
    test "includes cache fields when dispatch returns them", %{conn: conn} do
      account = account_fixture()

      stub(K8sClient, :create_token_review, fn "valid-token" ->
        {:ok, %{namespace: "tuist-runners", name: "pod-1"}}
      end)

      stub(Runners, :dispatch_for_sa, fn "tuist-runners", "pod-1" ->
        {:ok,
         %{
           jit: "jit-blob",
           account: account,
           runner_name: "pod-1",
           cache_token: "cache-jwt",
           cache_gateway_url: "https://cache-gateway.linux.internal"
         }}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/internal/runners/dispatch")

      body = json_response(conn, 200)
      assert body["encoded_jit_config"] == "jit-blob"
      assert body["owner"] == account.name
      assert body["cache_token"] == "cache-jwt"
      assert body["cache_gateway_url"] == "https://cache-gateway.linux.internal"
    end

    test "omits cache fields when the feature is disabled", %{conn: conn} do
      account = account_fixture()

      stub(K8sClient, :create_token_review, fn "valid-token" ->
        {:ok, %{namespace: "tuist-runners", name: "pod-1"}}
      end)

      stub(Runners, :dispatch_for_sa, fn "tuist-runners", "pod-1" ->
        {:ok, %{jit: "jit-blob", account: account, runner_name: "pod-1", cache_token: nil, cache_gateway_url: nil}}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/internal/runners/dispatch")

      body = json_response(conn, 200)
      assert body["encoded_jit_config"] == "jit-blob"
      assert body["owner"] == account.name
      refute Map.has_key?(body, "cache_token")
      refute Map.has_key?(body, "cache_gateway_url")
    end

    test "returns 204 when there is no work", %{conn: conn} do
      stub(K8sClient, :create_token_review, fn "valid-token" ->
        {:ok, %{namespace: "tuist-runners", name: "pod-1"}}
      end)

      stub(Runners, :dispatch_for_sa, fn "tuist-runners", "pod-1" -> {:error, :no_work_yet} end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/internal/runners/dispatch")

      assert response(conn, 204)
    end
  end

  defp enabled_account_fixture do
    account = account_fixture()

    {1, _} =
      Repo.update_all(
        from(a in Account, where: a.id == ^account.id),
        set: [runner_max_concurrent: 10]
      )

    Repo.reload!(account)
  end
end
