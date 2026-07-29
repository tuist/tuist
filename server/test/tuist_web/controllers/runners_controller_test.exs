defmodule TuistWeb.RunnersControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners
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

      {:ok, _} =
        Claims.attempt(7_100_002, account.id, "fleet-scale", "pod-scale-1", %{
          platform: :linux,
          vcpus: 1,
          memory_gb: 1
        })

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
    test "returns the jit, workflow_job_id, and a per-job log token", %{conn: conn} do
      account = account_fixture()

      stub(K8sClient, :create_token_review, fn "valid-token" ->
        {:ok, %{namespace: "tuist-runners", name: "pod-1"}}
      end)

      stub(Runners, :dispatch_for_sa, fn "tuist-runners", "pod-1" ->
        {:ok,
         %{
           jit: "JITCONFIG",
           account: account,
           runner_name: "pod-1",
           workflow_job_id: 4242,
           fleet_on_cluster_network: false,
           fleet_platform: :linux
         }}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/internal/runners/dispatch")

      body = json_response(conn, 200)
      assert body["encoded_jit_config"] == "JITCONFIG"
      assert body["owner"] == account.name
      assert body["workflow_job_id"] == 4242
      refute Map.has_key?(body, "cache_endpoint_url")
    end

    test "routes cache_endpoint_url by fleet platform and cluster-network reachability", %{conn: conn} do
      account = account_fixture()

      # The endpoint lookup goes through `Regions.available/0`, which
      # in test sees only the local controller region — surface the
      # private region the way a managed runtime would.
      stub(Tuist.Environment, :dev?, fn -> false end)
      stub(Tuist.Environment, :test?, fn -> false end)

      stub(Tuist.Environment, :kura_available_region_ids, fn ->
        ["scw-fr-par-runners"]
      end)

      # The only private runner-cache region, serving macOS. Linux has none.
      scw_url = "http://kura-#{account.name}-scw-fr-par.kura.svc.cluster.local:4000"

      Tuist.Repo.insert!(%Tuist.Kura.Server{
        account_id: account.id,
        region: "scw-fr-par-runners",
        status: :active,
        url: scw_url,
        # Fresh readiness heartbeat so the node-port server is served
        # rather than failed over to the public cache (see
        # Kura.runner_cache_endpoint_url/2).
        last_ready_at: DateTime.truncate(DateTime.utc_now(), :second),
        provisioner_node_ref: "kura-#{account.name}-scw-fr-par-runners"
      })

      stub(K8sClient, :create_token_review, fn "valid-token" ->
        {:ok, %{namespace: "tuist-runners", name: "pod-1"}}
      end)

      dispatch = fn fleet_on_cluster_network, fleet_platform ->
        stub(Runners, :dispatch_for_sa, fn "tuist-runners", "pod-1" ->
          {:ok,
           %{
             jit: "JITCONFIG",
             account: account,
             runner_name: "pod-1",
             workflow_job_id: 4242,
             fleet_on_cluster_network: fleet_on_cluster_network,
             fleet_platform: fleet_platform
           }}
        end)

        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/internal/runners/dispatch")
        |> json_response(200)
      end

      # Locality: each platform only ever sees a region that serves it. The
      # Linux fleet must never receive the Scaleway URL — that node is
      # co-located with the macOS fleet on the other side of a WAN — and since
      # no region serves Linux, it gets no URL rather than the wrong one.
      refute Map.has_key?(dispatch.(true, :linux), "cache_endpoint_url")
      assert dispatch.(true, :macos)["cache_endpoint_url"] == scw_url

      # Reachability: a fleet off the cluster network gets no URL at
      # all — clients treat TUIST_CACHE_ENDPOINT as a hard override,
      # so an unreachable URL would break caching outright.
      refute Map.has_key?(dispatch.(false, :macos), "cache_endpoint_url")
      refute Map.has_key?(dispatch.(true, nil), "cache_endpoint_url")
    end

    test "includes cache_endpoint_url only for cluster-networked fleets with an active node",
         %{conn: conn} do
      account = account_fixture()

      stub(K8sClient, :create_token_review, fn "valid-token" ->
        {:ok, %{namespace: "tuist-runners", name: "pod-1"}}
      end)

      stub(Tuist.Kura, :runner_cache_endpoint_url, fn _account, :linux ->
        "http://kura-acme.kura.svc.cluster.local:4000"
      end)

      base = %{
        jit: "JITCONFIG",
        account: account,
        runner_name: "pod-1",
        workflow_job_id: 4242,
        fleet_platform: :linux
      }

      # Cluster-networked fleet (Linux): the in-cluster URL is handed out.
      stub(Runners, :dispatch_for_sa, fn _, _ ->
        {:ok, Map.put(base, :fleet_on_cluster_network, true)}
      end)

      on_cluster =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/internal/runners/dispatch")
        |> json_response(200)

      assert on_cluster["cache_endpoint_url"] == "http://kura-acme.kura.svc.cluster.local:4000"

      # Off-cluster fleet (e.g. macOS Tart on vmnet): URL withheld so the
      # client falls back to default cache resolution instead of getting
      # an unreachable hard override.
      stub(Runners, :dispatch_for_sa, fn _, _ ->
        {:ok, Map.put(base, :fleet_on_cluster_network, false)}
      end)

      off_cluster =
        build_conn()
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/internal/runners/dispatch")
        |> json_response(200)

      refute Map.has_key?(off_cluster, "cache_endpoint_url")
    end
  end

  describe "POST /api/internal/runners/volume-head/upload-url" do
    test "returns a presigned upload URL for the reported digest", %{conn: conn} do
      digest = String.duplicate("a", 40)

      stub(K8sClient, :create_token_review, fn "valid-token" ->
        {:ok, %{namespace: "tuist-runners", name: "pod-1"}}
      end)

      stub(Runners, :account_id_for_sa, fn "tuist-runners", "pod-1" -> {:ok, 77} end)
      stub(Runners, :volume_master_upload_url, fn 77, ^digest -> {:ok, "https://bucket.example.com/put"} end)

      body =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/internal/runners/volume-head/upload-url", %{"tree_digest" => digest})
        |> json_response(200)

      assert body["upload_url"] == "https://bucket.example.com/put"
    end

    test "422 when the digest is rejected", %{conn: conn} do
      stub(K8sClient, :create_token_review, fn "valid-token" ->
        {:ok, %{namespace: "tuist-runners", name: "pod-1"}}
      end)

      stub(Runners, :account_id_for_sa, fn _ns, _sa -> {:ok, 77} end)
      stub(Runners, :volume_master_upload_url, fn 77, "bad" -> :error end)

      body =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/internal/runners/volume-head/upload-url", %{"tree_digest" => "bad"})
        |> json_response(422)

      assert body["error"] == "invalid digest"
    end

    test "401 without a bearer token", %{conn: conn} do
      conn = post(conn, "/api/internal/runners/volume-head/upload-url", %{"tree_digest" => "x"})
      assert json_response(conn, 401)
    end
  end

  describe "POST /api/internal/runners/volume-head" do
    setup %{conn: conn} do
      stub(K8sClient, :create_token_review, fn "valid-token" ->
        {:ok, %{namespace: "tuist-runners", name: "pod-1"}}
      end)

      stub(Runners, :account_id_for_sa, fn "tuist-runners", "pod-1" -> {:ok, 77} end)
      {:ok, conn: put_req_header(conn, "authorization", "Bearer valid-token")}
    end

    test "returns the accepted generation on a fast-forward", %{conn: conn} do
      digest = String.duplicate("a", 40)
      stub(Runners, :report_volume_head, fn 77, "node-1", ^digest, 5 -> {:ok, 6} end)

      body =
        conn
        |> post("/api/internal/runners/volume-head", %{
          "tree_digest" => digest,
          "node_name" => "node-1",
          "base_generation" => 5
        })
        |> json_response(200)

      assert body["generation"] == 6
    end

    test "409 when the fast-forward is rejected as stale", %{conn: conn} do
      digest = String.duplicate("a", 40)
      stub(Runners, :report_volume_head, fn 77, _node, ^digest, _base -> :conflict end)

      body =
        conn
        |> post("/api/internal/runners/volume-head", %{"tree_digest" => digest, "base_generation" => 1})
        |> json_response(409)

      assert body["error"] == "stale base generation"
    end

    test "parses a string base_generation and defaults a missing one to 0", %{conn: conn} do
      digest = String.duplicate("a", 40)
      stub(Runners, :report_volume_head, fn 77, _node, ^digest, base -> {:ok, base + 1} end)

      # A string body value is parsed to an integer.
      assert %{"generation" => 4} =
               conn
               |> post("/api/internal/runners/volume-head", %{"tree_digest" => digest, "base_generation" => "3"})
               |> json_response(200)

      # A missing base_generation is treated as 0 (a cold job).
      assert %{"generation" => 1} =
               conn
               |> post("/api/internal/runners/volume-head", %{"tree_digest" => digest})
               |> json_response(200)
    end

    test "422 when the digest is invalid", %{conn: conn} do
      stub(Runners, :report_volume_head, fn 77, _node, "bad", _base -> :error end)

      body =
        conn
        |> post("/api/internal/runners/volume-head", %{"tree_digest" => "bad", "base_generation" => 0})
        |> json_response(422)

      assert body["error"] == "invalid digest"
    end
  end
end
