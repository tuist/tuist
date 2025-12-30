defmodule TuistWeb.MembersLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias TuistTestSupport.Fixtures.AccountsFixtures

  setup %{conn: conn} do
    user = AccountsFixtures.user_fixture(handle: "admin#{System.unique_integer([:positive])}")

    %{account: account} =
      organization =
      AccountsFixtures.organization_fixture(
        name: "test-org",
        creator: user,
        preload: [:account]
      )

    conn =
      conn
      |> assign(:selected_account, account)
      |> log_in_user(user)

    %{conn: conn, user: user, organization: organization, account: account}
  end

  describe "members table" do
    test "renders members table with admin and regular users", %{
      conn: conn,
      user: admin_user,
      organization: organization,
      account: account
    } do
      # Given: Add a regular user to the organization
      regular_user =
        AccountsFixtures.user_fixture(handle: "user#{System.unique_integer([:positive])}")

      Accounts.add_user_to_organization(regular_user, organization)

      # When: Visit the members page
      {:ok, lv, html} = live(conn, ~p"/#{account.name}/members")

      # Then: Should render the table with both members
      assert html =~ "Members"
      assert html =~ admin_user.email
      assert html =~ regular_user.email

      # And: Should display roles correctly
      assert has_element?(lv, "#members-table")
      assert has_element?(lv, "tr#member-#{admin_user.id}")
      assert has_element?(lv, "tr#member-#{regular_user.id}")
    end

    test "renders empty state when no members match search", %{
      conn: conn,
      account: account
    } do
      # When: Visit the members page and search for non-existent member
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/members")

      lv
      |> form("form[phx-change='search']", %{search: "nonexistent@example.com"})
      |> render_change()

      # Then: Should show empty state
      assert has_element?(lv, "[data-part=title]", "No members found")
      assert has_element?(lv, "[data-part=subtitle]", "Try changing your search term")
    end

    test "filters members by email", %{
      conn: conn,
      user: admin_user,
      organization: organization,
      account: account
    } do
      # Given: Multiple users in the organization
      user1 =
        AccountsFixtures.user_fixture(
          email: "alice@example.com",
          handle: "alice#{System.unique_integer([:positive])}"
        )

      user2 =
        AccountsFixtures.user_fixture(
          email: "bob@example.com",
          handle: "bob#{System.unique_integer([:positive])}"
        )

      Accounts.add_user_to_organization(user1, organization)
      Accounts.add_user_to_organization(user2, organization)

      # When: Search for a specific email
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/members")

      lv
      |> form("form[phx-change='search']", %{search: "alice@"})
      |> render_change()

      # Then: Should only show matching member
      assert has_element?(lv, "tr#member-#{user1.id}")
      refute has_element?(lv, "tr#member-#{user2.id}")
      refute has_element?(lv, "tr#member-#{admin_user.id}")
    end

    test "filters members by account name", %{
      conn: conn,
      user: admin_user,
      organization: organization,
      account: account
    } do
      # Given: Multiple users in the organization
      user1 =
        AccountsFixtures.user_fixture(handle: "special-user#{System.unique_integer([:positive])}")

      user2 =
        AccountsFixtures.user_fixture(handle: "normal-user#{System.unique_integer([:positive])}")

      Accounts.add_user_to_organization(user1, organization)
      Accounts.add_user_to_organization(user2, organization)

      # When: Search by account name
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/members")

      lv
      |> form("form[phx-change='search']", %{search: "special-"})
      |> render_change()

      # Then: Should only show matching member
      assert has_element?(lv, "tr#member-#{user1.id}")
      refute has_element?(lv, "tr#member-#{user2.id}")
      refute has_element?(lv, "tr#member-#{admin_user.id}")
    end
  end

  describe "members table row_key" do
    test "correctly generates unique row keys for list structure", %{
      conn: conn,
      user: admin_user,
      organization: organization,
      account: account
    } do
      # Given: Multiple users in the organization
      user1 = AccountsFixtures.user_fixture(handle: "user1#{System.unique_integer([:positive])}")
      user2 = AccountsFixtures.user_fixture(handle: "user2#{System.unique_integer([:positive])}")

      Accounts.add_user_to_organization(user1, organization)
      Accounts.add_user_to_organization(user2, organization)

      # When: Visit the members page
      {:ok, lv, html} = live(conn, ~p"/#{account.name}/members")

      # Then: Each row should have a unique id generated from the member's ID
      # This verifies the row_key function is working correctly with the [user, role] list structure
      assert has_element?(lv, "tr#member-#{admin_user.id}")
      assert has_element?(lv, "tr#member-#{user1.id}")
      assert has_element?(lv, "tr#member-#{user2.id}")

      # And: Should render the table without errors
      assert html =~ "Members"
      assert html =~ admin_user.email
      assert html =~ user1.email
      assert html =~ user2.email
    end
  end
end
