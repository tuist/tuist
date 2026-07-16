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
    ProjectsFixtures.project_fixture(account: account, name: "ios-app")

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
    assert html =~ "Project access"
    assert html =~ "Select all projects"
    assert html =~ "Select all account scopes"
    assert html =~ "Select all project scopes"
    refute html =~ "Project handles"
    refute html =~ "Specific projects"
    refute html =~ "MCP"
    refute html =~ "#{account.name}/ios-app"
    assert account_tokens_table_headers(html) == ["Name", "Token", "Last used", "Created"]
    assert scope_checked?(html, "ci")
    assert scope_checked?(html, "account:cache:read")
    assert scope_checked?(html, "account:cache:write")
    assert scope_checked?(html, "project:builds:read")
    assert scope_checked?(html, "project:builds:write")
    refute scope_checked?(html, "project:admin:read")
    refute html =~ "Token values are shown once. Store the generated value before closing the dialog."
    assert html =~ "ci-main"
    assert html =~ account_token_hint(token)
    assert html =~ ~p"/#{account.name}/settings/tokens/#{token.id}"
    assert html =~ "Never"
  end

  test "lists personal account tokens", %{conn: conn, user: user} do
    ProjectsFixtures.project_fixture(account: user.account, name: "personal-app")

    AccountsFixtures.account_token_fixture(
      account: user.account,
      name: "personal-ci",
      scopes: ["project:builds:write"],
      all_projects: true
    )

    {:ok, _lv, html} = live(conn, ~p"/#{user.account.name}/settings/tokens")

    assert html =~ "personal-ci"
    assert account_tokens_table_headers(html) == ["Name", "Token", "Last used", "Created"]
    assert html =~ "Project access"
    assert html =~ "Select all projects"
    assert html =~ "Select all account scopes"
    assert html =~ "Select all project scopes"
    refute html =~ "Project handles"
    refute html =~ "Specific projects"
    refute html =~ "MCP"
  end

  test "creates a token, reveals it once, and stores project restrictions", %{
    conn: conn,
    account: account
  } do
    project = ProjectsFixtures.project_fixture(account: account, name: "ios-app")
    ProjectsFixtures.project_fixture(account: account, name: "macos-app")

    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/tokens")

    render_hook(lv, "toggle_all_project_access_projects", %{})
    render_hook(lv, "toggle_project_access_project", %{"project-id" => "#{project.id}"})

    html =
      render_submit(lv, "create_account_token", %{
        "account_token" => %{
          "name" => "ci-rotated",
          "expires" => "30d"
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
    assert html =~ ~p"/#{account.name}/settings/tokens/#{token.id}"
  end

  test "shows token project access on the token detail page", %{conn: conn, account: account} do
    project = ProjectsFixtures.project_fixture(account: account, name: "ios-app")

    all_projects_token =
      AccountsFixtures.account_token_fixture(
        account: account,
        name: "all-projects",
        scopes: ["ci"],
        all_projects: true
      )

    restricted_token =
      AccountsFixtures.account_token_fixture(
        account: account,
        name: "ios-only",
        scopes: ["project:builds:read"],
        all_projects: false,
        project_ids: [project.id]
      )

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/settings/tokens/#{restricted_token.id}")

    assert html =~ "Tokens · #{account.name} · Tuist"
    assert html =~ "Account token"
    assert html =~ "ios-only"
    assert html =~ account_token_hint(restricted_token)
    refute html =~ "General"
    refute html =~ "Integrations"
    refute html =~ "Authentication"
    assert html =~ "Project access"
    assert html =~ "account-token-permissions-table"
    assert html =~ "account-token-projects-table"
    assert html =~ "Permission"
    assert html =~ "Scope"
    assert html =~ "ios-app"
    assert html =~ "#{account.name}/ios-app"
    refute html =~ "account-tokens-table"
    refute html =~ "permission-item"

    {:ok, _lv, html} = live(conn, ~p"/#{account.name}/settings/tokens/#{all_projects_token.id}")

    assert html =~ "all-projects"
    assert html =~ "account:cache:read"
    assert html =~ "account:cache:write"
    assert html =~ "project:cache:read"
    assert html =~ "project:cache:write"
    assert html =~ "project:previews:read"
    assert html =~ "project:previews:write"
    assert html =~ "project:bundles:read"
    assert html =~ "project:bundles:write"
    assert html =~ "project:tests:read"
    assert html =~ "project:tests:write"
    assert html =~ "project:builds:read"
    assert html =~ "project:builds:write"
    assert html =~ "project:runs:read"
    assert html =~ "project:runs:write"
    refute html =~ "Category"
    assert html =~ "This token has access to all projects in this account."
  end

  test "creates a token with a fine-grained scope selected from the dashboard", %{
    conn: conn,
    account: account
  } do
    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/tokens")

    render_hook(lv, "toggle_token_scope", %{"scope" => "ci"})
    render_hook(lv, "toggle_token_scope", %{"scope" => "project:builds:write"})

    render_submit(lv, "create_account_token", %{
      "account_token" => %{"name" => "build-writer", "expires" => ""}
    })

    {:ok, token} = Accounts.get_account_token_by_name(account, "build-writer")
    assert token.scopes == ["project:builds:read", "project:builds:write"]
    assert token.all_projects == true
  end

  test "selecting the CI preset clears unrelated permissions", %{
    conn: conn,
    account: account
  } do
    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/tokens")

    render_hook(lv, "toggle_token_scope", %{"scope" => "ci"})
    html = render_hook(lv, "toggle_token_scope_group", %{"group" => "account"})

    assert scope_checked?(html, "account:members:read")
    assert scope_checked?(html, "account:registry:read")

    html = render_hook(lv, "toggle_token_scope", %{"scope" => "ci"})

    assert scope_checked?(html, "ci")
    assert scope_checked?(html, "account:cache:read")
    assert scope_checked?(html, "account:cache:write")
    assert scope_checked?(html, "project:builds:read")
    assert scope_checked?(html, "project:builds:write")
    refute scope_checked?(html, "account:members:read")
    refute scope_checked?(html, "account:registry:read")
    refute scope_checked?(html, "project:admin:read")

    render_submit(lv, "create_account_token", %{
      "account_token" => %{"name" => "ci-only", "expires" => ""}
    })

    {:ok, token} = Accounts.get_account_token_by_name(account, "ci-only")
    assert token.scopes == ["ci"]
  end

  test "deselects the CI preset when fine-grained permissions change", %{
    conn: conn,
    account: account
  } do
    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/tokens")

    html = render_hook(lv, "toggle_token_scope", %{"scope" => "account:members:read"})

    refute scope_checked?(html, "ci")
    assert scope_checked?(html, "account:cache:read")
    assert scope_checked?(html, "account:cache:write")
    assert scope_checked?(html, "account:members:read")
    assert scope_checked?(html, "project:builds:read")
    assert scope_checked?(html, "project:builds:write")

    render_submit(lv, "create_account_token", %{
      "account_token" => %{"name" => "custom-ci-plus-members", "expires" => ""}
    })

    {:ok, token} = Accounts.get_account_token_by_name(account, "custom-ci-plus-members")

    refute "ci" in token.scopes

    assert token.scopes == [
             "account:cache:read",
             "account:cache:write",
             "account:members:read",
             "project:builds:read",
             "project:builds:write",
             "project:bundles:read",
             "project:bundles:write",
             "project:cache:read",
             "project:cache:write",
             "project:previews:read",
             "project:previews:write",
             "project:runs:read",
             "project:runs:write",
             "project:tests:read",
             "project:tests:write"
           ]
  end

  test "deselecting a read permission also deselects its write permission", %{
    conn: conn,
    account: account
  } do
    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/tokens")

    html = render_hook(lv, "toggle_token_scope", %{"scope" => "account:cache:read"})

    refute scope_checked?(html, "ci")
    refute scope_checked?(html, "account:cache:read")
    refute scope_checked?(html, "account:cache:write")
    assert scope_checked?(html, "project:builds:read")
    assert scope_checked?(html, "project:builds:write")

    render_submit(lv, "create_account_token", %{
      "account_token" => %{"name" => "ci-without-account-cache", "expires" => ""}
    })

    {:ok, token} = Accounts.get_account_token_by_name(account, "ci-without-account-cache")

    refute "ci" in token.scopes
    refute "account:cache:read" in token.scopes
    refute "account:cache:write" in token.scopes
    assert "project:builds:read" in token.scopes
    assert "project:builds:write" in token.scopes
  end

  test "creates a token with all account and project scopes selected from group toggles", %{
    conn: conn,
    account: account
  } do
    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/tokens")

    render_hook(lv, "toggle_token_scope", %{"scope" => "ci"})
    render_hook(lv, "toggle_token_scope_group", %{"group" => "account"})
    render_hook(lv, "toggle_token_scope_group", %{"group" => "project"})

    render_submit(lv, "create_account_token", %{
      "account_token" => %{"name" => "full-access", "expires" => ""}
    })

    {:ok, token} = Accounts.get_account_token_by_name(account, "full-access")

    assert token.scopes == [
             "account:cache:read",
             "account:cache:write",
             "account:members:read",
             "account:members:write",
             "account:registry:read",
             "account:registry:write",
             "account:scim:write",
             "project:admin:read",
             "project:admin:write",
             "project:builds:read",
             "project:builds:write",
             "project:bundles:read",
             "project:bundles:write",
             "project:cache:read",
             "project:cache:write",
             "project:previews:read",
             "project:previews:write",
             "project:runs:read",
             "project:runs:write",
             "project:tests:read",
             "project:tests:write"
           ]

    assert token.all_projects == true
  end

  test "rejects invalid expiration values", %{conn: conn, account: account} do
    {:ok, lv, _html} = live(conn, ~p"/#{account.name}/settings/tokens")

    html =
      render_submit(lv, "create_account_token", %{
        "account_token" => %{"name" => "bad-expiry", "expires" => "soon"}
      })

    assert html =~ "Expiration must use a duration like 30d, 6m, or 1y."
    document = Floki.parse_fragment!(html)
    assert Floki.find(document, ~s([data-error="Expiration must use a duration like 30d, 6m, or 1y."])) != []
    assert Floki.attribute(document, "#account_token_name", "value") == ["bad-expiry"]
    assert Floki.attribute(document, "#account_token_expires", "value") == ["soon"]
    assert Accounts.get_account_token_by_name(account, "bad-expiry") == {:error, :not_found}
  end

  test "shows a Noora field error when the token name is missing", %{conn: conn, account: account} do
    {:ok, lv, html} = live(conn, ~p"/#{account.name}/settings/tokens")

    document = Floki.parse_fragment!(html)
    assert Floki.attribute(document, "#account_token_name", "required") == []

    html =
      render_submit(lv, "create_account_token", %{
        "account_token" => %{"name" => "", "expires" => ""}
      })

    assert html =~ "Token name is required."
    document = Floki.parse_fragment!(html)
    assert Floki.find(document, ~s([data-error="Token name is required."])) != []
    assert Floki.attribute(document, "#account_token_name", "required") == []
  end

  test "revokes a token", %{conn: conn, account: account} do
    token = AccountsFixtures.account_token_fixture(account: account, name: "old-ci")

    {:ok, lv, html} = live(conn, ~p"/#{account.name}/settings/tokens/#{token.id}")
    assert html =~ "old-ci"

    assert {:error, {:live_redirect, %{to: redirect_to}}} =
             render_hook(lv, "revoke_account_token", %{})

    assert redirect_to == ~p"/#{account.name}/settings/tokens"
    assert Accounts.get_account_token_by_name(account, "old-ci") == {:error, :not_found}
  end

  test "raises not found for a token in another account", %{conn: conn, account: account} do
    other_account = AccountsFixtures.user_fixture().account
    token = AccountsFixtures.account_token_fixture(account: other_account, name: "other-ci")

    assert_raise TuistWeb.Errors.NotFoundError, fn ->
      live(conn, ~p"/#{account.name}/settings/tokens/#{token.id}")
    end
  end

  defp account_token_hint(token) do
    "tuist_" <> String.slice(token.id, 0, 8) <> String.duplicate("•", 6)
  end

  defp account_tokens_table_headers(html) do
    html
    |> Floki.parse_fragment!()
    |> Floki.find("#account-tokens-table thead th")
    |> Enum.map(&Floki.text/1)
  end

  defp scope_checked?(html, scope) do
    id = "#account-token-scope-#{String.replace(scope, ":", "-")}"

    html
    |> Floki.parse_fragment!()
    |> Floki.find("#{id} .noora-checkbox-control")
    |> Floki.attribute("data-state")
    |> Kernel.==(["checked"])
  end
end
