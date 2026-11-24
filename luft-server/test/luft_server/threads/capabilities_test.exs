defmodule LuftServer.Threads.CapabilitiesTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL.Sandbox
  alias LuftServer.Repo
  alias LuftServer.Sessions
  alias LuftServer.Threads.Capabilities

  setup do
    owner = Sandbox.start_owner!(Repo, shared: false)
    on_exit(fn -> Sandbox.stop_owner(owner) end)

    {:ok, _, session} =
      Sessions.create(%{
        claims: %{"sub" => "1"},
        tokens: %{
          "access_token" => "owner-token",
          "refresh_token" => "refresh",
          "expires_in" => 3600
        }
      })

    thread = %{owner_session_id: session.id, owner_id: 1, account_id: 10, account_handle: "team"}
    %{thread: thread, session: session}
  end

  test "every request rechecks scope and uses the explicitly bound session", %{thread: thread} do
    Req.Test.stub(LuftServer.Tuist, fn conn ->
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer owner-token"]

      case conn.request_path do
        "/api/accounts/team/luft-context" ->
          Req.Test.json(conn, %{
            user_id: 1,
            account_id: 10,
            organization_id: 5,
            can_create_threads: true,
            people: []
          })

        "/api/accounts/team/workspace-capabilities" ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          assert Jason.decode!(body) == %{"operation" => "show", "sandbox_id" => "sandbox"}
          Req.Test.json(conn, %{result: %{id: "sandbox"}})
      end
    end)

    assert {:ok, %{"id" => "sandbox"}} =
             Capabilities.request(thread, "show", %{sandbox_id: "sandbox"})

    Req.Test.stub(LuftServer.Tuist, fn conn ->
      assert conn.request_path == "/api/accounts/team/luft-context"

      Req.Test.json(conn, %{
        user_id: 1,
        account_id: 10,
        organization_id: 5,
        can_create_threads: false,
        people: []
      })
    end)

    assert {:error, :delegation_unavailable} =
             Capabilities.request(thread, "show", %{sandbox_id: "sandbox"})
  end

  test "missing, foreign and deleted delegation never falls back to another session", %{
    thread: thread,
    session: session
  } do
    assert {:error, :delegation_unavailable} =
             Capabilities.owner(%{thread | owner_session_id: nil})

    assert {:error, :delegation_unavailable} = Capabilities.owner(%{thread | owner_id: 2})
    Repo.delete!(session)
    assert {:error, :delegation_unavailable} = Capabilities.owner(thread)
  end
end
