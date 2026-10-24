defmodule Atlas.UsersTest do
  use Atlas.DataCase, async: true

  alias Atlas.Authorization.Roles
  alias Atlas.Authorization.UserRole
  alias Atlas.Users
  alias Atlas.Users.User
  alias Ueberauth.Auth.Info

  test "self description is bounded, independent of identity, and private background only" do
    {:ok, actor} = Users.find_or_create_user_from_auth(build_auth(email: "profile@tuist.dev", name: "Profile"))
    {:ok, other} = Users.find_or_create_user_from_auth(build_auth(email: "other-profile@tuist.dev", name: "Other"))
    description = "Engineering lead\nCurious; concise answers please."
    assert {:ok, saved} = Users.update_my_profile(actor, "  " <> description <> "\n")
    assert saved.description == description
    assert saved.name == actor.name and saved.email == actor.email
    assert Users.get_user(other.id).description == ""
    assert Users.profile_description_for(actor, :private) == description
    assert Users.profile_description_for(actor, :shared) == nil
    assert Users.profile_description_for(nil, :private) == nil
    assert {:ok, _} = Users.update_my_profile(actor, "")
    assert Users.profile_description_for(actor, :private) == nil

    assert {:ok, _} = Users.update_my_profile(actor, String.duplicate("🦀", 4000))
    assert {:error, %Ecto.Changeset{}} = Users.update_my_profile(actor, String.duplicate("🦀", 4001))
    assert {:error, %Ecto.Changeset{}} = Users.update_my_profile(actor, String.duplicate("é", 2001))

    for invalid <- [nil, 42, %{"description" => "no mass assignment"}, "null\0byte", <<255>>] do
      assert {:error, :invalid_params} = Users.update_my_profile(actor, invalid)
    end

    changeset = User.changeset(actor, %{description: "not an SSO field"})
    refute Map.has_key?(changeset.changes, :description)
  end

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
