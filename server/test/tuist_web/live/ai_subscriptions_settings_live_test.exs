defmodule TuistWeb.AISubscriptionsSettingsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Accounts.AISubscriptions
  alias Tuist.Environment
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.Errors.NotFoundError

  @claude_token "sk-ant-oat01-" <> String.duplicate("a1B2_c3-", 8)

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(preload: [:account])
    %{conn: log_in_user(conn, user), user: user}
  end

  test "connects and disconnects a Claude subscription from the personal settings", %{conn: conn, user: user} do
    {:ok, lv, html} = live(conn, ~p"/#{user.account.name}/settings/ai-subscriptions")

    assert html =~ "AI subscriptions"
    assert html =~ "claude setup-token"
    assert has_element?(lv, "#connect-claude")
    # Without an OAuth client, ChatGPT sign-in cannot work, so its card stays hidden.
    refute has_element?(lv, "#chatgpt-subscription")

    html =
      lv
      |> form("#claude-subscription-form", claude: %{token: "sk-ant-api03-not-a-subscription-token"})
      |> render_submit()

    assert html =~ "Paste the token printed by claude setup-token."
    assert {:error, :not_connected} = AISubscriptions.credentials(user, :claude)

    html = lv |> form("#claude-subscription-form", claude: %{token: @claude_token}) |> render_submit()
    assert html =~ "Connected. Threads run on your Claude subscription."
    refute html =~ @claude_token
    assert {:ok, %{access_token: @claude_token}} = AISubscriptions.credentials(user, :claude)

    lv |> element("#disconnect-claude") |> render_click()
    assert {:ok, _} = AISubscriptions.credentials(user, :claude)

    # The confirmation button lives in a portaled modal, out of reach of `element/2`.
    render_click(lv, "disconnect")
    assert has_element?(lv, "#connect-claude")
    assert {:error, :not_connected} = AISubscriptions.credentials(user, :claude)
  end

  test "shows the ChatGPT one-time code once sign-in starts", %{conn: conn, user: user} do
    stub(Environment, :chatgpt_client_id, fn -> "app_test_client" end)

    stub(Req, :post, fn _opts ->
      {:ok, %Req.Response{status: 200, body: %{"device_auth_id" => "dev-1", "user_code" => "ABCD-1234", "interval" => 5}}}
    end)

    {:ok, lv, _html} = live(conn, ~p"/#{user.account.name}/settings/ai-subscriptions")

    lv |> element("#connect-chatgpt") |> render_click()
    html = render_async(lv, 2_000)
    assert html =~ "ABCD-1234"
    assert html =~ ~s(href="https://auth.openai.com/codex/device")
  end

  test "links the tab from the personal account's settings", %{conn: conn, user: user} do
    {:ok, lv, _html} = live(conn, ~p"/#{user.account.name}/settings")

    assert has_element?(lv, ~s(a[href="/#{user.account.name}/settings/ai-subscriptions"]))
  end

  test "is not available on another user's personal account", %{conn: conn} do
    other_user = AccountsFixtures.user_fixture(preload: [:account])

    assert_raise NotFoundError, fn ->
      live(conn, ~p"/#{other_user.account.name}/settings/ai-subscriptions")
    end
  end

  test "is not available on an organization's settings", %{conn: conn, user: user} do
    organization = AccountsFixtures.organization_fixture(creator: user, preload: [:account])

    {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/settings")
    refute has_element?(lv, ~s(a[href="/#{organization.account.name}/settings/ai-subscriptions"]))

    assert_raise NotFoundError, fn ->
      live(conn, ~p"/#{organization.account.name}/settings/ai-subscriptions")
    end
  end

  test "requires the ai flag in production", %{conn: conn, user: user} do
    stub(Environment, :env, fn -> :prod end)

    {:ok, lv, _html} = live(conn, ~p"/#{user.account.name}/settings")
    refute has_element?(lv, ~s(a[href="/#{user.account.name}/settings/ai-subscriptions"]))

    assert_raise NotFoundError, fn ->
      live(conn, ~p"/#{user.account.name}/settings/ai-subscriptions")
    end

    FunWithFlags.enable(:ai, for_actor: user)

    assert {:ok, _lv, _html} = live(conn, ~p"/#{user.account.name}/settings/ai-subscriptions")
  end
end
