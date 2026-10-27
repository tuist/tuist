defmodule Tuist.MCP.Components.Tools.AddOrganizationMemberTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  alias Tuist.Accounts
  alias Tuist.MCP.Components.Tools.AddOrganizationMember
  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "add_organization_member" do
    test "adds an existing user to an organization" do
      creator = AccountsFixtures.user_fixture()
      member = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: creator)

      conn = %Plug.Conn{assigns: %{current_user: creator}}

      result =
        AddOrganizationMember.call(conn, %{
          "organization_handle" => organization.account.name,
          "email" => member.email,
          "role" => "admin"
        })

      assert %{"content" => [%{"type" => "text", "text" => text}]} = result

      assert %{
               "email" => email,
               "organization_handle" => organization_handle,
               "role" => "admin"
             } = JSON.decode!(text)

      assert email == member.email
      assert organization_handle == organization.account.name
    end

    test "updates the role of an existing organization member" do
      creator = AccountsFixtures.user_fixture()
      member = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: creator)
      :ok = Accounts.add_user_to_organization(member, organization, role: :user)

      conn = %Plug.Conn{assigns: %{current_user: creator}}

      result =
        AddOrganizationMember.call(conn, %{
          "organization_handle" => organization.account.name,
          "email" => member.email,
          "role" => "admin"
        })

      assert %{"content" => [%{"type" => "text", "text" => text}]} = result
      assert %{"role" => "admin"} = JSON.decode!(text)
      assert Accounts.get_user_role_in_organization(member, organization).name == "admin"
    end

    test "rejects regular organization members" do
      creator = AccountsFixtures.user_fixture()
      member = AccountsFixtures.user_fixture()
      added_member = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: creator)
      :ok = Accounts.add_user_to_organization(member, organization, role: :user)

      conn = %Plug.Conn{assigns: %{current_user: member}}

      result =
        AddOrganizationMember.call(conn, %{
          "organization_handle" => organization.account.name,
          "email" => added_member.email
        })

      assert %{
               "content" => [
                 %{
                   "text" => "The authenticated subject is not authorized to perform this action.",
                   "type" => "text"
                 }
               ],
               "isError" => true
             } = result
    end

    test "rejects users outside the organization" do
      creator = AccountsFixtures.user_fixture()
      outsider = AccountsFixtures.user_fixture()
      member = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: creator)

      conn = %Plug.Conn{assigns: %{current_user: outsider}}

      result =
        AddOrganizationMember.call(conn, %{
          "organization_handle" => organization.account.name,
          "email" => member.email
        })

      assert %{
               "content" => [
                 %{
                   "text" => "The authenticated subject is not authorized to perform this action.",
                   "type" => "text"
                 }
               ],
               "isError" => true
             } = result
    end

    test "does not reveal missing organizations" do
      user = AccountsFixtures.user_fixture()
      member = AccountsFixtures.user_fixture()

      conn = %Plug.Conn{assigns: %{current_user: user}}

      result =
        AddOrganizationMember.call(conn, %{
          "organization_handle" => "missing-organization-#{TuistTestSupport.Utilities.unique_integer()}",
          "email" => member.email
        })

      assert %{
               "content" => [
                 %{
                   "text" => "The authenticated subject is not authorized to perform this action.",
                   "type" => "text"
                 }
               ],
               "isError" => true
             } = result
    end
  end
end
