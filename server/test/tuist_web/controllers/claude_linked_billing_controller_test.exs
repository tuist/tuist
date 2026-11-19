defmodule TuistWeb.ClaudeLinkedBillingControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts.OrganizationAI
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistWeb.Authentication
  alias TuistWeb.ClaudeLinkedBillingController
  alias TuistWeb.Errors.BadRequestError

  setup do
    user = AccountsFixtures.user_fixture()
    account = AccountsFixtures.organization_fixture(creator: user).account

    stub(OrganizationAI, :start_claude_link, fn ^user, %{id: id} when id == account.id ->
      {:ok, %{url: "https://auth.claude.com/oauth/authorize?client_id=c", state: "state-1", code_verifier: "verifier-1"}}
    end)

    %{user: user, account: account, conn: authenticated_conn(user)}
  end

  test "starts linking with browser-bound state and completes on the same user's callback", %{
    conn: conn,
    user: user,
    account: account
  } do
    conn = ClaudeLinkedBillingController.start(conn, %{"account_id" => to_string(account.id)})
    assert redirected_to(conn) == "https://auth.claude.com/oauth/authorize?client_id=c"

    expect(OrganizationAI, :link_claude, fn ^user, _account, "code-1", "verifier-1" -> {:ok, %{}} end)

    conn =
      conn |> browser_request(user) |> ClaudeLinkedBillingController.callback(%{"code" => "code-1", "state" => "state-1"})

    assert redirected_to(conn) == "/#{account.name}/settings/ai/routing"
    assert Phoenix.Flash.get(conn.assigns.flash, :info) == "Linked your Claude organization."
    assert get_session(conn, :claude_linked_billing) == nil
  end

  test "reports a refused or cancelled approval without linking", %{conn: conn, user: user, account: account} do
    conn = ClaudeLinkedBillingController.start(conn, %{"account_id" => to_string(account.id)})
    reject(OrganizationAI, :link_claude, 4)

    conn =
      conn
      |> browser_request(user)
      |> ClaudeLinkedBillingController.callback(%{"error" => "user_profile_already_linked", "state" => "state-1"})

    assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "already linked to another Tuist organization"
  end

  test "rejects another user's callback and a mismatched state", %{conn: conn, user: user, account: account} do
    conn = ClaudeLinkedBillingController.start(conn, %{"account_id" => to_string(account.id)})
    reject(OrganizationAI, :link_claude, 4)

    assert_raise BadRequestError, fn ->
      conn
      |> browser_request(AccountsFixtures.user_fixture())
      |> ClaudeLinkedBillingController.callback(%{"code" => "code-1", "state" => "state-1"})
    end

    assert_raise BadRequestError, fn ->
      conn |> browser_request(user) |> ClaudeLinkedBillingController.callback(%{"code" => "code-1", "state" => "other"})
    end
  end

  defp browser_request(conn, user) do
    user
    |> authenticated_conn()
    |> put_session(:claude_linked_billing, get_session(conn, :claude_linked_billing))
    |> Phoenix.Controller.fetch_flash([])
  end

  defp authenticated_conn(user) do
    build_conn() |> init_test_session(%{}) |> Authentication.put_current_user(user) |> Phoenix.Controller.fetch_flash([])
  end
end
