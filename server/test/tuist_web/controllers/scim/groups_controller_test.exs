defmodule TuistWeb.SCIM.GroupsControllerTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  import TuistTestSupport.Fixtures.AccountsFixtures

  alias Tuist.Accounts
  alias Tuist.SCIM

  setup %{conn: conn} do
    organization = organization_fixture()
    {:ok, {_token, plaintext}} = SCIM.create_token(organization, %{name: "test"})

    conn =
      conn
      |> put_req_header("authorization", "Bearer #{plaintext}")
      |> put_req_header("content-type", "application/scim+json")

    %{conn: conn, organization: organization}
  end

  test "PATCH /Groups/:id ignores members outside the organization", %{conn: conn, organization: org} do
    outsider = user_fixture()

    body =
      Jason.encode!(%{
        schemas: ["urn:ietf:params:scim:api:messages:2.0:PatchOp"],
        Operations: [%{op: "add", value: [%{value: to_string(outsider.id)}]}]
      })

    conn = patch(conn, "/scim/v2/Groups/admins", body)

    assert json_response(conn, 200)["id"] == "admins"
    refute Accounts.belongs_to_organization?(outsider, org)
  end
end
