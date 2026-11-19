defmodule Tuist.MCP.Components.Tools.AmpWorkspaceToolsTest do
  use TuistTestSupport.Cases.ConnCase, async: true

  alias Tuist.Accounts
  alias Tuist.Accounts.AuthenticatedAccount
  alias Tuist.MCP.Components.Tools.ConnectAmpWorkspace
  alias Tuist.MCP.Components.Tools.DisconnectAmpWorkspace
  alias Tuist.MCP.Components.Tools.ListAmpWorkspaceConnections
  alias TuistTestSupport.Fixtures.AccountsFixtures

  @workspace_id "4b7c2a91-5d3e-4f8a-9c61-2e0d7b9a1f35"
  @project_id "9a1f6e2c-0b4d-4c7e-8f35-6d2a8b1c4e70"

  setup do
    admin = AccountsFixtures.user_fixture(preload: [:account])
    organization = AccountsFixtures.organization_fixture(creator: admin, preload: [:account])
    member = AccountsFixtures.user_fixture(preload: [:account])
    Accounts.add_user_to_organization(member, organization, role: :user)

    %{admin: admin, member: member, account: organization.account, handle: organization.account.name}
  end

  defp user_conn(user), do: %Plug.Conn{assigns: %{current_user: user}}

  test "an admin connects, lists and disconnects a workspace", %{admin: admin, account: account, handle: handle} do
    connected =
      ConnectAmpWorkspace.call(user_conn(admin), %{
        "account_handle" => handle,
        "workspace_id" => @workspace_id,
        "project_id" => @project_id
      })

    refute connected["isError"]
    assert %{"id" => id, "workspace_id" => @workspace_id, "project_id" => @project_id} = connected["structuredContent"]
    assert [%{id: ^id, project_id: @project_id}] = Accounts.list_amp_workspace_connections(account)

    listed = ListAmpWorkspaceConnections.call(user_conn(admin), %{"account_handle" => handle})
    assert [%{"id" => ^id, "workspace_id" => @workspace_id}] = listed["structuredContent"]["connections"]

    disconnected = DisconnectAmpWorkspace.call(user_conn(admin), %{"account_handle" => handle, "connection_id" => id})
    refute disconnected["isError"]
    assert Accounts.list_amp_workspace_connections(account) == []

    again = DisconnectAmpWorkspace.call(user_conn(admin), %{"account_handle" => handle, "connection_id" => id})
    assert again["isError"]
  end

  test "a workspace-wide connection has no project", %{admin: admin, handle: handle} do
    result = ConnectAmpWorkspace.call(user_conn(admin), %{"account_handle" => handle, "workspace_id" => @workspace_id})

    assert %{"workspace_id" => @workspace_id, "project_id" => nil} = result["structuredContent"]
  end

  test "reports invalid and duplicate workspaces", %{admin: admin, account: account, handle: handle} do
    invalid = ConnectAmpWorkspace.call(user_conn(admin), %{"account_handle" => handle, "workspace_id" => "not-a-uuid"})
    assert %{"isError" => true, "content" => [%{"text" => text}]} = invalid
    assert text =~ "workspace_id"

    args = %{"account_handle" => handle, "workspace_id" => @workspace_id}
    refute ConnectAmpWorkspace.call(user_conn(admin), args)["isError"]
    assert %{"isError" => true, "content" => [%{"text" => text}]} = ConnectAmpWorkspace.call(user_conn(admin), args)
    assert text =~ "already connected"
    assert length(Accounts.list_amp_workspace_connections(account)) == 1
  end

  test "refuses members who aren't admins", %{admin: admin, member: member, account: account, handle: handle} do
    {:ok, connection} = Accounts.create_amp_workspace_connection(account, %{workspace_id: @workspace_id})

    assert ConnectAmpWorkspace.call(user_conn(member), %{"account_handle" => handle, "workspace_id" => @project_id})[
             "isError"
           ]

    assert ListAmpWorkspaceConnections.call(user_conn(member), %{"account_handle" => handle})["isError"]

    assert DisconnectAmpWorkspace.call(user_conn(member), %{"account_handle" => handle, "connection_id" => connection.id})[
             "isError"
           ]

    assert [%{id: id}] = Accounts.list_amp_workspace_connections(account)
    assert id == connection.id
    refute ListAmpWorkspaceConnections.call(user_conn(admin), %{"account_handle" => handle})["isError"]
  end

  test "refuses CI tokens, such as the ones orbs get", %{account: account, handle: handle} do
    subject = %AuthenticatedAccount{account: account, scopes: ["ci"], all_projects: true}
    conn = %Plug.Conn{assigns: %{current_subject: subject}}

    assert ConnectAmpWorkspace.call(conn, %{"account_handle" => handle, "workspace_id" => @workspace_id})["isError"]
    assert Accounts.list_amp_workspace_connections(account) == []
  end

  test "can't disconnect another account's connection", %{admin: admin, handle: handle} do
    other = AccountsFixtures.organization_fixture(preload: [:account])
    {:ok, connection} = Accounts.create_amp_workspace_connection(other.account, %{workspace_id: @workspace_id})

    result =
      DisconnectAmpWorkspace.call(user_conn(admin), %{"account_handle" => handle, "connection_id" => connection.id})

    assert result["isError"]
    assert [_] = Accounts.list_amp_workspace_connections(other.account)
  end
end
