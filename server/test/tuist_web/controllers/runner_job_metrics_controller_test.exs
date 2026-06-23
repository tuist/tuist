defmodule TuistWeb.RunnerJobMetricsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.JobMetrics
  alias Tuist.Runners.Jobs

  defp ok_tokenreview_stub do
    stub(K8sClient, :create_controller_token_review, fn "valid-token" ->
      {:ok, %{namespace: "tuist", name: "tuist-runners-controller"}}
    end)
  end

  defp enqueue(account, workflow_job_id) do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: workflow_job_id,
        account_id: account.id,
        fleet_name: "linux-amd64",
        repository: "tuist/tuist",
        workflow_run_id: workflow_job_id - 1000,
        workflow_name: "CLI",
        run_attempt: 1,
        job_name: "Build",
        head_branch: "main",
        head_sha: "abc"
      })
  end

  defp sample(timestamp, attrs \\ %{}) do
    Map.merge(
      %{
        "timestamp" => timestamp,
        "cpu_usage_percent" => 42.5,
        "cpu_iowait_percent" => 1.2,
        "memory_used_bytes" => 7_516_192_768,
        "memory_total_bytes" => 15_032_385_536,
        "network_bytes_in" => 10_485_760,
        "network_bytes_out" => 5_242_880,
        "disk_used_bytes" => 48_318_382_080,
        "disk_total_bytes" => 68_719_476_736
      },
      attrs
    )
  end

  defp post_metrics(conn, workflow_job_id, body) do
    post(conn, "/api/internal/runners/jobs/#{workflow_job_id}/metrics", body)
  end

  describe "POST /api/internal/runners/jobs/:workflow_job_id/metrics" do
    test "records the batch and returns 204", %{conn: conn} do
      account = account_fixture()
      enqueue(account, 33_001)
      ok_tokenreview_stub()

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post_metrics(33_001, %{
          "account_id" => account.id,
          "samples" => [sample(1_750_000_000.0, %{"cpu_usage_percent" => 88.0})]
        })

      assert response(conn, 204)

      assert [%{timestamp: 1_750_000_000.0, cpu_usage_percent: cpu}] = JobMetrics.list_for_job(33_001)
      assert_in_delta cpu, 88.0, 0.01
    end

    test "returns 204 on an empty sample batch", %{conn: conn} do
      account = account_fixture()
      enqueue(account, 33_002)
      ok_tokenreview_stub()

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post_metrics(33_002, %{"account_id" => account.id, "samples" => []})

      assert response(conn, 204)
      assert JobMetrics.list_for_job(33_002) == []
    end

    test "returns 400 when a sample is missing its timestamp", %{conn: conn} do
      account = account_fixture()
      enqueue(account, 33_003)
      ok_tokenreview_stub()

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post_metrics(33_003, %{
          "account_id" => account.id,
          "samples" => [%{"cpu_usage_percent" => 10.0}]
        })

      assert json_response(conn, 400)["error"] =~ "timestamp"
    end

    test "returns 400 when samples is not a list", %{conn: conn} do
      account = account_fixture()
      enqueue(account, 33_004)
      ok_tokenreview_stub()

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post_metrics(33_004, %{"account_id" => account.id, "samples" => "nope"})

      assert json_response(conn, 400)["error"] =~ "samples"
    end

    test "returns 404 when no job matches the (account, workflow_job_id)", %{conn: conn} do
      account = account_fixture()
      ok_tokenreview_stub()

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post_metrics(33_999, %{
          "account_id" => account.id,
          "samples" => [sample(1_750_000_000.0)]
        })

      assert json_response(conn, 404)["error"] =~ "not found"
    end

    test "returns 401 when the bearer token is missing", %{conn: conn} do
      conn = post_metrics(conn, 33_005, %{"account_id" => 1, "samples" => []})
      assert json_response(conn, 401)["error"] =~ "bearer"
    end

    test "returns 401 when the principal isn't the runners-controller SA", %{conn: conn} do
      stub(K8sClient, :create_controller_token_review, fn _ ->
        {:ok, %{namespace: "other-ns", name: "other-sa"}}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer foreign-token")
        |> post_metrics(33_006, %{"account_id" => 1, "samples" => []})

      assert json_response(conn, 401)["error"] =~ "unauthorized"
    end

    test "returns 503 when kubernetes is unavailable", %{conn: conn} do
      stub(K8sClient, :create_controller_token_review, fn _ -> {:error, :not_in_cluster} end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer any-token")
        |> post_metrics(33_007, %{"account_id" => 1, "samples" => []})

      assert json_response(conn, 503)["error"] =~ "kubernetes"
    end
  end
end
