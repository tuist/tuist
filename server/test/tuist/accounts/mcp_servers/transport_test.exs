defmodule Tuist.Accounts.MCPServers.TransportTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts.MCPServers
  alias Tuist.Accounts.MCPServers.Transport
  alias Tuist.Accounts.UserMCPServer
  alias Tuist.OAuth2.PinnedHTTP
  alias Tuist.OAuth2.SSRFGuard
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @url "https://mcp.example.com/mcp"
  @token "private-profile-token"

  setup do
    user = AccountsFixtures.user_fixture()
    server = Repo.insert!(%UserMCPServer{user_id: user.id, name: "Profile", url: @url, access_token: @token})
    stub(SSRFGuard, :pin, fn @url -> {:ok, "https://93.184.216.34/mcp", "mcp.example.com"} end)
    %{user: user, server: server, endpoint: Transport.fingerprint(@url)}
  end

  test "metadata has opaque endpoint fingerprint but no credentials", ctx do
    assert [%{id: id, connected: true, endpoint: endpoint} = metadata] = Transport.connections(ctx.user)
    assert id == ctx.server.id and endpoint == ctx.endpoint
    refute inspect(metadata) =~ @token
    refute Map.has_key?(metadata, :url)
  end

  test "real credential refresh completes before authority is checked again", ctx do
    endpoint = "https://mcp.example.com/token"

    Repo.update!(
      Ecto.Changeset.change(ctx.server,
        expires_at: DateTime.add(DateTime.utc_now(:second), -60),
        refresh_token: "refresh-secret",
        client_id: "client",
        token_endpoint: endpoint
      )
    )

    stub(SSRFGuard, :pin, fn url ->
      {:ok, String.replace(url, "mcp.example.com", "93.184.216.34"), "mcp.example.com"}
    end)

    expect(PinnedHTTP, :request, fn "POST", "https://93.184.216.34/token", opts ->
      assert URI.decode_query(opts[:body])["refresh_token"] == "refresh-secret"

      {:ok,
       %{
         status: 200,
         headers: [],
         body: JSON.encode!(%{access_token: "refreshed-private-token", refresh_token: "rotated", expires_in: 3600})
       }}
    end)

    assert {:error, _} = Transport.discover(ctx.user, ctx.server.id, ctx.endpoint, fn -> false end)
    assert Repo.reload!(ctx.server).access_token == "refreshed-private-token"
  end

  test "SSE frames require a terminator and preserve correlated JSON-RPC messages", ctx do
    stub(PinnedHTTP, :request, fn "POST", _, opts ->
      envelope = JSON.decode!(opts[:body])

      body =
        "event: message\r\ndata: " <>
          JSON.encode!(%{jsonrpc: "2.0", id: envelope["id"], result: default(envelope["method"], envelope)})

      response = %{status: 200, headers: [{"content-type", "text/event-stream"}], body: ""}

      if envelope["method"] != "notifications/initialized" do
        assert {:cont, {_, response}} = opts[:into].({:data, body}, {%{}, response})
        assert {:halt, _} = opts[:into].({:data, "\r\n\r\n"}, {%{}, response})
      end

      {:ok, %{response | body: body <> "\r\n\r\n"}}
    end)

    assert {:ok, [_]} = Transport.discover(ctx.user, ctx.server.id, ctx.endpoint, fn -> true end)
  end

  test "credentials refresh for each dispatch; version/session headers and token echoes are safe", ctx do
    test = self()

    expect(MCPServers, :credentials, 3, fn user, id ->
      assert user.id == ctx.user.id and id == ctx.server.id
      send(test, :credential_read)
      Mimic.call_original(MCPServers, :credentials, [user, id])
    end)

    protocol(fn method, envelope, opts ->
      send(test, {:method, method})
      assert opts[:connect_options][:hostname] == "mcp.example.com"
      assert opts[:connect_options][:transport_opts][:verify] == :verify_peer

      if method != "initialize" do
        assert {"mcp-session-id", "session-1"} in opts[:headers]
        assert {"mcp-protocol-version", "2025-03-26"} in opts[:headers]
      end

      if method == "tools/list", do: %{"tools" => [definition(@token)]}, else: default(method, envelope)
    end)

    assert {:ok, [tool]} = Transport.discover(ctx.user, ctx.server.id, ctx.endpoint, fn -> true end)
    assert tool["description"] == "[REDACTED]"
    for _ <- 1..3, do: assert_received(:credential_read)
    refute_received :credential_read
  end

  test "foreign connection, changed endpoint, unsafe DNS and revoked authority never dispatch", ctx do
    reject(PinnedHTTP, :request, 3)
    stranger = AccountsFixtures.user_fixture()
    assert {:error, _} = Transport.discover(stranger, ctx.server.id, ctx.endpoint, fn -> true end)
    assert {:error, _} = Transport.discover(ctx.user, ctx.server.id, String.duplicate("0", 64), fn -> true end)
    assert {:error, _} = Transport.discover(ctx.user, ctx.server.id, ctx.endpoint, fn -> false end)
    stub(SSRFGuard, :pin, fn _ -> {:error, :unsafe} end)
    assert {:error, _} = Transport.discover(ctx.user, ctx.server.id, ctx.endpoint, fn -> true end)
  end

  test "dispatch errors are uncertain, definitive protocol errors and redacted results are complete", ctx do
    protocol(fn method, envelope, _ ->
      if method == "tools/call", do: {:transport_error, @token}, else: default(method, envelope)
    end)

    assert {:error, :mcp_outcome_unknown} = call(ctx)

    protocol(fn method, envelope, _ ->
      if method == "tools/call", do: {:rpc_error, @token}, else: default(method, envelope)
    end)

    assert {:ok, %{isError: true}} = call(ctx)

    protocol(fn method, envelope, _ ->
      if method == "tools/call",
        do: %{"content" => [%{"type" => "text", "text" => @token}], "structuredContent" => %{@token => @token}},
        else: default(method, envelope)
    end)

    assert {:ok, result} = call(ctx)
    refute JSON.encode!(result) =~ @token
    assert result["structuredContent"] == %{"[REDACTED]" => "[REDACTED]"}
  end

  test "removal while listing tools proves non-dispatch rather than uncertain effect", ctx do
    protocol(fn method, envelope, _ ->
      if method == "tools/list", do: MCPServers.remove(ctx.user, ctx.server.id)
      if method == "tools/call", do: flunk("removed connection must not dispatch")
      default(method, envelope)
    end)

    assert {:ok, %{isError: true}} = call(ctx)
  end

  test "unbounded or remote-ref schemas and argument mismatches are refused", ctx do
    protocol(fn method, envelope, _ ->
      if method == "tools/list",
        do: %{
          "tools" => [put_in(definition()["inputSchema"], %{"type" => "object", "$ref" => "https://private.invalid"})]
        },
        else: default(method, envelope)
    end)

    assert {:error, _} = Transport.discover(ctx.user, ctx.server.id, ctx.endpoint, fn -> true end)

    assert {:ok, %{isError: true}} =
             Transport.call(ctx.user, ctx.server.id, ctx.endpoint, "read", %{"x" => String.duplicate("x", 65_536)}, fn ->
               true
             end)
  end

  defp call(ctx), do: Transport.call(ctx.user, ctx.server.id, ctx.endpoint, "read", %{}, fn -> true end)

  defp definition(description \\ "Read"),
    do: %{"name" => "read", "description" => description, "inputSchema" => %{"type" => "object"}}

  defp default("initialize", _), do: %{"protocolVersion" => "2025-03-26", "capabilities" => %{"tools" => %{}}}
  defp default("notifications/initialized", _), do: %{}
  defp default("tools/list", _), do: %{"tools" => [definition()]}

  defp protocol(handler) do
    stub(PinnedHTTP, :request, fn "POST", "https://93.184.216.34/mcp", opts ->
      assert {"authorization", "Bearer " <> @token} in opts[:headers]
      envelope = JSON.decode!(opts[:body])

      case handler.(envelope["method"], envelope, opts) do
        {:transport_error, secret} ->
          {:error, secret}

        {:rpc_error, secret} ->
          {:ok,
           %{
             status: 200,
             headers: [],
             body: JSON.encode!(%{jsonrpc: "2.0", id: envelope["id"], error: %{code: -1, message: secret}})
           }}

        result ->
          {:ok,
           %{
             status: 200,
             headers: [{"mcp-session-id", "session-1"}],
             body: JSON.encode!(%{jsonrpc: "2.0", id: envelope["id"], result: result})
           }}
      end
    end)
  end
end
