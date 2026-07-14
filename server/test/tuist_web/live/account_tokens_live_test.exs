defmodule TuistWeb.AccountTokensLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase

  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture()

    %{account: account} =
      AccountsFixtures.organization_fixture(
        name: "test-org",
        creator: user,
        preload: [:account]
      )

    conn =
      conn
      |> assign(:selected_account, account)
      |> log_in_user(user)

    %{conn: conn, user: user, account: account}
  end

  test "lists organization account tokens", %{conn: conn, account: account} do
    token =
      AccountsFixtures.account_token_fixture(
        account: account,
        name: "ci-main",
        scopes: ["ci"],
        all_projects: true
      )

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/settings/tokens")

    assert html =~ "Tokens · #{account.name} · Tuist"
    assert html =~ "Account tokens"
    assert html =~ "Create scoped tokens for CI, automation, and more."
    refute html =~ "Token values are shown once. Store the generated value before closing the dialog."
    assert html =~ "ci-main"
    assert html =~ account_token_hint(token)
    assert html =~ "ci"
    assert html =~ "All projects"
    assert html =~ "Never"
  end

  test "lists personal account tokens", %{conn: conn, user: user} do
    AccountsFixtures.account_token_fixture(
      account: user.account,
      name: "personal-ci",
      scopes: ["project:builds:write"],
      all_projects: true
    )

    {:ok, _lv, html} = live(conn, ~p"/#{user.account.name}/settings/tokens")

    assert html =~ "personal-ci"
    assert html =~ "project:builds:write"
    assert html =~ "All projects"
  end

  test "creates a token, reveals it once, and stores project restrictions", %{
    conn: conn,
    account: account
  } do
    project = ProjectsFixtures.project_fixture(account: account, name: "ios-app")

    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/tokens")

    html =
      render_submit(lv, "create_account_token", %{
        "account_token" => %{
          "name" => "ci-rotated",
          "expires" => "30d",
          "project_handles" => project.name
        }
      })

    assert html =~ "Token created"
    assert html =~ "tuist_"
    assert html =~ ~s(id="new-account-token")

    document = Floki.parse_fragment!(html)
    plaintext_token = document |> Floki.find("#new-account-token") |> Floki.text()
    assert Floki.attribute(document, "#copy-account-token-button", "data-clipboard-value") == [plaintext_token]

    {:ok, token} = Accounts.get_account_token_by_name(account, "ci-rotated")
    assert token.scopes == ["ci"]
    assert token.token_last_four == String.slice(plaintext_token, -4, 4)
    assert token.all_projects == false
    assert Enum.map(token.projects, & &1.name) == ["ios-app"]
    assert token.expires_at
    assert html =~ "ci-rotated"
    assert html =~ account_token_hint(token)
    assert html =~ "ios-app"
  end

  test "creates a token with a fine-grained scope selected from the dashboard", %{
    conn: conn,
    account: account
  } do
    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/tokens")

    render_hook(lv, "toggle_token_scope", %{"scope" => "ci"})
    render_hook(lv, "toggle_token_scope", %{"scope" => "project:builds:write"})

    render_submit(lv, "create_account_token", %{
      "account_token" => %{"name" => "build-writer", "expires" => "", "project_handles" => ""}
    })

    {:ok, token} = Accounts.get_account_token_by_name(account, "build-writer")
    assert token.scopes == ["project:builds:write"]
    assert token.all_projects == true
  end

  test "rejects invalid expiration values", %{conn: conn, account: account} do
    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/tokens")

    html =
      render_submit(lv, "create_account_token", %{
        "account_token" => %{"name" => "bad-expiry", "expires" => "soon", "project_handles" => ""}
      })

    assert html =~ "Expiration must use a duration like 30d, 6m, or 1y."
    assert Accounts.get_account_token_by_name(account, "bad-expiry") == {:error, :not_found}
  end

  test "revokes a token", %{conn: conn, account: account} do
    AccountsFixtures.account_token_fixture(account: account, name: "old-ci")

    {:ok, lv, html} = live(conn, ~p"/#{account.name}/settings/tokens")
    assert html =~ "old-ci"

    html = render_hook(lv, "revoke_account_token", %{"name" => "old-ci"})

    refute html =~ "old-ci"
    assert Accounts.get_account_token_by_name(account, "old-ci") == {:error, :not_found}
  end

  defp account_token_hint(token) do
    prefix = String.slice("tuist_#{token.id}_", 0, 14)

    "#{prefix}...#{token.token_last_four}"
  end
end
