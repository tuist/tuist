defmodule TuistWeb.RunnerCacheMastersControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.VolumePrefetch

  describe "GET /api/internal/runners/cache-masters" do
    test "names a custom volume's HEAD by the use that published it", %{conn: conn} do
      stub(K8sClient, :create_runner_host_token_review, fn "host-token" ->
        {:ok, %{namespace: "tuist", name: "tart-kubelet-mac-01", uid: "uid"}}
      end)

      expect(VolumePrefetch, :for_node, fn "mac-01", :macos ->
        [
          %{
            kind: "custom",
            id: "use",
            account_id: 42,
            scope: "scope",
            generation: 2,
            image_digest: "d",
            content_digest: "c",
            volume_bytes: 30_000_000_000,
            head_size_bytes: 12_000_000_000,
            reason: "prewarm"
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
                   "kind" => "custom",
                   "id" => "use",
                   "account_id" => 42,
                   "scope" => "scope",
                   "generation" => 2,
                   "image_digest" => "d",
                   "content_digest" => "c",
                   "volume_bytes" => 30_000_000_000,
                   "head_size_bytes" => 12_000_000_000,
                   "reason" => "prewarm"
                 }
               ]
             }
    end

    test "refuses a token without the host audience", %{conn: conn} do
      stub(K8sClient, :create_runner_host_token_review, fn "runner-token" -> {:error, :unauthenticated} end)
      reject(&VolumePrefetch.for_node/2)

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

      reject(&VolumePrefetch.for_node/2)

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
