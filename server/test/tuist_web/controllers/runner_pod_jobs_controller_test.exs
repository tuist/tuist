defmodule TuistWeb.RunnerPodJobsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Environment
  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Repo
  alias Tuist.Runners.Claims
  alias Tuist.Runners.Concurrency
  alias Tuist.Runners.WorkflowJob
  alias Tuist.Runners.WorkflowJobs

  setup do
    account = account_fixture()
    Concurrency.raise_to_plan_defaults(account, :pro)

    :ok =
      WorkflowJobs.upsert_queued(%{
        workflow_job_id: 9101,
        account_id: account.id,
        fleet_name: "fleet-a",
        platform: "linux",
        vcpus: 1,
        memory_gb: 1,
        repository: "acme/cli",
        workflow_run_id: 500
      })

    {:ok, claim} = Claims.attempt(9101, account.id, "fleet-a", "pod-1", %{platform: :linux, vcpus: 1, memory_gb: 1})
    :ok = Claims.mark_running(9101, "runner-1", claim.claimed_at)

    stub(K8sClient, :create_token_review, fn "pod-1-token" ->
      {:ok, %{namespace: Environment.runners_namespace(), name: "pod-1", uid: "uid-1"}}
    end)

    :ok
  end

  test "frees the claimed job when the Pod's runner started a job of another run", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer pod-1-token")
      |> post("/api/internal/runners/pods/pod-1/job-started", %{"run_id" => 501})

    assert response(conn, 204)
    assert Repo.get!(WorkflowJob, 9101).status == "queued"
  end

  test "refuses a report for another Pod", %{conn: conn} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer pod-1-token")
      |> post("/api/internal/runners/pods/pod-2/job-started", %{"run_id" => 501})

    assert json_response(conn, 401)
    assert Repo.get!(WorkflowJob, 9101).status == "running"
  end
end
