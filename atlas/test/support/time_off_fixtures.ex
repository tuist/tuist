defmodule Atlas.TimeOffFixtures do
  alias Atlas.Authorization.Roles
  alias Atlas.Authorization.UserRole
  alias Atlas.Repo
  alias Atlas.TimeOff
  alias Atlas.Users.User

  def user_fixture(attrs \\ %{}) do
    %User{}
    |> User.changeset(
      Map.merge(%{email: "time-off-#{System.unique_integer([:positive])}@example.com", name: "Team member"}, attrs)
    )
    |> Repo.insert!()
  end

  def admin_fixture do
    user = user_fixture()
    role = Roles.ensure_executive_role!()
    %UserRole{} |> UserRole.changeset(%{user_id: user.id, role_id: role.id}) |> Repo.insert!()
    user
  end

  def location_fixture(admin, attrs \\ %{}) do
    {:ok, location} =
      TimeOff.create_location(
        Map.merge(
          %{name: "Berlin #{System.unique_integer([:positive])}", country_code: "DE", subdivision_code: "DE-BE"},
          attrs
        ),
        admin
      )

    location
  end

  def assign_fixture(user, location, admin) do
    {:ok, user} = TimeOff.assign_location(user.id, location.id, admin)
    user
  end
end
