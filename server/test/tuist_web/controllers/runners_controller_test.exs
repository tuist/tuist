defmodule TuistWeb.RunnersControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners
  alias Tuist.Runners.Claims
  alias Tuist.Runners.Jobs

  describe "GET /api/internal/runners/desired_replicas" do
    test "returns claimed, occupied, queued, and historical concurrency for the fleet", %{conn: conn} do
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
      assert body["occupied"] == 1
      assert body["queued"] == 1
      assert body["withheld"] == 0
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
      assert body["occupied"] == 0
      assert body["queued"] == 0
      assert body["withheld"] == 0
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
    test "returns the GitHub JIT config, workflow_job_id, and a per-job log token", %{conn: conn} do
      account = account_fixture()

      stub(K8sClient, :create_token_review, fn "valid-token" ->
        {:ok, %{namespace: "tuist-runners", name: "pod-1"}}
      end)

      stub(Runners, :dispatch_for_sa, fn "tuist-runners", "pod-1", %{} ->
        {:ok,
         %{
           credential: %{kind: :github, jit: "JITCONFIG"},
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

      assert [%{"group" => "Tuist Runner", "detail" => detail}] = body["setup_info"]
      assert detail =~ "/#{account.name}/runners/by-runner/pod-1"
    end

    test "passes the guest's reported macOS version on and drops one that is not a version", %{conn: conn} do
      test_pid = self()

      stub(K8sClient, :create_token_review, fn "valid-token" ->
        {:ok, %{namespace: "tuist-runners", name: "pod-1"}}
      end)

      stub(Runners, :dispatch_for_sa, fn "tuist-runners", "pod-1", guest ->
        send(test_pid, {:guest, guest})
        {:error, :no_work_yet}
      end)

      dispatch = fn body ->
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> put_req_header("content-type", "application/json")
        |> post("/api/internal/runners/dispatch", JSON.encode!(body))
        |> response(204)
      end

      dispatch.(%{os_version: "26.6"})
      assert_receive {:guest, %{os_version: "26.6"}}

      dispatch.(%{os_version: "26.6\"-evil"})
      assert_receive {:guest, guest}
      assert guest == %{}

      dispatch.(%{})
      assert_receive {:guest, guest}
      assert guest == %{}
    end

    test "returns a Buildkite acquisition token instead of a JIT config", %{conn: conn} do
      account = account_fixture()

      stub(K8sClient, :create_token_review, fn "valid-token" ->
        {:ok, %{namespace: "tuist-runners", name: "pod-1"}}
      end)

      stub(Runners, :dispatch_for_sa, fn "tuist-runners", "pod-1", %{} ->
        {:ok,
         %{
           credential: %{
             kind: :buildkite,
             token: "bkjat_opaque",
             job_uuid: "0189abcd-0000-4000-8000-000000000000",
             organization_slug: "acme",
             report_token: "report-token"
           },
           account: account,
           runner_name: "pod-1",
           workflow_job_id: 1_000_000_000_000_123,
           fleet_on_cluster_network: false,
           fleet_platform: :macos
         }}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/internal/runners/dispatch")

      body = json_response(conn, 200)
      assert body["buildkite_acquisition_token"] == "bkjat_opaque"
      assert body["buildkite_job_uuid"] == "0189abcd-0000-4000-8000-000000000000"
      assert body["buildkite_organization_slug"] == "acme"
      assert body["buildkite_report_token"] == "report-token"
      # The poll script selects the agent to launch on which credential
      # key is present, so the two must never appear together.
      refute Map.has_key?(body, "encoded_jit_config")
      refute Map.has_key?(body, "setup_info")
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
        # Kura.runner_cache_endpoint_url/3).
        last_ready_at: DateTime.truncate(DateTime.utc_now(), :second),
        provisioner_node_ref: "kura-#{account.name}-scw-fr-par-runners"
      })

      stub(K8sClient, :create_token_review, fn "valid-token" ->
        {:ok, %{namespace: "tuist-runners", name: "pod-1"}}
      end)

      dispatch = fn fleet_on_cluster_network, fleet_platform ->
        stub(Runners, :dispatch_for_sa, fn "tuist-runners", "pod-1", %{} ->
          {:ok,
           %{
             credential: %{kind: :github, jit: "JITCONFIG"},
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

      stub(Tuist.Kura, :runner_cache_endpoint_url, fn _account, :linux, nil ->
        "http://kura-acme.kura.svc.cluster.local:4000"
      end)

      base = %{
        credential: %{kind: :github, jit: "JITCONFIG"},
        account: account,
        runner_name: "pod-1",
        workflow_job_id: 4242,
        fleet_platform: :linux
      }

      # Cluster-networked fleet (Linux): the in-cluster URL is handed out.
      stub(Runners, :dispatch_for_sa, fn _, _, _ ->
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
      stub(Runners, :dispatch_for_sa, fn _, _, _ ->
        {:ok, Map.put(base, :fleet_on_cluster_network, false)}
      end)

      off_cluster =
        build_conn()
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/internal/runners/dispatch")
        |> json_response(200)

      refute Map.has_key?(off_cluster, "cache_endpoint_url")
    end

    test "hands a site's fleet the cache racked at its site", %{conn: conn} do
      account = account_fixture()

      stub(K8sClient, :create_token_review, fn "valid-token" ->
        {:ok, %{namespace: "tuist-runners", name: "pod-1"}}
      end)

      stub(Tuist.Kura, :runner_cache_endpoint_url, fn _account, :macos, "ber1" ->
        "https://acme-ber1-runners.kura.tuist.dev"
      end)

      stub(Runners, :dispatch_for_sa, fn _, _, _ ->
        {:ok,
         %{
           credential: %{kind: :github, jit: "JITCONFIG"},
           account: account,
           runner_name: "pod-1",
           workflow_job_id: 4242,
           fleet_on_cluster_network: true,
           fleet_platform: :macos,
           fleet_site: "ber1"
         }}
      end)

      response =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/internal/runners/dispatch")
        |> json_response(200)

      assert response["cache_endpoint_url"] == "https://acme-ber1-runners.kura.tuist.dev"
    end

    test "sends no cache mode to any job", %{conn: conn} do
      account = account_fixture()

      stub(K8sClient, :create_token_review, fn "valid-token" ->
        {:ok, %{namespace: "tuist-runners", name: "pod-1"}}
      end)

      github = %{kind: :github, jit: "JITCONFIG"}

      buildkite = %{
        kind: :buildkite,
        token: "bkjat_opaque",
        job_uuid: "0189abcd-0000-4000-8000-000000000000",
        organization_slug: "acme",
        report_token: "report-token"
      }

      gitlab = %{
        kind: :gitlab,
        url: "https://gitlab.example.com",
        payload: %{},
        report_token: "report-token",
        waiting_trace: nil
      }

      dispatch = fn account, platform, credential ->
        stub(Runners, :dispatch_for_sa, fn _, _, _ ->
          {:ok,
           %{
             credential: credential,
             account: account,
             runner_name: "pod-1",
             workflow_job_id: 4242,
             fleet_on_cluster_network: false,
             fleet_platform: platform
           }}
        end)

        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/internal/runners/dispatch")
        |> json_response(200)
      end

      responses = [
        dispatch.(account, :linux, github)
        | for(credential <- [github, buildkite, gitlab], do: dispatch.(account, :macos, credential))
      ]

      for response <- responses do
        refute Map.has_key?(response, "automatic_caches")
        refute Map.has_key?(response, "managed_cache_volumes")
      end
    end
  end
end
