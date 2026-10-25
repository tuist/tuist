defmodule Atlas.LLMs.ConnectionsTest do
  use Atlas.DataCase, async: true
  use Mimic

  alias Atlas.Audit.Activity
  alias Atlas.LLMs.ChatGPT
  alias Atlas.LLMs.Connection
  alias Atlas.LLMs.Connections
  alias Atlas.Users.User

  setup do
    user = insert_user()
    stub(ChatGPT, :client_id, fn -> {:ok, "atlas-test-client"} end)
    {:ok, user: user}
  end

  test "credentials are encrypted, redacted and never included in public metadata", %{user: user} do
    token = claude_token()
    assert {:ok, %{credential_configured: true}} = Connections.connect_claude(user, token)
    connection = Repo.get_by!(Connection, user_id: user.id, provider: "claude")
    assert connection.access_token == token
    refute inspect(connection) =~ token
    refute JSON.encode!(Connections.list(user)) =~ token

    result =
      Repo.query!("SELECT access_token FROM user_llm_connections WHERE id = $1", [Ecto.UUID.dump!(connection.id)])

    assert [[ciphertext]] = result.rows
    refute ciphertext == token
    assert :binary.match(ciphertext, token) == :nomatch
    assert {:ok, %{access_token: ^token}} = Connections.credentials(user, "claude")

    assert %Activity{actor_id: actor_id, metadata: metadata} =
             Repo.get_by!(Activity, action: "llm_provider.connected", target_id: user.id)

    assert actor_id == user.id
    assert metadata["path"] == "/settings/llm-providers"
    refute JSON.encode!(metadata) =~ token
  end

  test "owner identity cannot be supplied in credentials and other users cannot see or remove them", %{user: user} do
    other = insert_user()
    assert {:ok, _} = Connections.connect_claude(user, claude_token())
    assert Enum.all?(Connections.list(other), &(!&1.credential_configured))
    assert {:error, :not_connected} = Connections.credentials(other, "claude")
    assert {:ok, _} = Connections.disconnect(other, "claude")
    assert {:ok, _} = Connections.credentials(user, "claude")
    assert {:ok, _} = Connections.disconnect(user, "claude")
    assert {:error, :not_connected} = Connections.credentials(user, "claude")
  end

  test "rejects API keys, malformed setup tokens, control characters and oversized input", %{user: user} do
    for token <- [nil, "", "sk-ant-api03-test", claude_token() <> "\ninvalid", String.duplicate("x", 5000), %{}] do
      assert {:error, :invalid_claude_token} = Connections.connect_claude(user, token)
    end

    assert Repo.aggregate(Connection, :count) == 0
    assert {:error, :unsupported_provider} = Connections.disconnect(user, "unknown")
  end

  test "updating Claude replaces one credential, never creates duplicate provider rows", %{user: user} do
    assert {:ok, _} = Connections.connect_claude(user, claude_token())
    replacement = claude_token() <> "replacement"
    assert {:ok, _} = Connections.connect_claude(user, replacement)
    assert Repo.aggregate(Connection, :count) == 1
    assert {:ok, %{access_token: ^replacement}} = Connections.credentials(user, "claude")
  end

  test "ChatGPT login is user-bound, rate bounded, encrypted and single-use", %{user: user} do
    stub(ChatGPT, :start, fn -> {:ok, device_login()} end)
    login_data = device_login()
    assert {:ok, login} = Connections.start_chatgpt(user)
    assert login.user_code == login_data["user_code"]
    refute Map.has_key?(login, :device_auth_id)
    assert {:error, :login_in_progress} = Connections.start_chatgpt(user)
    assert {:error, :not_found} = Connections.poll_chatgpt(insert_user(), login.login_id)
    assert {:error, :not_found} = Connections.poll_chatgpt(user, "wrong-id")
    assert {:ok, %{status: "pending"}} = Connections.poll_chatgpt(user, login.login_id)
    allow_poll(user)

    expect(ChatGPT, :poll, fn pending ->
      assert pending["device_auth_id"] == login_data["device_auth_id"]
      {:ok, tokens()}
    end)

    assert {:ok, %{status: "connected"}} = Connections.poll_chatgpt(user, login.login_id)
    assert {:error, :not_found} = Connections.poll_chatgpt(user, login.login_id)
    connection = Repo.get_by!(Connection, user_id: user.id, provider: "chatgpt")
    assert connection.pending_login == nil
    assert connection.refresh_token == tokens().refresh_token
    assert {:ok, %{access_token: "test-access-token"}} = Connections.credentials(user, "chatgpt")
  end

  test "expiration and cancellation remove pending credentials but preserve a saved connection", %{user: user} do
    stub(ChatGPT, :start, fn -> {:ok, device_login()} end)
    insert_chatgpt(user)
    assert {:ok, login} = Connections.start_chatgpt(user)
    assert {:ok, %{status: "cancelled"}} = Connections.cancel_chatgpt(user, login.login_id)
    assert {:error, :not_found} = Connections.poll_chatgpt(user, login.login_id)
    assert {:ok, _} = Connections.credentials(user, "chatgpt")

    assert {:ok, login} = Connections.start_chatgpt(user)
    connection = Repo.get_by!(Connection, user_id: user.id, provider: "chatgpt")

    connection
    |> Ecto.Changeset.change(pending_expires_at: DateTime.add(DateTime.utc_now(:second), -1))
    |> Repo.update!()

    assert {:error, :login_expired} = Connections.poll_chatgpt(user, login.login_id)
    assert {:ok, _} = Connections.credentials(user, "chatgpt")
  end

  test "disconnect invalidates pending login rather than allowing later polls to resurrect credentials", %{user: user} do
    stub(ChatGPT, :start, fn -> {:ok, device_login()} end)
    assert {:ok, login} = Connections.start_chatgpt(user)
    assert {:ok, _} = Connections.disconnect(user, "chatgpt")
    assert {:error, :not_found} = Connections.poll_chatgpt(user, login.login_id)
    assert {:error, :not_connected} = Connections.credentials(user, "chatgpt")
  end

  test "refresh rotates credentials, preserves them on transient failure, clears them on rejection", %{user: user} do
    connection = insert_chatgpt(user, DateTime.add(DateTime.utc_now(:second), -1))
    expect(ChatGPT, :refresh, fn "test-refresh-token" -> {:error, :provider_unavailable} end)
    assert {:error, :chatgpt_refresh_failed} = Connections.credentials(user, "chatgpt")
    assert Repo.get!(Connection, connection.id).refresh_token == "test-refresh-token"

    expect(ChatGPT, :refresh, fn "test-refresh-token" -> {:ok, %{tokens() | refresh_token: "rotated-refresh-token"}} end)

    assert {:ok, %{access_token: "test-access-token"}} = Connections.credentials(user, "chatgpt")
    assert Repo.get!(Connection, connection.id).refresh_token == "rotated-refresh-token"

    Repo.get!(Connection, connection.id)
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(:second), -1))
    |> Repo.update!()

    expect(ChatGPT, :refresh, fn "rotated-refresh-token" -> {:error, {:http_status, 401}} end)
    assert {:error, :chatgpt_refresh_failed} = Connections.credentials(user, "chatgpt")
    assert Repo.get!(Connection, connection.id).refresh_token == nil
    assert {:error, :not_connected} = Connections.credentials(user, "chatgpt")
  end

  test "user deletion cascades to provider credentials", %{user: user} do
    assert {:ok, _} = Connections.connect_claude(user, claude_token())
    Repo.delete!(user)
    assert Repo.aggregate(Connection, :count) == 0
  end

  defp insert_user do
    %User{} |> User.changeset(%{email: "llm-#{System.unique_integer([:positive])}@tuist.dev"}) |> Repo.insert!()
  end

  defp claude_token, do: "sk-ant-oat01-" <> String.duplicate("a", 64)

  defp device_login do
    %{
      "device_auth_id" => "private-device-id",
      "user_code" => "CODE-123",
      "client_id" => "atlas-test-client",
      "interval" => 5,
      "verification_url" => "https://auth.openai.com/codex/device"
    }
  end

  defp tokens,
    do: %{
      access_token: "test-access-token",
      refresh_token: "test-refresh-token",
      expires_at: DateTime.add(DateTime.utc_now(:second), 3600)
    }

  defp allow_poll(user) do
    Repo.get_by!(Connection, user_id: user.id, provider: "chatgpt")
    |> Ecto.Changeset.change(next_poll_at: DateTime.add(DateTime.utc_now(:second), -1))
    |> Repo.update!()
  end

  defp insert_chatgpt(user, expires_at \\ DateTime.add(DateTime.utc_now(:second), 3600)) do
    %Connection{user_id: user.id}
    |> Connection.changeset(Map.merge(tokens(), %{provider: "chatgpt", expires_at: expires_at}))
    |> Repo.insert!()
  end
end
