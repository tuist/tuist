defmodule TuistWeb.API.RunnerInteractiveShellSessionControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false

  alias Tuist.Repo
  alias Tuist.Runners.InteractiveSession
  alias Tuist.Runners.Jobs
  alias TuistTestSupport.Fixtures.AccountsFixtures

  defp running_job(account, workflow_job_id, workflow_run_id, pod_name \\ "pod-api-shell") do
    :ok =
      Jobs.enqueue(%{
        workflow_job_id: workflow_job_id,
        account_id: account.id,
        fleet_name: "linux-amd64",
        repository: "tuist/tuist",
        workflow_run_id: workflow_run_id,
        workflow_name: "CLI",
        run_attempt: 1,
        job_name: "Test",
        head_branch: "main",
        head_sha: "abc"
      })

    {:ok, candidate} = Jobs.pick_queued("linux-amd64", [])
    :ok = Jobs.record_claimed(candidate, pod_name, DateTime.utc_now())
    :ok = Jobs.record_running(workflow_job_id, "tuist-runner-shell-api")
  end

  test "creates a shell session from a workflow job id", %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    account = user.account
    running_job(account, 72_001, 720_010)

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{user.token}")
      |> post(~p"/api/runners/interactive/shell", %{job_ref: "72001"})

    response = json_response(conn, 200)

    assert response["workflow_job_id"] == 72_001
    assert response["state"] == "requested"
    assert response["websocket_url"] =~ "/api/runners/interactive/shell/connect"
    assert is_binary(response["websocket_protocol"])

    session = Repo.get_by!(InteractiveSession, workflow_job_id: 72_001, kind: :shell)
    assert session.requested_by_user_id == user.id
  end

  test "creates a shell session from a dashboard job URL", %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    account = user.account
    running_job(account, 72_002, 720_020, "pod-api-shell-url")

    job_url = "https://tuist.dev/#{account.name}/runners/runs/720020/jobs/72002?tab=terminal"

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{user.token}")
      |> post(~p"/api/runners/interactive/shell", %{job_ref: job_url})

    response = json_response(conn, 200)

    assert response["workflow_job_id"] == 72_002
    assert is_binary(response["websocket_protocol"])
  end

  test "rejects completed jobs", %{conn: conn} do
    user = AccountsFixtures.user_fixture()
    account = user.account

    :ok =
      Jobs.enqueue(%{
        workflow_job_id: 72_003,
        account_id: account.id,
        fleet_name: "linux-amd64",
        repository: "tuist/tuist",
        workflow_run_id: 720_030,
        workflow_name: "CLI",
        run_attempt: 1,
        job_name: "Done",
        head_branch: "main",
        head_sha: "abc"
      })

    {:ok, completed} = Jobs.complete(72_003, "success")
    assert completed.status == "completed"

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{user.token}")
      |> post(~p"/api/runners/interactive/shell", %{job_ref: "72003"})

    assert json_response(conn, 422)["message"] =~ "only available while"
  end
end
