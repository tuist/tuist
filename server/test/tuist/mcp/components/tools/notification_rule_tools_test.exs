defmodule Tuist.MCP.Components.Tools.NotificationRuleToolsTest do
  use TuistTestSupport.Cases.DataCase, async: true

  alias Tuist.MCP.Components.Tools.CreateNotificationRule
  alias Tuist.MCP.Components.Tools.DeleteNotificationRule
  alias Tuist.MCP.Components.Tools.ListNotificationConditionOptions
  alias Tuist.MCP.Components.Tools.ListNotificationEvents
  alias Tuist.MCP.Components.Tools.ListNotificationRules
  alias Tuist.MCP.Components.Tools.UpdateNotificationRule
  alias Tuist.Notifications
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.AppBuildsFixtures
  alias TuistTestSupport.Fixtures.ProjectsFixtures

  setup do
    user = AccountsFixtures.user_fixture(preload: [:account])
    project = ProjectsFixtures.project_fixture(account_id: user.account.id, name: "ios-app")
    %{user: user, project: project, conn: %Plug.Conn{assigns: %{current_user: user}}}
  end

  test "creates, updates, lists and deletes the user's rules", %{user: user, project: project, conn: conn} do
    handle = "#{user.account.name}/ios-app"

    assert %{"structuredContent" => %{"events" => [%{"id" => "preview_published"}]}} =
             ListNotificationEvents.call(conn, %{})

    assert %{"structuredContent" => %{"id" => id, "projects" => [^handle]}} =
             CreateNotificationRule.call(conn, %{
               "event" => "preview_published",
               "projects" => [handle],
               "conditions" => %{"git_branch" => %{"operator" => "contains", "value" => "release/"}},
               "actions" => [%{"type" => "push"}]
             })

    assert %{"structuredContent" => %{"enabled" => false, "projects" => []}} =
             UpdateNotificationRule.call(conn, %{"rule_id" => id, "enabled" => false, "projects" => []})

    assert %{"structuredContent" => %{"rules" => [%{"id" => ^id}]}} = ListNotificationRules.call(conn, %{})

    AppBuildsFixtures.preview_fixture(project: project, git_branch: "release/1.0")

    assert %{"structuredContent" => %{"options" => %{"git_branch" => ["release/1.0"]}}} =
             ListNotificationConditionOptions.call(conn, %{
               "event" => "preview_published",
               "account_handle" => user.account.name,
               "project_handle" => "ios-app"
             })

    assert %{"structuredContent" => %{"deleted" => true}} = DeleteNotificationRule.call(conn, %{"rule_id" => id})
    assert Notifications.list_rules(user) == []
    assert DeleteNotificationRule.annotations().destructiveHint
  end

  test "rejects other users' rules and projects, and dashboard requests", %{user: user, conn: conn} do
    other = AccountsFixtures.user_fixture(preload: [:account])
    {:ok, rule} = Notifications.create_rule(other, %{"event" => "preview_published", "actions" => [%{"type" => "push"}]})
    foreign = ProjectsFixtures.project_fixture(account_id: other.account.id)

    assert %{"isError" => true} = UpdateNotificationRule.call(conn, %{"rule_id" => rule.id, "enabled" => false})
    assert %{"isError" => true} = DeleteNotificationRule.call(conn, %{"rule_id" => rule.id})

    assert %{"isError" => true} =
             CreateNotificationRule.call(conn, %{
               "event" => "preview_published",
               "projects" => ["#{other.account.name}/#{foreign.name}"],
               "actions" => [%{"type" => "push"}]
             })

    # Even on the user's personal account pages, because rules reach their organizations.
    scoped = %Plug.Conn{assigns: %{current_user: user, mcp_account_scope: user.account}}
    assert %{"isError" => true} = ListNotificationRules.call(scoped, %{})
    assert [_rule] = Notifications.list_rules(other)
  end
end
