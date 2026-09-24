defmodule Atlas.UsersTest do
  use Atlas.DataCase, async: true

  alias Atlas.Authorization.Roles
  alias Atlas.Authorization.UserRole
  alias Atlas.Users
  alias Atlas.Users.User
  alias Ueberauth.Auth.Info

  describe "find_or_create_user_from_auth/1" do
    test "creates a user when the email is in the allowed Google Workspace" do
      auth = build_auth(email: "alice@tuist.dev", name: "Alice")

      assert {:ok, user} = Users.find_or_create_user_from_auth(auth)
      assert user.email == "alice@tuist.dev"
      assert user.name == "Alice"
      assert Roles.list_roles_for_user(user) == []
    end

    test "matches the allowed domain case-insensitively" do
      auth = build_auth(email: "Bob@Tuist.DEV", name: "Bob")

      assert {:ok, _user} = Users.find_or_create_user_from_auth(auth)
    end

    test "rejects users from other domains" do
      auth = build_auth(email: "intruder@example.com", name: "Intruder")

      assert {:error, :unauthorized_domain} = Users.find_or_create_user_from_auth(auth)
      assert Users.get_user_by_email("intruder@example.com") == nil
    end

    test "updates the name on subsequent sign-ins" do
      first = build_auth(email: "carol@tuist.dev", name: "Carol")
      second = build_auth(email: "carol@tuist.dev", name: "Carol Smith")

      assert {:ok, user} = Users.find_or_create_user_from_auth(first)
      assert {:ok, updated} = Users.find_or_create_user_from_auth(second)
      assert updated.id == user.id
      assert updated.name == "Carol Smith"
    end

    test "preserves the stored role assignments on subsequent sign-ins" do
      user =
        %User{}
        |> User.changeset(%{email: "chief@tuist.dev", name: "Chief"})
        |> Repo.insert!()

      executive_role = Roles.ensure_executive_role!()

      %UserRole{}
      |> UserRole.changeset(%{user_id: user.id, role_id: executive_role.id})
      |> Repo.insert!()

      auth = build_auth(email: "chief@tuist.dev", name: "Chief Executive")

      assert {:ok, user} = Users.find_or_create_user_from_auth(auth)
      assert user.name == "Chief Executive"
      assert Enum.any?(Roles.list_roles_for_user(user), &(&1.id == executive_role.id))
      assert Users.has_scope?(user, "admin:read")
    end
  end

  defp build_auth(opts) do
    %Ueberauth.Auth{
      info: %Info{
        email: Keyword.fetch!(opts, :email),
        name: Keyword.fetch!(opts, :name)
      }
    }
  end
end
