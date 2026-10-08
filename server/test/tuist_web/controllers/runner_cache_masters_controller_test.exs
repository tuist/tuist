defmodule TuistWeb.RunnerCacheMastersControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.CacheVolumes.Builtin
  alias Tuist.Runners.VolumePrefetch

  describe "POST /api/internal/runners/cache-masters/usage" do
    test "binds a report to the authenticated host, ignoring the body node", %{conn: conn} do
      stub(K8sClient, :create_runner_host_token_review, fn "host-token" ->
        {:ok, %{namespace: "tuist", name: "tart-kubelet-mac-01"}}
      end)

      expect(Builtin, :report, fn "mac-01", %{"node_name" => "other-node"} -> {:ok, %{id: "volume"}} end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer host-token")
        |> post("/api/internal/runners/cache-masters/usage", %{node_name: "other-node"})

      assert json_response(conn, 200) == %{"id" => "volume"}
    end

    test "rejects workflow credentials and unauthenticated callers", %{conn: conn} do
      stub(K8sClient, :create_runner_host_token_review, fn "guest-token" -> {:error, :unauthenticated} end)
      reject(&Builtin.report/2)
      assert conn |> post("/api/internal/runners/cache-masters/usage", %{}) |> response(401)

      assert conn
             |> put_req_header("authorization", "Bearer guest-token")
             |> post("/api/internal/runners/cache-masters/usage", %{})
             |> response(401)
    end

    test "retries reports whose executed-job binding has not arrived", %{conn: conn} do
      stub(K8sClient, :create_runner_host_token_review, fn "host-token" ->
        {:ok, %{namespace: "tuist", name: "tart-kubelet-mac-01"}}
      end)

      expect(Builtin, :report, fn "mac-01", _ -> {:error, :pending} end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer host-token")
        |> post("/api/internal/runners/cache-masters/usage", %{})

      assert json_response(conn, 425) == %{"error" => "execution pending"}
    end

    test "tells the agent to drop reports whose execution binding can no longer arrive", %{conn: conn} do
      stub(K8sClient, :create_runner_host_token_review, fn "host-token" ->
        {:ok, %{namespace: "tuist", name: "tart-kubelet-mac-01"}}
      end)

      expect(Builtin, :report, fn "mac-01", _ -> {:error, :unbound} end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer host-token")
        |> post("/api/internal/runners/cache-masters/usage", %{})

      assert json_response(conn, 410) == %{"error" => "execution unavailable"}
    end
  end

  describe "GET /api/internal/runners/cache-masters" do
    test "answers a host for the Node its ServiceAccount names", %{conn: conn} do
      stub(K8sClient, :create_runner_host_token_review, fn "host-token" ->
        {:ok, %{namespace: "tuist", name: "tart-kubelet-mac-01", uid: "uid"}}
      end)

      expect(VolumePrefetch, :for_node, fn "mac-01" ->
        [
          %{
            account_id: 42,
            volume: "tuist-cache",
            generation: 3,
            digest: "d",
            content_digest: "c",
            download_url: "https://objects.example/m"
          }
        ]
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer host-token")
        |> get("/api/internal/runners/cache-masters")

      assert json_response(conn, 200) == %{
               "masters" => [
                 %{
                   "account_id" => 42,
                   "volume" => "tuist-cache",
                   "generation" => 3,
                   "digest" => "d",
                   "content_digest" => "c",
                   "download_url" => "https://objects.example/m"
                 }
               ]
             }
    end

    test "refuses a token without the host audience", %{conn: conn} do
      stub(K8sClient, :create_runner_host_token_review, fn "runner-token" -> {:error, :unauthenticated} end)
      reject(&VolumePrefetch.for_node/1)

      conn =
        conn
        |> put_req_header("authorization", "Bearer runner-token")
        |> get("/api/internal/runners/cache-masters")

      assert json_response(conn, 401)
    end

    test "refuses a ServiceAccount that is not a host's", %{conn: conn} do
      stub(K8sClient, :create_runner_host_token_review, fn "other-token" ->
        {:ok, %{namespace: "tuist-runners", name: "tuist-runner-pool", uid: "uid"}}
      end)

      reject(&VolumePrefetch.for_node/1)

      conn =
        conn
        |> put_req_header("authorization", "Bearer other-token")
        |> get("/api/internal/runners/cache-masters")

      assert json_response(conn, 401)
    end

    test "refuses a request without a token", %{conn: conn} do
      conn = get(conn, "/api/internal/runners/cache-masters")

      assert json_response(conn, 401) == %{"error" => "missing bearer token"}
    end
  end
end
