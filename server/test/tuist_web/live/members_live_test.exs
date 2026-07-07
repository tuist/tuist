defmodule TuistWeb.MembersLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use Mimic

  import Ecto.Query
  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias Tuist.Accounts.Invitation
  alias Tuist.Environment
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

  describe "revoke_invite" do
    test "does not allow revoking an invitation belonging to a different organization", %{
      conn: conn,
      account: account
    } do
      # Given: an invitation on a completely different organization
      other_user = AccountsFixtures.user_fixture()
      other_org = AccountsFixtures.organization_fixture(creator: other_user, preload: [:account])

      {:ok, other_invitation} =
        Accounts.invite_user_to_organization(
          "victim@example.com",
          %{
            inviter: other_user,
            to: other_org,
            url: &"/auth/invitations/#{&1}"
          }
        )

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/members")

      # When: the user sends a revoke event with the other org's invitation ID
      render_hook(lv, "revoke_invite", %{"id" => other_invitation.id})

      # Then: the invitation should still exist
      assert Accounts.get_invitation_by_id(other_invitation.id)
    end
  end

  describe "resend_invite" do
    test "does not allow resending an invitation belonging to a different organization", %{
      conn: conn,
      account: account
    } do
      other_user = AccountsFixtures.user_fixture()
      other_org = AccountsFixtures.organization_fixture(creator: other_user, preload: [:account])

      {:ok, other_invitation} =
        Accounts.invite_user_to_organization(
          "victim@example.com",
          %{
            inviter: other_user,
            to: other_org,
            url: &"/auth/invitations/#{&1}"
          },
          token: "other-org-token"
        )

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/members")

      render_hook(lv, "resend_invite", %{"id" => other_invitation.id})

      assert Accounts.get_invitation_by_id(other_invitation.id).token == "other-org-token"
    end

    test "refreshes the invitation and reveals the new link", %{
      conn: conn,
      user: user,
      organization: organization,
      account: account
    } do
      {:ok, invitation} =
        Accounts.invite_user_to_organization(
          "invitee@example.com",
          %{
            inviter: user,
            to: organization,
            url: &"/auth/invitations/#{&1}"
          },
          token: "old-token"
        )

      stub(Environment, :mail_configured?, fn -> true end)

      expect(Accounts.UserNotifier, :deliver_invitation, fn invitee_email, opts ->
        assert invitee_email == "invitee@example.com"
        assert opts.url =~ "/auth/invitations/"
        refute opts.url =~ "old-token"
        :ok
      end)

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/members")

      html = render_hook(lv, "resend_invite", %{"id" => invitation.id})
      resent_invitation = Accounts.get_invitation_by_id(invitation.id)

      assert resent_invitation.token != "old-token"
      assert html =~ "Invitation link"
      assert html =~ "/auth/invitations/#{resent_invitation.token}"
      assert html =~ "emailed this invitation to invitee@example.com"
    end
  end

  describe "invitations table" do
    test "surfaces a copy-able invite link so members can be onboarded without email delivery", %{
      conn: conn,
      user: user,
      organization: organization,
      account: account
    } do
      # Given: a pending invitation to the current organization
      {:ok, invitation} =
        Accounts.invite_user_to_organization(
          "invitee@example.com",
          %{
            inviter: user,
            to: organization,
            url: &"/auth/invitations/#{&1}"
          }
        )

      # When: visiting the members page and switching to the invitations tab
      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/members")

      html =
        lv
        |> element("[phx-value-tab='invitations']")
        |> render_click()

      # Then: the invitation row exposes the acceptance link for the clipboard action
      assert html =~ "copy-invite-link-#{invitation.id}"
      assert html =~ "/auth/invitations/#{invitation.token}"
      assert html =~ "Resend invitation"
    end

    test "shows expired invitations as expired and hides the stale copy action", %{
      conn: conn,
      user: user,
      organization: organization,
      account: account
    } do
      {:ok, invitation} =
        Accounts.invite_user_to_organization(
          "expired@example.com",
          %{
            inviter: user,
            to: organization,
            url: &"/auth/invitations/#{&1}"
          }
        )

      expired_at =
        NaiveDateTime.utc_now()
        |> NaiveDateTime.add(-(Invitation.validity_days() + 1) * 24 * 60 * 60, :second)
        |> NaiveDateTime.truncate(:second)

      Tuist.Repo.update_all(
        from(i in Invitation, where: i.id == ^invitation.id),
        set: [updated_at: expired_at]
      )

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/members")

      html =
        lv
        |> element("[phx-value-tab='invitations']")
        |> render_click()

      assert html =~ "Expired"
      assert html =~ "resend-invite-#{invitation.id}"
      refute html =~ "copy-invite-link-#{invitation.id}"
    end

    test "reveals the invite link and notes no email was sent when mail is not configured", %{
      conn: conn,
      organization: organization,
      account: account
    } do
      stub(Environment, :mail_configured?, fn -> false end)

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/members")

      html =
        lv
        |> form("#invite-member-form", invitation: %{invitee_email: "newcomer@example.com"})
        |> render_submit()

      # Then: the modal swaps to a confirmation that surfaces the acceptance link
      invitation =
        Accounts.get_invitation_by_invitee_email_and_organization(
          "newcomer@example.com",
          organization
        )

      assert html =~ "Invitation link"
      assert html =~ "/auth/invitations/#{invitation.token}"
      assert html =~ "invite-member-form-copy-invitation-link"
      assert html =~ "Share this link with newcomer@example.com so they can join"
    end

    test "tells the inviter an email was sent when mail is configured", %{
      conn: conn,
      account: account
    } do
      stub(Environment, :mail_configured?, fn -> true end)
      stub(Accounts.UserNotifier, :deliver_invitation, fn _email, _opts -> :ok end)

      {:ok, lv, _html} = live(conn, ~p"/#{account.name}/members")

      html =
        lv
        |> form("#invite-member-form", invitation: %{invitee_email: "emailed@example.com"})
        |> render_submit()

      assert html =~ "Invitation link"
      assert html =~ "emailed this invitation to emailed@example.com"
    end
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

  describe "avatar rendering" do
    test "renders avatar for member with consecutive delimiters in account name", %{
      conn: conn,
      organization: organization,
      account: account
    } do
      # Given: A user with consecutive delimiters in their account name
      # This causes String.split to produce empty strings, and String.first("") returns nil
      user_with_delimiters =
        AccountsFixtures.user_fixture(handle: "test--user#{System.unique_integer([:positive])}")

      Accounts.add_user_to_organization(user_with_delimiters, organization)

      # When: Visit the members page
      # Then: Should render without crashing (previously caused FunctionClauseError in String.upcase)
      {:ok, lv, html} = live(conn, ~p"/#{account.name}/members")

      assert html =~ "Members"
      assert has_element?(lv, "tr#member-#{user_with_delimiters.id}")
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
