defmodule Tuist.MCP.Components.Tools.AISubscriptionToolsTest do
  use TuistTestSupport.Cases.DataCase, async: true
  use Mimic

  alias Tuist.Accounts.AISubscriptions
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.Environment
  alias Tuist.FeatureFlags
  alias Tuist.MCP.Components.Tools.CancelChatGPTSubscriptionLogin
  alias Tuist.MCP.Components.Tools.ConnectClaudeSubscription
  alias Tuist.MCP.Components.Tools.DisconnectAISubscription
  alias Tuist.MCP.Components.Tools.ListAISubscriptions
  alias Tuist.MCP.Components.Tools.PollChatGPTSubscriptionLogin
  alias Tuist.MCP.Components.Tools.StartChatGPTSubscriptionLogin
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @claude_token "sk-ant-oat01-" <> String.duplicate("a1B2_c3-", 8)

  setup do
    stub(Environment, :chatgpt_client_id, fn -> "app_test_client" end)
    user = AccountsFixtures.user_fixture(preload: [:account])
    %{user: user, conn: %Plug.Conn{assigns: %{current_user: user}}}
  end

  test "annotates only the list as read-only and disconnect as destructive" do
    assert ListAISubscriptions.annotations().readOnlyHint

    for tool <- [
          ConnectClaudeSubscription,
          StartChatGPTSubscriptionLogin,
          PollChatGPTSubscriptionLogin,
          CancelChatGPTSubscriptionLogin,
          DisconnectAISubscription
        ] do
      refute tool.annotations().readOnlyHint
    end

    assert DisconnectAISubscription.annotations().destructiveHint
    assert ConnectClaudeSubscription.description() =~ "secret"
    assert ConnectClaudeSubscription.input_schema()["properties"]["token"]["description"] =~ "Secret"
  end

  test "connects, lists and disconnects Claude without returning the token", %{user: user, conn: conn} do
    assert %{"structuredContent" => %{"subscriptions" => [%{"provider" => "claude", "connected" => false}, _]}} =
             ListAISubscriptions.call(conn, %{})

    result = ConnectClaudeSubscription.call(conn, %{"token" => @claude_token})

    assert %{"structuredContent" => %{"subscriptions" => [%{"provider" => "claude", "connected" => true}, _]}} = result
    refute JSON.encode!(result) =~ "sk-ant-oat01"
    assert {:ok, %{access_token: @claude_token}} = AISubscriptions.credentials(user, :claude)

    assert %{"structuredContent" => %{"subscriptions" => [%{"provider" => "claude", "connected" => false}, _]}} =
             DisconnectAISubscription.call(conn, %{"provider" => "claude"})

    assert {:error, :not_connected} = AISubscriptions.credentials(user, :claude)
  end

  test "rejects invalid Claude tokens without echoing them", %{conn: conn} do
    token = "sk-ant-api03-" <> String.duplicate("a", 40)

    assert %{"isError" => true, "content" => [%{"text" => text}]} =
             ConnectClaudeSubscription.call(conn, %{"token" => token})

    refute text =~ token

    assert %{"isError" => true, "content" => [%{"text" => "Arguments do not match the tool schema."}]} =
             ConnectClaudeSubscription.call(conn, %{"token" => @claude_token, "extra" => true})
  end

  test "signs in to ChatGPT and cancels a pending sign-in", %{conn: conn} do
    stub(Req, :post, fn opts ->
      case opts[:url] do
        "https://auth.openai.com/api/accounts/deviceauth/usercode" ->
          {:ok,
           %Req.Response{status: 200, body: %{"device_auth_id" => "dev-1", "user_code" => "ABCD-1234", "interval" => 5}}}

        "https://auth.openai.com/api/accounts/deviceauth/token" ->
          {:ok, %Req.Response{status: 403, body: %{}}}
      end
    end)

    result = StartChatGPTSubscriptionLogin.call(conn, %{})

    assert %{
             "structuredContent" =>
               %{
                 "login_id" => login_id,
                 "user_code" => "ABCD-1234",
                 "verification_url" => "https://auth.openai.com/codex/device",
                 "interval" => 5
               } = login
           } = result

    assert map_size(login) == 5
    refute JSON.encode!(result) =~ "dev-1"

    # Starting again replaces the pending sign-in, so an agent that lost the login ID can recover.
    assert %{"structuredContent" => %{"login_id" => replaced_login_id}} =
             StartChatGPTSubscriptionLogin.call(conn, %{})

    assert %{"isError" => true} = PollChatGPTSubscriptionLogin.call(conn, %{"login_id" => login_id})
    login_id = replaced_login_id

    assert %{"structuredContent" => %{"status" => "pending"}} =
             PollChatGPTSubscriptionLogin.call(conn, %{"login_id" => login_id})

    assert %{"structuredContent" => %{"cancelled" => true}} =
             CancelChatGPTSubscriptionLogin.call(conn, %{"login_id" => login_id})

    assert %{"isError" => true} = PollChatGPTSubscriptionLogin.call(conn, %{"login_id" => login_id})
    assert %{"isError" => true} = CancelChatGPTSubscriptionLogin.call(conn, %{"login_id" => login_id})
  end

  test "requires a user with the ai flag", %{user: user, conn: conn} do
    account_subject = %Plug.Conn{
      assigns: %{current_subject: %AuthenticatedAccount{account: user.account, scopes: ["mcp"]}}
    }

    assert %{"isError" => true} = ListAISubscriptions.call(account_subject, %{})
    assert %{"isError" => true} = ConnectClaudeSubscription.call(account_subject, %{"token" => @claude_token})

    stub(FeatureFlags, :ai_enabled?, fn _user -> false end)

    assert %{"isError" => true} = ListAISubscriptions.call(conn, %{})
    assert %{"isError" => true} = ConnectClaudeSubscription.call(conn, %{"token" => @claude_token})
    assert %{"isError" => true} = StartChatGPTSubscriptionLogin.call(conn, %{})
    assert {:error, :not_connected} = AISubscriptions.credentials(user, :claude)
  end

  test "answers under a WebMCP scope only on the user's personal account", %{user: user} do
    organization = AccountsFixtures.organization_fixture(preload: [:account])
    other_user = AccountsFixtures.user_fixture(preload: [:account])

    own = %Plug.Conn{assigns: %{current_user: user, mcp_account_scope: user.account}}
    assert %{"structuredContent" => %{"subscriptions" => [_, _]}} = ListAISubscriptions.call(own, %{})

    for account <- [organization.account, other_user.account] do
      scoped = %Plug.Conn{assigns: %{current_user: user, mcp_account_scope: account}}
      assert %{"isError" => true} = ListAISubscriptions.call(scoped, %{})
    end
  end
end
