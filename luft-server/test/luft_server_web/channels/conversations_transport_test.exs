defmodule LuftServerWeb.ConversationsTransportTest do
  use LuftServerWeb.ConnCase, async: false

  alias LuftServer.NativeAuth
  alias LuftServer.Repo

  setup do
    listener =
      start_supervised!({Bandit, plug: LuftServerWeb.Endpoint, port: 0, ip: {127, 0, 0, 1}})

    {:ok, {_ip, port}} = ThousandIsland.listener_info(listener)
    {:ok, port: port}
  end

  test "real native WebSocket authenticates locally and speaks Phoenix without a Tuist relay", %{
    port: port
  } do
    bearer = bearer()
    {client, ref} = upgrade(port, bearer)
    assert {:upgrade, ["websocket"], headers} = :gun.await(client, ref)
    refute inspect(headers) =~ bearer

    :ok =
      :gun.ws_send(client, ref, {:text, Jason.encode!([nil, "1", "phoenix", "heartbeat", %{}])})

    assert {:ws, {:text, frame}} = :gun.await(client, ref)

    assert [nil, "1", "phoenix", "phx_reply", %{"status" => "ok", "response" => %{}}] =
             Jason.decode!(frame)

    Repo.delete!(NativeAuth.resolve_bearer(bearer))
    {revoked, denied} = upgrade(port, bearer)
    assert {:response, :fin, 403, _} = :gun.await(revoked, denied)
    :ok = :gun.ws_send(client, ref, :close)
  end

  test "missing, refresh and malformed credentials are refused before upgrading", %{port: port} do
    for bearer <- [nil, "invalid", "luft_refresh_not-an-access-token"] do
      {client, ref} = upgrade(port, bearer)
      assert {:response, :fin, 403, _} = :gun.await(client, ref)
    end
  end

  defp upgrade(port, bearer) do
    {:ok, client} = :gun.open(~c"127.0.0.1", port, %{protocols: [:http], retry: 0})
    on_exit(fn -> :gun.close(client) end)
    assert {:ok, :http} = :gun.await_up(client)

    protocols =
      if bearer,
        do: [
          {"phoenix", :gun_ws_h},
          {"base64url.bearer.phx." <> Base.encode64(bearer, padding: false), :gun_ws_h}
        ],
        else: [{"phoenix", :gun_ws_h}]

    ref =
      :gun.ws_upgrade(client, "/threads/socket/websocket?vsn=2.0.0", [], %{protocols: protocols})

    {client, ref}
  end

  defp bearer do
    verifier = String.duplicate("x", 43)

    request = %{
      "client_id" => NativeAuth.client_id(),
      "response_type" => "code",
      "redirect_uri" => "luft://oauth-callback",
      "state" => "state",
      "code_challenge_method" => "S256",
      "code_challenge" => :sha256 |> :crypto.hash(verifier) |> Base.url_encode64(padding: false)
    }

    {:ok, callback, _session} =
      NativeAuth.complete(
        %{
          claims: %{"sub" => "42", "preferred_username" => "person"},
          tokens: %{
            "access_token" => "escrowed-upstream",
            "refresh_token" => "refresh",
            "expires_in" => 3600
          }
        },
        request
      )

    query = callback |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

    {:ok, credentials} =
      NativeAuth.exchange(%{
        "grant_type" => "authorization_code",
        "client_id" => NativeAuth.client_id(),
        "code" => query["code"],
        "redirect_uri" => "luft://oauth-callback",
        "code_verifier" => verifier
      })

    credentials.access_token
  end
end
