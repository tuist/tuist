defmodule Tuist.NotificationsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Accounts
  alias Tuist.Notifications
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  test "new previews follow the user's organization choice unless a project overrides it" do
    user = AccountsFixtures.user_fixture(preload: [:account])
    organization = AccountsFixtures.organization_fixture(name: "acme", creator: user, preload: [:account])
    shop = ProjectsFixtures.project_fixture(account_id: organization.account.id, name: "ios-shop")
    admin = ProjectsFixtures.project_fixture(account_id: organization.account.id, name: "android-admin")
    personal = ProjectsFixtures.project_fixture(account_id: user.account.id)

    assert Enum.all?([shop, admin, personal], &Notifications.notify?(user.id, "new_preview", &1.id))

    assert :ok = Notifications.update_account_preference(user, "new_preview", organization.account.id, false)
    assert :ok = Notifications.update_project_preference(user, "new_preview", shop.id, true)

    refute Notifications.notify?(user.id, "new_preview", admin.id)
    assert Notifications.notify?(user.id, "new_preview", shop.id)
    assert Notifications.notify?(user.id, "new_preview", personal.id)

    preferences = Notifications.preferences(user, "new_preview")

    assert %{
             enabled: false,
             projects: [
               %{project: %{name: "android-admin"}, override: nil, enabled: false},
               %{project: %{name: "ios-shop"}, override: true, enabled: true}
             ]
           } = Enum.find(preferences, &(&1.account.name == "acme"))

    assert %{enabled: true, projects: [%{override: nil, enabled: true}]} =
             Enum.find(preferences, &(&1.account.id == user.account.id))

    # Turning the organization back on keeps overrides; an off override mutes a project.
    assert :ok = Notifications.update_account_preference(user, "new_preview", organization.account.id, true)
    assert :ok = Notifications.update_project_preference(user, "new_preview", admin.id, false)
    refute Notifications.notify?(user.id, "new_preview", admin.id)
    assert Notifications.notify?(user.id, "new_preview", shop.id)

    assert :ok = Notifications.update_project_preference(user, "new_preview", admin.id, nil)
    assert Notifications.notify?(user.id, "new_preview", admin.id)
  end

  test "preferences belong to one user and only cover their accounts" do
    user = AccountsFixtures.user_fixture(preload: [:account])
    teammate = AccountsFixtures.user_fixture(preload: [:account])
    organization = AccountsFixtures.organization_fixture(creator: user, preload: [:account])
    Accounts.add_user_to_organization(teammate, organization)
    project = ProjectsFixtures.project_fixture(account_id: organization.account.id)
    foreign = ProjectsFixtures.project_fixture()

    assert :ok = Notifications.update_account_preference(teammate, "new_preview", organization.account.id, false)
    refute Notifications.notify?(teammate.id, "new_preview", project.id)
    assert Notifications.notify?(user.id, "new_preview", project.id)

    assert {:error, :invalid} = Notifications.update_account_preference(user, "new_preview", foreign.account_id, false)
    assert {:error, :invalid} = Notifications.update_project_preference(user, "new_preview", foreign.id, false)

    assert {:error, :invalid} =
             Notifications.update_account_preference(user, "new_preview", organization.account.id, "no")

    assert {:error, :invalid} = Notifications.update_project_preference(user, "unknown", project.id, false)
    refute Enum.any?(Notifications.preferences(user, "new_preview"), &(&1.account.id == foreign.account_id))

    # An organization without projects yet can still be turned off for its future projects.
    empty = AccountsFixtures.organization_fixture(creator: user, preload: [:account])

    assert %{enabled: true, projects: []} =
             Enum.find(Notifications.preferences(user, "new_preview"), &(&1.account.id == empty.account.id))

    assert :ok = Notifications.update_account_preference(user, "new_preview", empty.account.id, false)
    later = ProjectsFixtures.project_fixture(account_id: empty.account.id)
    refute Notifications.notify?(user.id, "new_preview", later.id)
  end
end
