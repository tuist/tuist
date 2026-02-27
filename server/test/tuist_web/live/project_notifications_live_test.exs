defmodule TuistWeb.ProjectNotificationsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true

  import Phoenix.LiveViewTest

  alias Tuist.Alerts
  alias Tuist.Alerts.AlertRule
  alias TuistTestSupport.Fixtures.AlertsFixtures

  describe "delete_alert_rule" do
    test "does not allow deleting an alert rule belonging to a different project", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given: an alert rule on a completely different project/account
      other_alert_rule = AlertsFixtures.alert_rule_fixture()

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/notifications")

      # When: the user sends a delete event with the other project's alert rule ID
      render_hook(lv, "delete_alert_rule", %{"alert_rule_id" => other_alert_rule.id})

      # Then: the alert rule should still exist (deletion should have been rejected)
      assert {:ok, _} = Alerts.get_alert_rule(other_alert_rule.id)
    end
  end

  describe "update_alert_rule" do
    test "does not allow updating an alert rule belonging to a different project", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given: an alert rule on a completely different project/account
      other_alert_rule = AlertsFixtures.alert_rule_fixture(name: "Original Name")

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/notifications")

      # When: the user sends an update event with the other project's alert rule ID
      render_hook(lv, "update_alert_rule", %{"id" => other_alert_rule.id})

      # Then: the alert rule should be unchanged
      {:ok, unchanged_rule} = Alerts.get_alert_rule(other_alert_rule.id)
      assert unchanged_rule.name == "Original Name"
    end

    test "successfully updates an alert rule belonging to the current project", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given: an alert rule on the current project
      alert_rule = AlertsFixtures.alert_rule_fixture(project: project, name: "Original Name")

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/notifications")

      # When: the user updates the name via the edit form and saves
      render_hook(lv, "update_edit_alert_form_name", %{"id" => alert_rule.id, "value" => "Updated Name"})
      render_hook(lv, "update_alert_rule", %{"id" => alert_rule.id})

      # Then: the alert rule should be updated
      {:ok, updated_rule} = Alerts.get_alert_rule(alert_rule.id)
      assert updated_rule.name == "Updated Name"
    end

    test "updates a rule that appeared after deleting another rule", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given: project starts with rule A
      rule_a = AlertsFixtures.alert_rule_fixture(project: project, name: "Rule A")

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/notifications")

      # And: another user creates rule B on the same project
      rule_b = AlertsFixtures.alert_rule_fixture(project: project, name: "Rule B")

      # When: the current user deletes rule A (which refreshes alert_rules from DB,
      # now including rule B, but does NOT rebuild edit_alert_forms)
      render_hook(lv, "delete_alert_rule", %{"alert_rule_id" => rule_a.id})

      # And: the user opens rule B's edit modal and clicks Update without editing
      render_hook(lv, "update_alert_rule", %{"id" => rule_b.id})

      # Then: rule B should remain unchanged (no crash)
      {:ok, unchanged_rule} = Alerts.get_alert_rule(rule_b.id)
      assert unchanged_rule.name == "Rule B"
    end
  end

  describe "render" do
    test "renders page when a bundle_size alert rule has a non-bundle-size metric", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given: a bundle_size alert rule with an invalid metric (e.g. :p99 instead of :install_size)
      # inserted directly to simulate legacy data that predates the changeset validation
      %AlertRule{}
      |> Ecto.Changeset.change(%{
        project_id: project.id,
        name: "Legacy Alert",
        category: :bundle_size,
        metric: :p99,
        deviation_percentage: 20.0,
        git_branch: "main",
        slack_channel_id: "C123456",
        slack_channel_name: "test-channel"
      })
      |> Tuist.Repo.insert!()

      # When/Then: the page should render without crashing
      {:ok, _lv, html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/notifications")

      assert html =~ "Metrics"
    end
  end

  describe "environment filter" do
    test "creates an alert rule with the selected environment", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/notifications")

      # When: user selects CI environment, sets a channel, then creates the alert rule
      render_hook(lv, "update_create_alert_form_environment", %{"environment" => "ci"})

      render_hook(lv, "create_alert_form_channel_selected", %{
        "channel_id" => "C123456",
        "channel_name" => "test-channel"
      })

      render_hook(lv, "create_alert_rule", %{})

      # Then: the alert rule is persisted with :ci environment
      [alert_rule] = Alerts.get_project_alert_rules(project)
      assert alert_rule.environment == :ci
    end

    test "updates the environment of an existing alert rule", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given: an alert rule with :any environment
      alert_rule = AlertsFixtures.alert_rule_fixture(project: project, environment: "any")

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/notifications")

      # When: user changes environment to local and saves
      render_hook(lv, "update_edit_alert_form_environment", %{
        "id" => alert_rule.id,
        "environment" => "local"
      })

      render_hook(lv, "update_alert_rule", %{"id" => alert_rule.id})

      # Then: the alert rule is updated with :local environment
      {:ok, updated_rule} = Alerts.get_alert_rule(alert_rule.id)
      assert updated_rule.environment == :local
    end

    test "renders environment label in create form description when environment is ci", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given
      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/notifications")

      # When: user selects CI environment
      html = render_hook(lv, "update_create_alert_form_environment", %{"environment" => "ci"})

      # Then: description shows "CI" (uppercase)
      assert html =~ "CI"
    end

    test "renders environment label in edit form description when environment is local", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given: an existing alert rule
      alert_rule = AlertsFixtures.alert_rule_fixture(project: project)

      {:ok, lv, _html} =
        live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/notifications")

      # When: user changes environment to local
      html =
        render_hook(lv, "update_edit_alert_form_environment", %{
          "id" => alert_rule.id,
          "environment" => "local"
        })

      # Then: description shows "local" (lowercase)
      assert html =~ "local"
    end
  end

  describe "create_alert_rule" do
    test "does not allow creating an alert rule when user lacks project_update permission", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # Given: a user who only has :user role (not :admin) on the organization
      non_admin_user = TuistTestSupport.Fixtures.AccountsFixtures.user_fixture()
      Tuist.Accounts.add_user_to_organization(non_admin_user, organization, role: :user)
      conn = TuistTestSupport.Cases.ConnCase.log_in_user(conn, non_admin_user)

      # The mount check should reject non-admin users
      assert_raise TuistWeb.Errors.UnauthorizedError, fn ->
        live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/notifications")
      end
    end
  end
end
