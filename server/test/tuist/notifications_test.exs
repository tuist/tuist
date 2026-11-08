defmodule Tuist.NotificationsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.Accounts
  alias Tuist.Notifications
  alias Tuist.Notifications.Events.PreviewPublished
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    organization = AccountsFixtures.organization_fixture(name: "acme", creator: user, preload: [:account])
    shop = ProjectsFixtures.project_fixture(account_id: organization.account.id, name: "ios-shop")
    admin = ProjectsFixtures.project_fixture(account_id: organization.account.id, name: "android-admin")
    %{user: user, organization: organization, shop: shop, admin: admin}
  end

  defp rule_attrs(attrs), do: Map.merge(%{event: "preview_published", actions: [%{type: "push"}]}, attrs)

  defp recipient_ids(project, preview) do
    PreviewPublished |> Notifications.recipients(project, preview) |> Enum.map(&elem(&1, 0))
  end

  test "creates a rule with normalized conditions and only the user's projects", %{user: user, shop: shop} do
    assert {:ok, rule} =
             Notifications.create_rule(
               user,
               rule_attrs(%{
                 projects: ["acme/ios-shop", "acme/ios-shop"],
                 conditions: %{track: %{operator: "is", value: " beta "}, published_by: "anyone"}
               })
             )

    assert %{
             "event" => "preview_published",
             "enabled" => true,
             "projects" => ["acme/ios-shop"],
             "conditions" => %{"track" => %{"operator" => "is", "value" => "beta"}},
             "actions" => [%{"type" => "push"}]
           } = Notifications.rule_to_map(rule)

    assert [%{id: id}] = Notifications.list_rules(user)
    assert id == rule.id

    assert [{user.id, ["push"]}] ==
             Notifications.recipients(
               PreviewPublished,
               shop,
               AppBuildsFixtures.preview_fixture(project: shop, track: "beta")
             )

    foreign = ProjectsFixtures.project_fixture(preload: [:account])

    assert {:error, {:invalid, message}} =
             Notifications.create_rule(user, rule_attrs(%{projects: ["#{foreign.account.name}/#{foreign.name}"]}))

    assert message =~ foreign.name
    assert {:error, %Ecto.Changeset{} = changeset} = Notifications.create_rule(user, rule_attrs(%{event: "deploy"}))
    assert Notifications.error_message(changeset) =~ "event is not a known notification event"
    assert {:error, %Ecto.Changeset{}} = Notifications.create_rule(user, rule_attrs(%{actions: []}))
    assert {:error, %Ecto.Changeset{}} = Notifications.create_rule(user, rule_attrs(%{actions: [%{type: "email"}]}))

    assert {:error, %Ecto.Changeset{}} =
             Notifications.create_rule(user, rule_attrs(%{conditions: %{track: %{operator: "matches", value: "x"}}}))

    assert {:error, %Ecto.Changeset{}} = Notifications.create_rule(user, rule_attrs(%{conditions: %{platform: "ios"}}))
    assert length(Notifications.list_rules(user)) == 1
  end

  test "matches previews by project, track, branch and publisher", %{
    user: user,
    organization: organization,
    shop: shop,
    admin: admin
  } do
    colleague = AccountsFixtures.user_fixture(preload: [:account])
    Accounts.add_user_to_organization(colleague, organization)

    {:ok, _} =
      Notifications.create_rule(
        user,
        rule_attrs(%{projects: ["acme/ios-shop"], conditions: %{git_branch: %{operator: "contains", value: "Release/"}}})
      )

    {:ok, _} = Notifications.create_rule(colleague, rule_attrs(%{conditions: %{published_by: "me"}}))

    release = AppBuildsFixtures.preview_fixture(project: shop, git_branch: "release/2.0")
    assert recipient_ids(shop, release) == [user.id]
    assert recipient_ids(shop, AppBuildsFixtures.preview_fixture(project: shop, git_branch: "main")) == []
    # The user's rule lists only ios-shop.
    assert recipient_ids(admin, AppBuildsFixtures.preview_fixture(project: admin, git_branch: "release/2.0")) == []

    # A rule without projects covers every project, including ones created later.
    later = ProjectsFixtures.project_fixture(account_id: organization.account.id)
    by_colleague = AppBuildsFixtures.preview_fixture(project: later, created_by_account_id: colleague.account.id)
    assert recipient_ids(later, by_colleague) == [colleague.id]
    assert recipient_ids(later, AppBuildsFixtures.preview_fixture(project: later)) == []
  end

  test "updates a rule's fields but not its event, and keeps rules private", %{user: user, admin: admin} do
    {:ok, rule} = Notifications.create_rule(user, rule_attrs(%{projects: ["acme/ios-shop"]}))

    assert {:ok, updated} =
             Notifications.update_rule(user, rule, %{
               "event" => "deploy",
               "projects" => ["acme/android-admin"],
               "enabled" => false
             })

    assert %{"event" => "preview_published", "projects" => ["acme/android-admin"], "enabled" => false} =
             Notifications.rule_to_map(updated)

    assert recipient_ids(admin, AppBuildsFixtures.preview_fixture(project: admin)) == []

    assert {:ok, updated} = Notifications.update_rule(user, updated, %{enabled: true})
    assert Notifications.rule_to_map(updated)["projects"] == ["acme/android-admin"]
    assert recipient_ids(admin, AppBuildsFixtures.preview_fixture(project: admin)) == [user.id]

    other = AccountsFixtures.user_fixture()
    assert {:error, :not_found} = Notifications.get_rule(other, rule.id)
    assert {:error, :not_found} = Notifications.get_rule(user, "not-a-uuid")
    assert :ok = Notifications.delete_rule(user, updated)
    assert Notifications.list_rules(user) == []
  end

  test "suggests the tracks and branches of the project's recent previews", %{user: user, shop: shop} do
    AppBuildsFixtures.preview_fixture(project: shop, track: "beta", git_branch: "main")
    AppBuildsFixtures.preview_fixture(project: shop, track: "", git_branch: "feature/a")
    AppBuildsFixtures.preview_fixture(project: shop, track: "beta", git_branch: "main")

    AppBuildsFixtures.preview_fixture(
      project: shop,
      track: "old",
      inserted_at: DateTime.add(DateTime.utc_now(), -100, :day)
    )

    assert {:ok, %{"track" => ["beta"], "git_branch" => ["feature/a", "main"]}} =
             Notifications.condition_options(user, "preview_published", shop)

    assert {:error, :not_found} = Notifications.condition_options(user, "deploy", shop)

    assert {:error, :not_found} =
             Notifications.condition_options(AccountsFixtures.user_fixture(), "preview_published", shop)
  end
end
