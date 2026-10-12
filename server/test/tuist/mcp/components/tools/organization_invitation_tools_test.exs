defmodule Tuist.MCP.Components.Tools.OrganizationInvitationToolsTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Accounts
  alias Tuist.Environment
  alias Tuist.MCP.Components.Tools.CancelOrganizationInvitation
  alias Tuist.MCP.Components.Tools.InviteOrganizationMember
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @not_authorized "The authenticated subject is not authorized to perform this action."

  setup do
    creator = AccountsFixtures.user_fixture()
    organization = AccountsFixtures.organization_fixture(creator: creator)
    %{creator: creator, organization: organization, conn: %Plug.Conn{assigns: %{current_user: creator}}}
  end

  describe "invite_organization_member" do
    test "invites an email that does not belong to a Tuist user", %{conn: conn, organization: organization} do
      stub(Environment, :mail_configured?, fn -> true end)

      expect(Accounts.UserNotifier, :deliver_invitation, fn invitee_email, opts ->
        assert invitee_email == "new.person@example.com"
        assert opts.url =~ "/auth/invitations/"
        :ok
      end)

      result =
        InviteOrganizationMember.call(conn, %{
          "organization_handle" => organization.account.name,
          "email" => " New.Person@example.com ",
          "role" => "viewer"
        })

      assert %{"content" => [%{"type" => "text", "text" => text}]} = result
      refute Map.has_key?(result, "isError")

      assert %{
               "invitee_email" => "new.person@example.com",
               "organization_handle" => organization_handle,
               "role" => "viewer",
               "email_sent" => true,
               "expires_at" => expires_at
             } = JSON.decode!(text)

      assert organization_handle == organization.account.name
      assert {:ok, _datetime, 0} = DateTime.from_iso8601(expires_at)

      invitation = Accounts.get_invitation_by_invitee_email_and_organization("new.person@example.com", organization)
      assert invitation.role == "viewer"
      refute text =~ invitation.token
    end

    test "invites an existing Tuist user who is not a member", %{conn: conn, organization: organization} do
      stub(Environment, :mail_configured?, fn -> false end)
      invitee = AccountsFixtures.user_fixture()

      result =
        InviteOrganizationMember.call(conn, %{
          "organization_handle" => organization.account.name,
          "email" => invitee.email
        })

      assert %{"content" => [%{"type" => "text", "text" => text}]} = result
      assert %{"role" => "user", "email_sent" => false} = JSON.decode!(text)
      refute Accounts.belongs_to_organization?(invitee, organization)
      assert Accounts.get_invitation_by_invitee_email_and_organization(invitee.email, organization)
    end

    test "rejects emails that are already members", %{conn: conn, organization: organization} do
      member = AccountsFixtures.user_fixture()
      :ok = Accounts.add_user_to_organization(member, organization, role: :user)

      result =
        InviteOrganizationMember.call(conn, %{
          "organization_handle" => organization.account.name,
          "email" => member.email
        })

      assert %{"content" => [%{"text" => text}], "isError" => true} = result
      assert text == "#{member.email} is already a member of the organization."
    end

    test "rejects emails that are already invited", %{conn: conn, creator: creator, organization: organization} do
      {:ok, _invitation} =
        Accounts.invite_user_to_organization("invited@example.com", %{
          inviter: creator,
          to: organization,
          url: &"/auth/invitations/#{&1}"
        })

      result =
        InviteOrganizationMember.call(conn, %{
          "organization_handle" => organization.account.name,
          "email" => "invited@example.com"
        })

      assert %{
               "content" => [%{"text" => "invited@example.com is already invited to the organization."}],
               "isError" => true
             } =
               result
    end

    test "rejects invalid email addresses", %{conn: conn, organization: organization} do
      result =
        InviteOrganizationMember.call(conn, %{
          "organization_handle" => organization.account.name,
          "email" => "not-an-email"
        })

      assert %{"content" => [%{"text" => "not-an-email is not a valid email address."}], "isError" => true} = result
    end

    test "rejects regular organization members", %{organization: organization} do
      member = AccountsFixtures.user_fixture()
      :ok = Accounts.add_user_to_organization(member, organization, role: :user)

      result =
        InviteOrganizationMember.call(%Plug.Conn{assigns: %{current_user: member}}, %{
          "organization_handle" => organization.account.name,
          "email" => "someone@example.com"
        })

      assert %{"content" => [%{"text" => @not_authorized}], "isError" => true} = result
      refute Accounts.get_invitation_by_invitee_email_and_organization("someone@example.com", organization)
    end

    test "does not reveal missing organizations", %{conn: conn} do
      result =
        InviteOrganizationMember.call(conn, %{
          "organization_handle" => "missing-organization-#{TuistTestSupport.Utilities.unique_integer()}",
          "email" => "someone@example.com"
        })

      assert %{"content" => [%{"text" => @not_authorized}], "isError" => true} = result
    end
  end

  describe "cancel_organization_invitation" do
    test "cancels a pending invitation", %{conn: conn, creator: creator, organization: organization} do
      {:ok, _invitation} =
        Accounts.invite_user_to_organization("invited@example.com", %{
          inviter: creator,
          to: organization,
          url: &"/auth/invitations/#{&1}"
        })

      result =
        CancelOrganizationInvitation.call(conn, %{
          "organization_handle" => organization.account.name,
          "email" => "Invited@example.com"
        })

      assert %{"content" => [%{"type" => "text", "text" => text}]} = result

      assert JSON.decode!(text) == %{
               "invitee_email" => "invited@example.com",
               "organization_handle" => organization.account.name
             }

      refute Accounts.get_invitation_by_invitee_email_and_organization("invited@example.com", organization)
    end

    test "returns an error when there is no pending invitation", %{conn: conn, organization: organization} do
      result =
        CancelOrganizationInvitation.call(conn, %{
          "organization_handle" => organization.account.name,
          "email" => "nobody@example.com"
        })

      assert %{
               "content" => [%{"text" => "No pending invitation for nobody@example.com was found in the organization."}],
               "isError" => true
             } = result
    end

    test "rejects regular organization members", %{creator: creator, organization: organization} do
      member = AccountsFixtures.user_fixture()
      :ok = Accounts.add_user_to_organization(member, organization, role: :user)

      {:ok, _invitation} =
        Accounts.invite_user_to_organization("invited@example.com", %{
          inviter: creator,
          to: organization,
          url: &"/auth/invitations/#{&1}"
        })

      result =
        CancelOrganizationInvitation.call(%Plug.Conn{assigns: %{current_user: member}}, %{
          "organization_handle" => organization.account.name,
          "email" => "invited@example.com"
        })

      assert %{"content" => [%{"text" => @not_authorized}], "isError" => true} = result
      assert Accounts.get_invitation_by_invitee_email_and_organization("invited@example.com", organization)
    end
  end
end
