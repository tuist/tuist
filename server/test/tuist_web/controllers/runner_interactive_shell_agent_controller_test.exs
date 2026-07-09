defmodule TuistWeb.RunnerInteractiveShellAgentControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use Mimic

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Kubernetes.Client, as: K8sClient
  alias Tuist.Runners.InteractiveSessions

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
