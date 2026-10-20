defmodule Tuist.MCP.Components.Tools.GetOrganizationTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Accounts
  alias Tuist.MCP.Components.Tools.GetOrganization
  alias TuistTestSupport.Fixtures.AccountsFixtures

  describe "get_organization" do
    test "paginates members and invitations" do
      creator = AccountsFixtures.user_fixture(handle: "aaa-creator-#{System.unique_integer([:positive])}")
      organization = AccountsFixtures.organization_fixture(creator: creator, preload: [:account])

      members =
        for index <- 1..2 do
          user = AccountsFixtures.user_fixture(handle: "member-#{index}-#{System.unique_integer([:positive])}")
          Accounts.add_user_to_organization(user, organization, role: :user)
          user
        end

      for index <- 1..3 do
        {:ok, _invitation} =
          Accounts.invite_user_to_organization("invitee-#{index}@tuist.dev", %{
            inviter: creator,
            to: organization,
            url: &"/auth/invitations/#{&1}"
          })
      end

      conn = %Plug.Conn{assigns: %{current_user: creator}}

      # When
      first_page = call(conn, %{"account_handle" => organization.account.name, "page_size" => 2})
      second_page = call(conn, %{"account_handle" => organization.account.name, "page" => 2, "page_size" => 2})

      # Then
      assert Enum.map(first_page["members"] ++ second_page["members"], & &1["id"]) ==
               [creator.id | Enum.map(members, & &1.id)]

      assert first_page["members_pagination_metadata"] == %{
               "has_next_page" => true,
               "has_previous_page" => false,
               "total_count" => 3,
               "total_pages" => 2,
               "current_page" => 1,
               "page_size" => 2
             }

      assert length(first_page["invitations"]) == 2
      assert length(second_page["invitations"]) == 1
      assert %{"total_count" => 3, "has_next_page" => false} = second_page["invitations_pagination_metadata"]
    end

    test "omits invitations for members without the invitation read permission" do
      creator = AccountsFixtures.user_fixture()
      member = AccountsFixtures.user_fixture()
      organization = AccountsFixtures.organization_fixture(creator: creator, preload: [:account])
      Accounts.add_user_to_organization(member, organization, role: :user)

      Accounts.invite_user_to_organization("invitee@tuist.dev", %{
        inviter: creator,
        to: organization,
        url: &"/auth/invitations/#{&1}"
      })

      conn = %Plug.Conn{assigns: %{current_user: member}}

      # When
      result = call(conn, %{"account_handle" => organization.account.name})

      # Then
      assert result["invitations"] == []
      assert %{"total_count" => 0, "total_pages" => 0} = result["invitations_pagination_metadata"]
      assert %{"total_count" => 2} = result["members_pagination_metadata"]
    end
  end

  defp call(conn, arguments) do
    assert %{"content" => [%{"type" => "text", "text" => text}]} = GetOrganization.call(conn, arguments)
    JSON.decode!(text)
  end
end
