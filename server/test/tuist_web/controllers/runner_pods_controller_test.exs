defmodule TuistWeb.RunnerPodsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import Ecto.Query
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Repo
  alias Tuist.Runners.Claim
  alias Tuist.Runners.Claims
  alias Tuist.Runners.InteractiveSessions
  alias Tuist.Runners.RunnerSession
  alias Tuist.Runners.Workers.OrphanedRunnersWorker
  alias Tuist.Runners.WorkflowJob
  alias Tuist.Runners.WorkflowJobs

  defp session_fixture(account, attrs) do
    defaults = %{
      account_id: account.id,
      workflow_job_id: System.unique_integer([:positive]),
      fleet_name: "fleet-podctrl",
      pod_name: "pod-#{System.unique_integer([:positive])}",
      runner_name: "",
      started_at: DateTime.utc_now(),
      ended_at: nil,
      inserted_at: DateTime.truncate(DateTime.utc_now(), :second),
      updated_at: DateTime.truncate(DateTime.utc_now(), :second)
    }

    Repo.insert!(struct(RunnerSession, Map.merge(defaults, Map.new(attrs))))
  end

  defp ok_tokenreview_stub do
    stub(K8sClient, :create_controller_token_review, fn "valid-token" ->
      {:ok, %{namespace: "tuist", name: "tuist-runners-controller"}}
    end)
  end

  describe "POST /api/internal/runners/pods/stopped" do
    test "closes the matching open sessions and returns 204", %{conn: conn} do
      account = account_fixture()
      user = user_fixture()
      pod_name = "tuist-macos-runner-pod-1"
      started_at = ~U[2026-05-26 12:00:00.000000Z]
      ended_at = ~U[2026-05-26 12:05:00.000000Z]

      session_fixture(account, pod_name: pod_name, started_at: started_at)

      {:ok, interactive_session} =
        InteractiveSessions.request_vnc(
          %{
            account_id: account.id,
            workflow_job_id: 99_001,
            fleet_name: "macos-xcode-26-5",
            status: "running",
            pod_name: pod_name
          },
          account,
          user
        )

      ok_tokenreview_stub()

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/internal/runners/pods/stopped", %{
          "pod_name" => pod_name,
          "ended_at" => DateTime.to_iso8601(ended_at)
        })

      assert response(conn, 204)

      [session] = Repo.all(from(s in RunnerSession, where: s.pod_name == ^pod_name))
      assert DateTime.compare(session.ended_at, ended_at) == :eq
      assert Repo.reload!(interactive_session).state == :closed
    end

    test "releases a stranded claim held by the stopped pod so its budget is freed", %{conn: conn} do
      account = account_fixture()
      pod_name = "tuist-linux-runner-stranded-1"

      # A Pod stranded because GitHub ran its claimed job on a different
      # eligible runner: it still holds a `running` claim at stop time.
      queued_job!(account, 99_500)

      {:ok, _} =
        Claims.attempt(99_500, account.id, "fleet-podctrl", pod_name, %{platform: :linux, vcpus: 1, memory_gb: 1})

      :ok = mark_running!(99_500, "runner-stranded")

      ok_tokenreview_stub()

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/internal/runners/pods/stopped", %{
          "pod_name" => pod_name,
          "ended_at" => DateTime.to_iso8601(~U[2026-05-26 14:00:00.000000Z])
        })

      assert response(conn, 204)
      assert Repo.all(from(c in Claim, where: c.pod_name == ^pod_name)) == []
    end

    test "schedules recovery of the released claim's job so dispatch stops skipping it", %{conn: conn} do
      account = account_fixture()
      pod_name = "tuist-linux-runner-stranded-2"

      # Releasing the claim frees the account's budget but leaves the
      # ClickHouse row at `running`, which `pick_queued` skips. Without a
      # targeted recovery the job waits out `OrphanedRunnersWorker`'s
      # 5-minute staleness floor before it can be dispatched again.
      queued_job!(account, 99_501)

      {:ok, _} =
        Claims.attempt(99_501, account.id, "fleet-podctrl", pod_name, %{platform: :linux, vcpus: 1, memory_gb: 1})

      :ok = mark_running!(99_501, "runner-stranded-2")

      ok_tokenreview_stub()

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/internal/runners/pods/stopped", %{
          "pod_name" => pod_name,
          "ended_at" => DateTime.to_iso8601(~U[2026-05-26 14:00:00.000000Z])
        })

      assert response(conn, 204)

      # `pod_name` binds the recovery to this attempt: a delayed run must
      # not act on a row a replacement Pod has since claimed.
      assert_enqueued(worker: OrphanedRunnersWorker, args: %{workflow_job_id: 99_501, pod_name: pod_name})
    end

    test "schedules recovery for a job the stopped pod left running after its claim was already released", %{
      conn: conn
    } do
      pod_name = "tuist-linux-runner-mismatch-1"

      # GitHub binds a JIT runner by label set, so the Pod minted for
      # this job often executes a sibling's instead. That sibling's
      # `completed` webhook releases this Pod's claim by executor, so by
      # the time the Pod stops there is no claim left to release — while
      # the job it was minted for is still sitting at `running`, which
      # `pick_queued/2` skips. Keying recovery on the claim delete misses
      # exactly this population; the Pod stopping is proof the job is not
      # executing on it either way.
      running_job!(99_502, pod_name)

      ok_tokenreview_stub()

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/internal/runners/pods/stopped", %{
          "pod_name" => pod_name,
          "ended_at" => DateTime.to_iso8601(~U[2026-05-26 14:00:00.000000Z])
        })

      assert response(conn, 204)
      assert_enqueued(worker: OrphanedRunnersWorker, args: %{workflow_job_id: 99_502, pod_name: pod_name})
    end

    test "schedules no recovery for a job left running by a different pod", %{conn: conn} do
      # The binding runs both ways: a stopped Pod must not drag a
      # replacement's row back through recovery.
      running_job!(99_503, "tuist-linux-runner-replacement")

      ok_tokenreview_stub()

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/internal/runners/pods/stopped", %{
          "pod_name" => "tuist-linux-runner-stopped",
          "ended_at" => DateTime.to_iso8601(~U[2026-05-26 14:00:00.000000Z])
        })

      assert response(conn, 204)
      refute_enqueued(worker: OrphanedRunnersWorker)
    end

    test "schedules no recovery when the stopped pod left no running job", %{conn: conn} do
      ok_tokenreview_stub()

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/internal/runners/pods/stopped", %{
          "pod_name" => "tuist-linux-runner-idle-warm",
          "ended_at" => DateTime.to_iso8601(~U[2026-05-26 14:00:00.000000Z])
        })

      assert response(conn, 204)
      refute_enqueued(worker: OrphanedRunnersWorker)
    end

    test "returns 204 when no open session matches (idempotent / out-of-order delivery)", %{conn: conn} do
      ok_tokenreview_stub()

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/internal/runners/pods/stopped", %{
          "pod_name" => "ghost-pod",
          "ended_at" => DateTime.to_iso8601(~U[2026-05-26 13:00:00.000000Z])
        })

      assert response(conn, 204)
    end

    test "returns 400 when pod_name is missing", %{conn: conn} do
      ok_tokenreview_stub()

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/internal/runners/pods/stopped", %{
          "ended_at" => DateTime.to_iso8601(DateTime.utc_now())
        })

      assert json_response(conn, 400)["error"] =~ "pod_name"
    end

    test "returns 400 when ended_at is missing", %{conn: conn} do
      ok_tokenreview_stub()

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/internal/runners/pods/stopped", %{"pod_name" => "pod-x"})

      assert json_response(conn, 400)["error"] =~ "ended_at"
    end

    test "returns 400 when ended_at isn't ISO-8601", %{conn: conn} do
      ok_tokenreview_stub()

      conn =
        conn
        |> put_req_header("authorization", "Bearer valid-token")
        |> post("/api/internal/runners/pods/stopped", %{
          "pod_name" => "pod-x",
          "ended_at" => "yesterday"
        })

      assert json_response(conn, 400)["error"] =~ "invalid"
    end

    test "returns 401 when bearer token is missing", %{conn: conn} do
      conn = post(conn, "/api/internal/runners/pods/stopped", %{"pod_name" => "pod-x"})
      assert json_response(conn, 401)["error"] =~ "bearer"
    end

    test "returns 401 when TokenReview rejects the token", %{conn: conn} do
      stub(K8sClient, :create_controller_token_review, fn _ -> {:error, :unauthenticated} end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer bad-token")
        |> post("/api/internal/runners/pods/stopped", %{
          "pod_name" => "pod-x",
          "ended_at" => DateTime.to_iso8601(DateTime.utc_now())
        })

      assert json_response(conn, 401)["error"] =~ "invalid"
    end

    test "returns 401 when the principal isn't the runners-controller SA", %{conn: conn} do
      # Any in-cluster workload could present a valid SA token, but
      # only the runners-controller is allowed to close billing
      # sessions. Tokens from any other SA must be rejected.
      stub(K8sClient, :create_controller_token_review, fn _ ->
        {:ok, %{namespace: "other-ns", name: "other-sa"}}
      end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer foreign-token")
        |> post("/api/internal/runners/pods/stopped", %{
          "pod_name" => "pod-x",
          "ended_at" => DateTime.to_iso8601(DateTime.utc_now())
        })

      assert json_response(conn, 401)["error"] =~ "unauthorized"
    end

    test "returns 503 when kubernetes is unavailable", %{conn: conn} do
      stub(K8sClient, :create_controller_token_review, fn _ -> {:error, :not_in_cluster} end)

      conn =
        conn
        |> put_req_header("authorization", "Bearer any-token")
        |> post("/api/internal/runners/pods/stopped", %{
          "pod_name" => "pod-x",
          "ended_at" => DateTime.to_iso8601(DateTime.utc_now())
        })

      assert json_response(conn, 503)["error"] =~ "kubernetes"
    end
  end

  # Production threads the caller's own claim handle into `mark_running/3`;
  # these tests only need "promote the claim that exists", so they read it
  # back. The guard itself is covered in the `mark_running/3` describe.
  defp queued_job!(account, workflow_job_id) do
    :ok =
      WorkflowJobs.upsert_queued(%{
        workflow_job_id: workflow_job_id,
        account_id: account.id,
        fleet_name: "fleet-podctrl",
        platform: "linux",
        vcpus: 1,
        memory_gb: 1,
        repository: "acme/cli",
        workflow_run_id: workflow_job_id * 10,
        workflow_name: "CI",
        run_attempt: 1,
        job_name: "build",
        head_branch: "main",
        head_sha: "deadbeef",
        requested_dispatch_label: "tuist-linux",
        enqueued_at: DateTime.utc_now()
      })
  end

  defp running_job!(workflow_job_id, pod_name) do
    account = account_fixture()
    now = DateTime.utc_now()

    Repo.insert!(%WorkflowJob{
      workflow_job_id: workflow_job_id,
      account_id: account.id,
      fleet_name: "fleet-podctrl",
      status: "running",
      repository: "acme/cli",
      pod_name: pod_name,
      runner_name: "runner-#{workflow_job_id}",
      enqueued_at: now,
      claimed_at: now,
      started_at: now,
      inserted_at: DateTime.truncate(now, :second),
      updated_at: DateTime.truncate(now, :second)
    })
  end

  defp mark_running!(workflow_job_id, runner_name) do
    claim = Repo.get!(Claim, workflow_job_id)
    Claims.mark_running(workflow_job_id, runner_name, claim.claimed_at)
  end
end
