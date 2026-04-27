defmodule TuistWeb.ProjectAutomationsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true

  import Phoenix.LiveViewTest

  alias Tuist.Automations
  alias TuistTestSupport.Fixtures.AutomationsFixtures

  defp open(conn, organization, project) do
    live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/automations")
  end

  describe "page rendering" do
    test "shows the empty state when no automations exist", %{conn: conn, organization: organization, project: project} do
      {:ok, _lv, html} = open(conn, organization, project)

      assert html =~ "Test case automations"
      assert html =~ "No automations yet"
    end

    test "lists existing automations in the table", %{conn: conn, organization: organization, project: project} do
      automation = AutomationsFixtures.automation_alert_fixture(project: project, name: "My automation")

      {:ok, _lv, html} = open(conn, organization, project)

      assert html =~ "My automation"
      refute html =~ "No automations yet"
      assert html =~ automation.id
    end
  end

  describe "creating an automation" do
    test "creates an automation through the modal form", %{conn: conn, organization: organization, project: project} do
      {:ok, lv, _html} = open(conn, organization, project)

      render_hook(lv, "open_create_automation_modal", %{})
      render_hook(lv, "update_create_automation_form_name", %{"value" => "Auto-quarantine"})
      render_hook(lv, "save_automation", %{})

      assert [automation] = Automations.list_alerts(project.id)
      assert automation.name == "Auto-quarantine"
      assert automation.monitor_type == "flakiness_rate"
      # Non-destructive default: label-only, no quarantine. Users can add
      # `change_state: muted` explicitly from the "Add action" dropdown.
      assert [%{"type" => "add_label", "label" => "flaky"}] = automation.trigger_actions
    end

    test "preserves the type-specific threshold default when switching types", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = open(conn, organization, project)

      render_hook(lv, "open_create_automation_modal", %{})
      render_hook(lv, "update_create_automation_form_name", %{"value" => "Flaky runs"})
      render_hook(lv, "update_create_automation_form_type", %{"data" => "flaky_run_count"})
      render_hook(lv, "save_automation", %{})

      assert [automation] = Automations.list_alerts(project.id)
      assert automation.monitor_type == "flaky_run_count"
      assert automation.trigger_config["threshold"] == 3
    end

    test "supports adding multiple actions and dropping the change_state option once added", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = open(conn, organization, project)

      render_hook(lv, "open_create_automation_modal", %{})
      render_hook(lv, "update_create_automation_form_name", %{"value" => "Multi-action"})
      # Default trigger action is `add_label: flaky`; user opts into quarantine
      # via the dropdown to layer `change_state: muted` on top.
      render_hook(lv, "add_create_automation_form_trigger_action", %{"data" => "change_state"})
      render_hook(lv, "save_automation", %{})

      assert [automation] = Automations.list_alerts(project.id)

      assert [
               %{"type" => "add_label", "label" => "flaky"},
               %{"type" => "change_state", "state" => "muted"}
             ] = automation.trigger_actions
    end

    test "deleting all trigger actions does not save (validation rejects empty list)", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = open(conn, organization, project)

      render_hook(lv, "open_create_automation_modal", %{})
      render_hook(lv, "update_create_automation_form_name", %{"value" => "Empty actions"})
      render_hook(lv, "delete_create_automation_form_trigger_action", %{"index" => "0"})
      render_hook(lv, "save_automation", %{})

      assert Automations.list_alerts(project.id) == []
    end

    test "creates a manually_marked_flaky automation with empty trigger_config and strips the default add_label action",
         %{conn: conn, organization: organization, project: project} do
      {:ok, lv, _html} = open(conn, organization, project)

      render_hook(lv, "open_create_automation_modal", %{})
      render_hook(lv, "update_create_automation_form_name", %{"value" => "Quarantine on manual mark"})
      render_hook(lv, "update_create_automation_form_type", %{"data" => "manually_marked_flaky"})
      # The default add_label action makes no sense once the user just marked
      # the test as flaky, so the type switch should drop it. We then layer on
      # an explicit change_state action.
      render_hook(lv, "add_create_automation_form_trigger_action", %{"data" => "change_state"})
      render_hook(lv, "save_automation", %{})

      assert [automation] = Automations.list_alerts(project.id)
      assert automation.monitor_type == "manually_marked_flaky"
      assert automation.trigger_config == %{}
      assert [%{"type" => "change_state", "state" => "muted"}] = automation.trigger_actions
    end

    test "hides threshold/window/recovery-window inputs for manually_marked_flaky", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = open(conn, organization, project)

      render_hook(lv, "open_create_automation_modal", %{})
      render_hook(lv, "toggle_create_automation_form_recovery", %{})
      html = render_hook(lv, "update_create_automation_form_type", %{"data" => "manually_marked_flaky"})

      refute html =~ "create-automation-threshold"
      refute html =~ "create-automation-window"
      refute html =~ "create-automation-recovery-days"
    end
  end

  describe "editing an automation" do
    test "edit_automation populates the form and save_automation updates the existing automation", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      automation = AutomationsFixtures.automation_alert_fixture(project: project, name: "Original")

      {:ok, lv, _html} = open(conn, organization, project)

      render_hook(lv, "edit_automation", %{"id" => automation.id})
      render_hook(lv, "update_create_automation_form_name", %{"value" => "Renamed"})
      render_hook(lv, "save_automation", %{})

      assert [updated] = Automations.list_alerts(project.id)
      assert updated.id == automation.id
      assert updated.name == "Renamed"
    end

    test "edit_automation does nothing for an automation in another project", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      other = AutomationsFixtures.automation_alert_fixture()
      {:ok, lv, _html} = open(conn, organization, project)
      render_hook(lv, "edit_automation", %{"id" => other.id})
      assert {:ok, ^other} = Automations.get_alert(other.id)
    end
  end

  describe "toggling and deleting" do
    test "toggle_automation_enabled flips the enabled flag", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      automation = AutomationsFixtures.automation_alert_fixture(project: project, enabled: true)
      {:ok, lv, _html} = open(conn, organization, project)
      render_hook(lv, "toggle_automation_enabled", %{"id" => automation.id})
      assert {:ok, %{enabled: false}} = Automations.get_alert(automation.id)
    end

    test "delete_automation removes the automation", %{conn: conn, organization: organization, project: project} do
      automation = AutomationsFixtures.automation_alert_fixture(project: project)
      {:ok, lv, _html} = open(conn, organization, project)
      render_hook(lv, "delete_automation", %{"id" => automation.id})
      assert {:error, :not_found} = Automations.get_alert(automation.id)
    end

    test "delete_automation does not delete an automation in another project", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      other = AutomationsFixtures.automation_alert_fixture()
      {:ok, lv, _html} = open(conn, organization, project)
      render_hook(lv, "delete_automation", %{"id" => other.id})
      assert {:ok, ^other} = Automations.get_alert(other.id)
    end
  end
end
