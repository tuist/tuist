defmodule TuistWeb.RunnerJobMetricsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Environment
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.JobMetrics
  alias Tuist.Runners.RunnerSessions

  # The runner presents its own per-pod SA token (audience
  # tuist-runners-dispatch); the SA name equals the Pod name. Stub the
  # TokenReview to return that principal for `pod_name`.
  defp runner_token_stub(pod_name) do
    stub(K8sClient, :create_token_review, fn "valid-token" ->
      {:ok, %{namespace: Environment.runners_namespace(), name: pod_name, uid: "uid-1"}}
    end)
  end

  # An open session for `pod_name`, as dispatch opens it at claim-win.
  # `claimed_job_id` is the job the Pod was minted for — which is NOT
  # necessarily the one GitHub runs on it.
  defp session(account, claimed_job_id, pod_name, runner_name) do
    {:ok, session} =
      RunnerSessions.open(%{
        workflow_job_id: claimed_job_id,
        account_id: account.id,
        fleet_name: "linux-amd64",
        pod_name: pod_name,
        runner_name: runner_name,
        started_at: DateTime.utc_now()
      })

    session
  end

  # GitHub proves, via workflow_job.in_progress, that `runner_name` is
  # running `executed_job_id`.
  defp prove_execution(account, runner_name, executed_job_id) do
    RunnerSessions.record_execution(runner_name, executed_job_id, account.id)
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

  defp post_metrics(conn, pod_name, body) do
    post(conn, "/api/internal/runners/pods/#{pod_name}/metrics", body)
  end

  describe "POST /api/internal/runners/pods/:pod_name/metrics" do
    test "records the batch under the job GitHub proved the Pod is running", %{conn: conn} do
      account = account_fixture()
      session(account, 33_001, "runner-pod-1", "runner-1")
      prove_execution(account, "runner-1", 33_001)
      runner_token_stub("runner-pod-1")

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post_metrics("runner-pod-1", %{
          "samples" => [sample(1_750_000_000.0, %{"cpu_usage_percent" => 88.0})]
        })

      assert response(conn, 204)

      assert [%{timestamp: 1_750_000_000.0, cpu_usage_percent: cpu}] = JobMetrics.list_for_job(33_001)
      assert_in_delta cpu, 88.0, 0.01
    end

    test "records under the executed job, not the job the Pod was minted for", %{conn: conn} do
      # GitHub ran a different job on this runner than the one its
      # claim was minted for. Samples must follow execution, or the
      # claimed job's chart shows another Pod's run.
      account = account_fixture()
      session(account, 33_010, "runner-pod-x", "runner-x")
      prove_execution(account, "runner-x", 33_099)
      runner_token_stub("runner-pod-x")

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post_metrics("runner-pod-x", %{"samples" => [sample(1_750_000_000.0)]})

      assert response(conn, 204)
      assert JobMetrics.list_for_job(33_099) != []
      assert JobMetrics.list_for_job(33_010) == []
    end

    test "records for a Pod executing a job it never claimed and holds no claim for", %{conn: conn} do
      # The issue's J2-cancellation scenario: B claimed J2, J2 was
      # cancelled, and GitHub handed B the job J1 that A claimed. B has
      # no live claim of its own, but its samples are real and must land
      # on J1.
      account = account_fixture()
      session(account, 33_020, "runner-pod-b", "runner-b")
      prove_execution(account, "runner-b", 33_021)
      runner_token_stub("runner-pod-b")

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post_metrics("runner-pod-b", %{"samples" => [sample(1_750_000_000.0)]})

      assert response(conn, 204)
      assert JobMetrics.list_for_job(33_021) != []
    end

    test "returns 204 on an empty sample batch", %{conn: conn} do
      account = account_fixture()
      session(account, 33_002, "runner-pod-2", "runner-2")
      prove_execution(account, "runner-2", 33_002)
      runner_token_stub("runner-pod-2")

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post_metrics("runner-pod-2", %{"samples" => []})

      assert response(conn, 204)
      assert JobMetrics.list_for_job(33_002) == []
    end

    test "returns 204 without recording when the Pod has no session", %{conn: conn} do
      runner_token_stub("unclaimed-pod")
      reject(&JobMetrics.record/3)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post_metrics("unclaimed-pod", %{"samples" => [sample(1_750_000_000.0)]})

      assert response(conn, 204)
    end

    test "does not attribute an idle runner's samples before GitHub proves execution", %{conn: conn} do
      # The Pod registered and is waiting for an assignment that may
      # never come. Falling back to its claimed job would chart this
      # idle CPU on a job running on a different Pod entirely.
      account = account_fixture()
      session(account, 33_030, "runner-pod-idle", "runner-idle")
      runner_token_stub("runner-pod-idle")
      reject(&JobMetrics.record/3)

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post_metrics("runner-pod-idle", %{"samples" => [sample(1_750_000_000.0)]})

      assert response(conn, 204)
    end

    test "returns 400 when a sample is missing its timestamp", %{conn: conn} do
      account = account_fixture()
      session(account, 33_003, "runner-pod-3", "runner-3")
      runner_token_stub("runner-pod-3")

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post_metrics("runner-pod-3", %{"samples" => [%{"cpu_usage_percent" => 10.0}]})

      assert json_response(conn, 400)["error"] =~ "timestamp"
    end

    test "returns 400 when samples is not a list", %{conn: conn} do
      account = account_fixture()
      session(account, 33_004, "runner-pod-4", "runner-4")
      runner_token_stub("runner-pod-4")

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post_metrics("runner-pod-4", %{"samples" => "nope"})

      assert json_response(conn, 400)["error"] =~ "samples"
    end

    test "returns 401 when the bearer token is missing", %{conn: conn} do
      conn = post_metrics(conn, "runner-pod-5", %{"samples" => []})
      assert json_response(conn, 401)["error"] =~ "bearer"
    end

    test "returns 401 when the token's SA is not this Pod's", %{conn: conn} do
      # Token authenticates as a different Pod's SA than the one in the
      # path — a Pod must not be able to write another Pod's metrics.
      stub(K8sClient, :create_token_review, fn _ ->
        {:ok, %{namespace: Environment.runners_namespace(), name: "some-other-pod", uid: "uid-2"}}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer foreign-token")
        |> post_metrics("runner-pod-6", %{"samples" => []})

      assert json_response(conn, 401)["error"] =~ "unauthorized"
    end

    test "returns 503 when kubernetes is unavailable", %{conn: conn} do
      stub(K8sClient, :create_token_review, fn _ -> {:error, :not_in_cluster} end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer any-token")
        |> post_metrics("runner-pod-7", %{"samples" => []})

      assert json_response(conn, 503)["error"] =~ "kubernetes"
    end
  end
end
