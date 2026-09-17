defmodule AtlasWeb.Admin.UsersLiveTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Atlas.Repo
  alias Atlas.Users.User

  test "renders the admin users directory for executives", %{conn: conn} do
    {conn, executive} = log_in_user(conn, %{role: :executive})
    employee = insert_user!(:employee)
    other_executive = insert_user!(:executive)

    {:ok, view, _html} = live(conn, ~p"/admin/users")

    assert has_element?(view, "#admin-users")
    assert has_element?(view, "#admin-users-executive-count", "2 executives")
    assert has_element?(view, "#admin-users-employee-count", "1 employee")
    assert has_element?(view, "#admin-user-actions-#{executive.id}")
    assert has_element?(view, "#admin-user-actions-#{employee.id}")
    assert has_element?(view, "#admin-user-actions-#{other_executive.id}")
    assert has_element?(view, "#manage-role-modal-#{employee.id}")
    assert has_element?(view, "#user-role-#{other_executive.id}", "Executive")
    assert has_element?(view, ~s(a[href="/admin/users"]), "Users")
  end

  test "updates a user's role from the admin directory", %{conn: conn} do
    {conn, _executive} = log_in_user(conn, %{role: :executive})
    employee = insert_user!(:employee)

    {:ok, view, _html} = live(conn, ~p"/admin/users")

    render_submit(view, "save_user_role", %{
      "user_id" => employee.id,
      "user" => %{"role" => "executive"}
    })

    updated_user = Repo.get!(User, employee.id)

    assert updated_user.role == :executive
    assert has_element?(view, "#user-role-#{employee.id}", "Executive")
    assert has_element?(view, "#admin-users-executive-count", "2 executives")
    assert has_element?(view, "#admin-users-employee-count", "0 employees")
  end

  test "redirects employees away from the admin directory", %{conn: conn} do
    {conn, _employee} = log_in_user(conn, %{role: :employee})

    assert {:error, {:redirect, %{to: "/commercial/sales"}}} = live(conn, ~p"/admin/users")
  end

  defp insert_user!(role) do
    %User{}
    |> User.changeset(%{
      email: "admin-users-#{System.unique_integer([:positive])}@tuist.dev",
      name: "Atlas User",
      role: role
    })
    |> Repo.insert!()
  end
end
