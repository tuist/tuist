defmodule Atlas.Authorization.BootstrapTest do
  use Atlas.DataCase, async: true

  alias Atlas.Audit.Activity
  alias Atlas.Authorization.Bootstrap
  alias Atlas.Authorization.Role
  alias Atlas.Authorization.UserRole
  alias Atlas.Users
  alias Atlas.Users.User

  test "grants access only to the selected existing user and records initialization" do
    selected = insert_user!()
    other = insert_user!()

    assert {:ok, user} = Bootstrap.run("  #{String.upcase(selected.email)}  ")
    assert user.id == selected.id
    assert Users.has_scope?(selected, "admin:write")
    refute Users.has_scope?(other, "admin:write")

    activity = Repo.get_by!(Activity, action: "installation.administrator_bootstrapped")
    assert activity.interface == "system"
    assert activity.target_id == selected.id
    assert activity.metadata["authorization"] == "deployment_operator"
    assert {:error, :already_initialized} = Bootstrap.run(other.email)
    refute Users.has_scope?(other, "admin:write")
  end

  test "requires an existing user without creating an identity or consuming initialization" do
    email = "missing-#{System.unique_integer([:positive])}@example.org"

    assert {:error, :user_not_found} = Bootstrap.run(email)
    assert Users.get_user_by_email(email) == nil
    refute Repo.exists?(from(activity in Activity, where: activity.action == "installation.administrator_bootstrapped"))

    user = insert_user!()
    assert {:ok, _user} = Bootstrap.run(user.email)
  end

  test "refuses to initialize an installation with an administrator assigned through a custom role" do
    administrator = insert_user!()
    selected = insert_user!()
    role = insert_role!(["admin:write"])
    assign_role!(administrator, role)

    assert {:error, :already_initialized} = Bootstrap.run(selected.email)
    refute Users.has_scope?(selected, "admin:write")
  end

  test "cannot run again after the initialized administrator is removed" do
    administrator = insert_user!()
    selected = insert_user!()

    assert {:ok, _user} = Bootstrap.run(administrator.email)
    Repo.delete!(administrator)

    assert {:error, :already_initialized} = Bootstrap.run(selected.email)
    refute Users.has_scope?(selected, "admin:write")
  end

  test "preserves the selected user's existing roles" do
    user = insert_user!()
    role = insert_role!(["notes:read"])
    assign_role!(user, role)

    assert {:ok, _user} = Bootstrap.run(user.email)
    assert Repo.get_by(UserRole, user_id: user.id, role_id: role.id)
    assert Users.has_scope?(user, "admin:write")
  end

  test "refuses ambiguous case-insensitive identities" do
    user = insert_user!()
    %User{} |> User.changeset(%{email: String.upcase(user.email)}) |> Repo.insert!()

    assert {:error, :ambiguous_email} = Bootstrap.run(user.email)
    refute Users.has_scope?(user, "admin:write")
  end

  defp insert_user! do
    %User{}
    |> User.changeset(%{email: "bootstrap-#{System.unique_integer([:positive])}@example.org"})
    |> Repo.insert!()
  end

  defp insert_role!(scopes) do
    %Role{}
    |> Role.changeset(%{name: "Test role", slug: "bootstrap-#{System.unique_integer([:positive])}", scopes: scopes})
    |> Repo.insert!()
  end

  defp assign_role!(user, role) do
    %UserRole{}
    |> UserRole.changeset(%{user_id: user.id, role_id: role.id})
    |> Repo.insert!()
  end
end
