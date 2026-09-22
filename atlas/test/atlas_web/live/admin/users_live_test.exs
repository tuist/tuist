defmodule AtlasWeb.Admin.UsersLiveTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Atlas.Authorization.Roles
  alias Atlas.Repo
  alias Atlas.Users.User

  test "renders the admin users directory for users with admin scope", %{conn: conn} do
    {conn, executive} = log_in_user(conn, %{role: :executive})
    employee = insert_user!()

    {:ok, view, _html} = live(conn, ~p"/admin/users")

    assert has_element?(view, "#admin-users")
    assert has_element?(view, "#admin-user-actions-#{executive.id}")
    assert has_element?(view, "#admin-user-actions-#{employee.id}")
    assert has_element?(view, "#manage-roles-modal-#{employee.id}")
    assert has_element?(view, "#manage-roles-modal-#{executive.id}")
  end

  test "assigns a role to a user through the manage roles form", %{conn: conn} do
    {conn, _executive} = log_in_user(conn, %{role: :executive})
    employee = insert_user!()
    executive_role = Roles.ensure_executive_role!()

    {:ok, view, _html} = live(conn, ~p"/admin/users")

    render_submit(view, "save_user_roles", %{
      "user_id" => employee.id,
      "role_ids" => %{executive_role.slug => executive_role.id}
    })

    assigned = employee |> Repo.reload!() |> Roles.list_roles_for_user()
    assert Enum.any?(assigned, &(&1.id == executive_role.id))
  end

  test "redirects users without admin scope away from the admin directory", %{conn: conn} do
    {conn, _employee} = log_in_user(conn, %{role: :employee})

    assert {:error, {:redirect, %{to: "/commercial/sales"}}} = live(conn, ~p"/admin/users")
  end

  defp insert_user! do
    %User{}
    |> User.changeset(%{
      email: "admin-users-#{System.unique_integer([:positive])}@tuist.dev",
      name: "Atlas User"
    })
    |> Repo.insert!()
  end
end
