defmodule TuistWeb.RunnerCacheMastersControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.VolumePrefetch

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
