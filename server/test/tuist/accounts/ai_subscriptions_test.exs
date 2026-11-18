defmodule Tuist.Accounts.AISubscriptionsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts.AISubscriptions
  alias Tuist.Accounts.UserAISubscription
  alias Tuist.Environment
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @claude_token "sk-ant-oat01-" <> String.duplicate("a1B2_c3-", 8)

  setup do
    stub(Environment, :chatgpt_client_id, fn -> "app_test_client" end)
    %{user: AccountsFixtures.user_fixture()}
  end

  describe "connect_claude/2" do
    test "saves a setup token encrypted and lists it without exposing it", %{user: user} do
      assert :ok = AISubscriptions.connect_claude(user, "  #{@claude_token}\n")

      assert [%{provider: :claude, connected: true} = claude, %{provider: :chatgpt, connected: false}] =
               AISubscriptions.list(user)

      refute Map.has_key?(claude, :access_token)
      assert {:ok, %{provider: :claude, access_token: @claude_token}} = AISubscriptions.credentials(user, :claude)

      raw = Repo.one!(from c in "user_ai_subscriptions", select: c.access_token)
      refute raw =~ "sk-ant-oat01"
    end

    test "rejects Anthropic API keys and malformed tokens", %{user: user} do
      assert {:error, :invalid_claude_token} =
               AISubscriptions.connect_claude(user, "sk-ant-api03-" <> String.duplicate("a", 40))

      assert {:error, :invalid_claude_token} = AISubscriptions.connect_claude(user, "sk-ant-oat01-short")
      assert {:error, :invalid_claude_token} = AISubscriptions.connect_claude(user, nil)
      assert {:error, :not_connected} = AISubscriptions.credentials(user, :claude)
    end

    test "disconnect deletes only that provider", %{user: user} do
      other_user = AccountsFixtures.user_fixture()
      :ok = AISubscriptions.connect_claude(user, @claude_token)
      :ok = AISubscriptions.connect_claude(other_user, @claude_token)

      assert :ok = AISubscriptions.disconnect(user, :claude)

      assert {:error, :not_connected} = AISubscriptions.credentials(user, :claude)
      assert {:ok, _} = AISubscriptions.credentials(other_user, :claude)
    end
  end

  describe "ChatGPT device sign-in" do
    test "polls until approved, then serves and refreshes the access token", %{user: user} do
      test_pid = self()

      stub_openai(test_pid, false)

      assert {:ok, %{login_id: login_id, user_code: "ABCD-1234", interval: 5, verification_url: url}} =
               AISubscriptions.start_chatgpt(user)

      assert url == "https://auth.openai.com/codex/device"
      assert_received {:request, _, %{client_id: "app_test_client"}}

      # Before the upstream interval elapses, polling does not reach OpenAI.
      assert {:ok, :pending} = AISubscriptions.poll_chatgpt(user, login_id)
      refute_received {:request, "https://auth.openai.com/api/accounts/deviceauth/token", _}

      allow_next_poll(user)
      assert {:ok, :pending} = AISubscriptions.poll_chatgpt(user, login_id)
      assert_received {:request, "https://auth.openai.com/api/accounts/deviceauth/token", %{"device_auth_id" => "dev-1"}}

      assert {:error, :not_found} = AISubscriptions.poll_chatgpt(user, Ecto.UUID.generate())

      allow_next_poll(user)
      stub_openai(test_pid, true)
      assert {:ok, :connected} = AISubscriptions.poll_chatgpt(user, login_id)

      assert %{"code" => "code-1", "code_verifier" => "verifier-1", "client_id" => "app_test_client"} =
               receive_token_request("authorization_code")

      assert %{provider: :chatgpt, connected: true} = Enum.find(AISubscriptions.list(user), &(&1.provider == :chatgpt))
      assert Repo.get_by!(UserAISubscription, user_id: user.id, provider: :chatgpt).pending_login == nil

      # The token expires within the refresh margin, so credentials refresh it
      # and keep the refresh token the response did not rotate.
      assert {:ok, %{provider: :chatgpt, access_token: "access-2"}} = AISubscriptions.credentials(user, :chatgpt)
      assert %{"refresh_token" => "refresh-1"} = receive_token_request("refresh_token")
      assert {:ok, %{access_token: "access-2"}} = AISubscriptions.credentials(user, :chatgpt)
      refute_received {:request, "https://auth.openai.com/oauth/token", _}
    end

    test "refreshes with the client the tokens were issued to", %{user: user} do
      user
      |> insert_chatgpt_connection(expires_at: DateTime.add(DateTime.utc_now(), -10, :second))
      |> UserAISubscription.changeset(%{client_id: "app_original_client"})
      |> Repo.update!()

      stub(Environment, :chatgpt_client_id, fn -> "app_rotated_client" end)
      test_pid = self()

      stub(Req, :post, fn opts ->
        send(test_pid, {:client_id, opts[:form][:client_id]})
        {:ok, %Req.Response{status: 200, body: %{"access_token" => "access-2", "expires_in" => 3600}}}
      end)

      assert {:ok, %{access_token: "access-2"}} = AISubscriptions.credentials(user, :chatgpt)
      assert_received {:client_id, "app_original_client"}
    end

    test "a rejected refresh requires signing in again", %{user: user} do
      insert_chatgpt_connection(user, expires_at: DateTime.add(DateTime.utc_now(), -10, :second))
      stub(Req, :post, fn _opts -> {:ok, %Req.Response{status: 401, body: %{}}} end)

      assert {:error, :reauthorization_required} = AISubscriptions.credentials(user, :chatgpt)
      assert %{connected: false} = Enum.find(AISubscriptions.list(user), &(&1.provider == :chatgpt))
    end

    test "a transient refresh failure keeps the credentials without returning the expired token", %{user: user} do
      insert_chatgpt_connection(user, expires_at: DateTime.add(DateTime.utc_now(), -10, :second))
      stub(Req, :post, fn _opts -> {:ok, %Req.Response{status: 503, body: %{}}} end)

      assert {:error, :chatgpt_refresh_failed} = AISubscriptions.credentials(user, :chatgpt)
      assert %{connected: true} = Enum.find(AISubscriptions.list(user), &(&1.provider == :chatgpt))
    end

    test "a new sign-in replaces a pending one, and cancelling keeps saved credentials", %{user: user} do
      insert_chatgpt_connection(user, expires_at: DateTime.add(DateTime.utc_now(), 3600, :second))

      stub(Req, :post, fn _opts ->
        {:ok,
         %Req.Response{status: 200, body: %{"device_auth_id" => "dev-1", "user_code" => "ABCD-1234", "interval" => 5}}}
      end)

      # A page that lost its login ID can start over instead of waiting 15 minutes.
      assert {:ok, %{login_id: lost_login_id}} = AISubscriptions.start_chatgpt(user)
      assert {:ok, %{login_id: login_id}} = AISubscriptions.start_chatgpt(user)
      refute login_id == lost_login_id
      assert {:error, :not_found} = AISubscriptions.poll_chatgpt(user, lost_login_id)

      assert :ok = AISubscriptions.cancel_chatgpt(user, login_id)
      assert {:error, :not_found} = AISubscriptions.poll_chatgpt(user, login_id)
      assert {:ok, %{access_token: "access-1"}} = AISubscriptions.credentials(user, :chatgpt)
    end

    test "is unavailable without a configured client", %{user: user} do
      stub(Environment, :chatgpt_client_id, fn -> nil end)

      assert {:error, :chatgpt_not_configured} = AISubscriptions.start_chatgpt(user)
      assert %{login_available: false} = Enum.find(AISubscriptions.list(user), &(&1.provider == :chatgpt))
    end
  end

  defp stub_openai(test_pid, approved?) do
    stub(Req, :post, fn opts ->
      send(test_pid, {:request, opts[:url], opts[:json] || Map.new(opts[:form])})

      case {opts[:url], opts[:form][:grant_type]} do
        {"https://auth.openai.com/api/accounts/deviceauth/usercode", _} ->
          {:ok,
           %Req.Response{status: 200, body: %{"device_auth_id" => "dev-1", "user_code" => "ABCD-1234", "interval" => "5"}}}

        {"https://auth.openai.com/api/accounts/deviceauth/token", _} when approved? ->
          {:ok, %Req.Response{status: 200, body: %{"authorization_code" => "code-1", "code_verifier" => "verifier-1"}}}

        {"https://auth.openai.com/api/accounts/deviceauth/token", _} ->
          {:ok, %Req.Response{status: 403, body: %{}}}

        {"https://auth.openai.com/oauth/token", "authorization_code"} ->
          {:ok,
           %Req.Response{
             status: 200,
             body: %{"access_token" => "access-1", "refresh_token" => "refresh-1", "expires_in" => 30}
           }}

        {"https://auth.openai.com/oauth/token", "refresh_token"} ->
          {:ok, %Req.Response{status: 200, body: %{"access_token" => "access-2", "expires_in" => 3600}}}
      end
    end)
  end

  defp allow_next_poll(user) do
    Repo.update_all(
      from(c in UserAISubscription, where: c.user_id == ^user.id and c.provider == :chatgpt),
      set: [next_poll_at: DateTime.add(DateTime.utc_now(:second), -1, :second)]
    )
  end

  defp receive_token_request(grant_type) do
    assert_received {:request, "https://auth.openai.com/oauth/token", %{grant_type: ^grant_type} = form}
    Map.new(form, fn {key, value} -> {to_string(key), value} end)
  end

  defp insert_chatgpt_connection(user, expires_at: expires_at) do
    %UserAISubscription{user_id: user.id, provider: :chatgpt}
    |> UserAISubscription.changeset(%{
      access_token: "access-1",
      refresh_token: "refresh-1",
      expires_at: DateTime.truncate(expires_at, :second)
    })
    |> Repo.insert!()
  end
end
