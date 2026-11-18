defmodule Tuist.Accounts.MCPServersConcurrencyTest do
  use ExUnit.Case, async: false
  use Mimic

  import Ecto.Query
  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Ecto.Adapters.SQL.Sandbox
  alias Tuist.Accounts.MCPServers
  alias Tuist.Accounts.UserMCPServer
  alias Tuist.OAuth2.PinnedHTTP
  alias Tuist.OAuth2.SSRFGuard
  alias Tuist.Repo

  setup do
    :ok = Sandbox.checkout(Repo, sandbox: false)
    user = user_fixture()
    stub(SSRFGuard, :pin, fn url -> {:ok, url, URI.parse(url).host} end)

    on_exit(fn ->
      :ok = Sandbox.checkout(Repo, sandbox: false)
      Repo.delete_all(from(s in UserMCPServer, where: s.user_id == ^user.id))
      Repo.delete!(user.account)
      Repo.delete!(user)
      Sandbox.checkin(Repo)
    end)

    %{user: user, server: insert_expired_server(user)}
  end

  test "concurrent reads of an expired token refresh it once, so a rotating refresh token is spent once", %{
    user: user,
    server: server
  } do
    parent = self()

    stub(PinnedHTTP, :request, fn _method, _url, opts ->
      send(parent, {:refresh, URI.decode_query(opts[:body])["refresh_token"]})
      # Hold the exchange open so the other readers queue behind it.
      Process.sleep(100)

      {:ok,
       %{
         status: 200,
         headers: [],
         body: JSON.encode!(%{"access_token" => "access-2", "refresh_token" => "refresh-2", "expires_in" => 3600})
       }}
    end)

    results = concurrent(fn -> MCPServers.credentials(user, server.id) end)

    assert Enum.all?(results, &match?({:ok, %{access_token: "access-2"}}, &1))
    assert_received {:refresh, "refresh-1"}
    refute_received {:refresh, _}
    assert %{refresh_token: "refresh-2"} = Repo.get!(UserMCPServer, server.id)
  end

  test "a removal during a refresh does not wait for the authorization server and is not undone", %{
    user: user,
    server: server
  } do
    parent = self()

    stub(PinnedHTTP, :request, fn _method, _url, _opts ->
      send(parent, :refreshing)
      Process.sleep(500)
      {:ok, %{status: 200, headers: [], body: JSON.encode!(%{"access_token" => "access-2", "expires_in" => 3600})}}
    end)

    refresh = Task.async(fn -> in_own_transaction(fn -> MCPServers.credentials(user, server.id) end) end)
    assert_receive :refreshing

    # No lock is held across the token request, so the removal completes while it is in flight.
    assert :ok = MCPServers.remove(user, server.id)
    assert Task.yield(refresh, 0) == nil

    assert {:error, :not_found} = Task.await(refresh)
    refute Repo.get(UserMCPServer, server.id)
  end

  defp insert_expired_server(user) do
    {:ok, server} = MCPServers.add(user, %{"url" => "https://mcp.example.com/mcp"})

    server
    |> UserMCPServer.changeset(%{
      token_endpoint: "https://auth.example.com/token",
      client_id: "registered-client",
      access_token: "access-1",
      refresh_token: "refresh-1",
      expires_at: DateTime.add(DateTime.utc_now(:second), -10)
    })
    |> Repo.update!()
  end

  defp concurrent(fun) do
    parent = self()

    tasks =
      for _ <- 1..8 do
        Task.async(fn ->
          send(parent, {:ready, self()})
          receive do: (:go -> :ok)
          in_own_transaction(fun)
        end)
      end

    pids = for _ <- tasks, do: receive(do: ({:ready, pid} -> pid))
    Enum.each(pids, &send(&1, :go))
    Task.await_many(tasks, 30_000)
  end

  defp in_own_transaction(fun) do
    :ok = Sandbox.checkout(Repo, sandbox: false)

    try do
      fun.()
    after
      Sandbox.checkin(Repo)
    end
  end
end
