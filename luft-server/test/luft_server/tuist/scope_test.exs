defmodule LuftServer.Tuist.ScopeTest do
  use LuftServerWeb.ConnCase, async: true

  alias LuftServer.Sessions
  alias LuftServer.Tuist.Scope

  setup do
    {:ok, _cookie, session} =
      Sessions.create(%{
        claims: %{"sub" => "42", "preferred_username" => "person"},
        tokens: %{
          "access_token" => "upstream-access",
          "refresh_token" => "upstream-refresh",
          "expires_in" => 3600
        }
      })

    %{session: session}
  end

  test "resolves fresh identity and permissions through the escrowed upstream grant", %{
    session: session
  } do
    Req.Test.stub(LuftServer.Tuist, fn conn ->
      assert conn.request_path == "/api/accounts/team/luft-context"
      assert get_req_header(conn, "authorization") == ["Bearer upstream-access"]
      Req.Test.json(conn, body())
    end)

    assert {:ok,
            %Scope{
              user_id: 42,
              account_id: 123,
              organization_id: 789,
              can_create_threads: false,
              people: [%{id: 42, handle: "person", active: true}]
            }} = Scope.load(session, "team")
  end

  test "does not turn upstream failures or mismatched identities into an authorized scope", %{
    session: session
  } do
    for {status, body, error} <- [
          {401, %{}, :unauthorized},
          {403, %{}, :not_found},
          {404, %{}, :not_found},
          {503, %{}, :tuist_unavailable},
          {200, Map.put(body(), :user_id, 43), :tuist_unavailable},
          {200, Map.put(body(), :can_create_threads, "true"), :tuist_unavailable}
        ] do
      Req.Test.stub(LuftServer.Tuist, fn conn ->
        conn |> put_status(status) |> Req.Test.json(body)
      end)

      assert {:error, ^error} = Scope.load(session, "team")
    end
  end

  defp body do
    %{
      user_id: 42,
      account_id: 123,
      organization_id: 789,
      can_create_threads: false,
      people: [%{id: 42, handle: "person", active: true}]
    }
  end
end
