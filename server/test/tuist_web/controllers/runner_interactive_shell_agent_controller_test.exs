defmodule TuistWeb.RunnerInteractiveShellAgentControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.InteractiveSessions
  alias Tuist.Runners.RunnerSessions

  test "returns the open shell session for the authenticated runner pod", %{conn: conn} do
    account = account_fixture()
    user = user_fixture()
    pod_name = "pod-shell-agent-controller"

    {:ok, session} =
      InteractiveSessions.request_shell(
        %{
          account_id: account.id,
          workflow_job_id: 73_001,
          fleet_name: "linux-amd64",
          status: "running",
          pod_name: pod_name
        },
        account,
        user
      )

    expect(K8sClient, :create_token_review, fn "valid-token" ->
      {:ok, %{namespace: "tuist-runners", name: pod_name}}
    end)

    conn =
      conn
      |> put_req_header("authorization", "Bearer valid-token")
      |> get(~p"/api/internal/runners/interactive/shell/sessions")

    response = json_response(conn, 200)

    assert response["session_id"] == session.id
    assert response["workflow_job_id"] == 73_001
    assert response["websocket_url"] =~ "/api/internal/runners/interactive/shell/#{session.id}/tunnel"
  end

  test "returns a stale shell session when the authenticated pod has an open runner session", %{conn: conn} do
    account = account_fixture()
    user = user_fixture()
    workflow_job_id = 73_002
    live_pod_name = "pod-shell-agent-controller-live"

    {:ok, session} =
      InteractiveSessions.request_shell(
        %{
          account_id: account.id,
          workflow_job_id: workflow_job_id,
          fleet_name: "macos-xcode-26-5",
          status: "running",
          pod_name: "stale-shell-agent-controller-pod"
        },
        account,
        user
      )

    assert {:ok, _runner_session} =
             RunnerSessions.open(%{
               workflow_job_id: workflow_job_id,
               account_id: account.id,
               fleet_name: "macos-xcode-26-5",
               platform: :macos,
               vcpus: 6,
               memory_gb: 14,
               pod_name: live_pod_name,
               started_at: DateTime.utc_now()
             })

    expect(K8sClient, :create_token_review, fn "valid-token" ->
      {:ok, %{namespace: "tuist-runners", name: live_pod_name}}
    end)

    conn =
      conn
      |> put_req_header("authorization", "Bearer valid-token")
      |> get(~p"/api/internal/runners/interactive/shell/sessions")

    response = json_response(conn, 200)

    assert response["session_id"] == session.id
    assert response["workflow_job_id"] == workflow_job_id
  end

  test "uses the reported pod when it belongs to the authenticated service account", %{conn: conn} do
    account = account_fixture()
    user = user_fixture()
    workflow_job_id = 73_003
    service_account_name = "runner-service-account"
    pod_name = "reported-shell-agent-pod"

    {:ok, session} =
      InteractiveSessions.request_shell(
        %{
          account_id: account.id,
          workflow_job_id: workflow_job_id,
          fleet_name: "macos-xcode-26-5",
          status: "running",
          pod_name: pod_name
        },
        account,
        user
      )

    expect(K8sClient, :create_token_review, fn "valid-token" ->
      {:ok, %{namespace: "tuist-runners", name: service_account_name}}
    end)

    expect(K8sClient, :get_pod, fn "tuist-runners", ^pod_name ->
      {:ok, %{"spec" => %{"serviceAccountName" => service_account_name}}}
    end)

    conn =
      conn
      |> put_req_header("authorization", "Bearer valid-token")
      |> put_req_header("x-tuist-runner-pod-name", pod_name)
      |> get(~p"/api/internal/runners/interactive/shell/sessions")

    response = json_response(conn, 200)

    assert response["session_id"] == session.id
    assert response["workflow_job_id"] == workflow_job_id
  end

  test "rejects a reported pod that does not belong to the authenticated service account", %{conn: conn} do
    expect(K8sClient, :create_token_review, fn "valid-token" ->
      {:ok, %{namespace: "tuist-runners", name: "runner-service-account"}}
    end)

    expect(K8sClient, :get_pod, fn "tuist-runners", "other-shell-agent-pod" ->
      {:ok, %{"spec" => %{"serviceAccountName" => "other-service-account"}}}
    end)

    conn =
      conn
      |> put_req_header("authorization", "Bearer valid-token")
      |> put_req_header("x-tuist-runner-pod-name", "other-shell-agent-pod")
      |> get(~p"/api/internal/runners/interactive/shell/sessions")

    assert json_response(conn, 401)["error"] == "pod identity mismatch"
  end

  test "returns 204 when the pod has no open shell session", %{conn: conn} do
    expect(K8sClient, :create_token_review, fn "valid-token" ->
      {:ok, %{namespace: "tuist-runners", name: "pod-without-shell"}}
    end)

    conn =
      conn
      |> put_req_header("authorization", "Bearer valid-token")
      |> get(~p"/api/internal/runners/interactive/shell/sessions")

    assert response(conn, 204) == ""
  end
end
