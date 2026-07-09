defmodule TuistWeb.RunnerInteractiveVNCControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: false

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Accounts
  alias Tuist.Runners.InteractiveSessions

  defp websocket_headers(conn, token) do
    %{conn | host: "www.example.com", req_headers: [{"host", "www.example.com"} | conn.req_headers]}
    |> put_req_header("connection", "upgrade")
    |> put_req_header("upgrade", "websocket")
    |> put_req_header("sec-websocket-key", 16 |> :crypto.strong_rand_bytes() |> Base.encode64())
    |> put_req_header("sec-websocket-version", "13")
    |> put_req_header("sec-websocket-protocol", token)
  end

  defp ready_vnc_session(account, user) do
    {:ok, session} =
      InteractiveSessions.request_vnc(
        %{
          account_id: account.id,
          workflow_job_id: System.unique_integer([:positive]),
          fleet_name: "macos-xcode-26-5",
          status: "running",
          pod_name: "pod-#{System.unique_integer([:positive])}"
        },
        account,
        user
      )

    {:ok, _session} = InteractiveSessions.mark_vnc_relay_ready(session, "127.0.0.1", 5900)

    session
  end

  test "upgrades when the WebSocket protocol token belongs to the route account and user", %{conn: conn} do
    user = user_fixture()
    account = user.account
    session = ready_vnc_session(account, user)

    conn =
      conn
      |> log_in_user(user)
      |> websocket_headers(session.token)
      |> get(~p"/#{account.name}/runners/interactive/vnc")

    assert conn.state == :upgraded
  end

  test "404s when the WebSocket protocol token is missing", %{conn: conn} do
    user = user_fixture()
    account = user.account

    conn =
      conn
      |> log_in_user(user)
      |> get(~p"/#{account.name}/runners/interactive/vnc")

    assert response(conn, 404) == ""
  end

  test "404s when another account member reuses a token they did not request", %{conn: conn} do
    creator = user_fixture()
    member = user_fixture()

    organization =
      organization_fixture(
        name: "runner-vnc-controller-#{System.unique_integer([:positive])}",
        creator: creator,
        preload: [:account]
      )

    account = organization.account
    :ok = Accounts.add_user_to_organization(member, organization, role: :user)
    session = ready_vnc_session(account, creator)

    conn =
      conn
      |> log_in_user(member)
      |> websocket_headers(session.token)
      |> get(~p"/#{account.name}/runners/interactive/vnc")

    assert response(conn, 404) == ""
  end
end
