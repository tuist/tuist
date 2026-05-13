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

    test "preserves the metric-specific threshold default when switching metrics", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = open(conn, organization, project)

      render_hook(lv, "open_create_automation_modal", %{})
      render_hook(lv, "update_create_automation_form_name", %{"value" => "Flaky runs"})
      render_hook(lv, "update_create_automation_form_metric", %{"data" => "flaky_run_count"})
      render_hook(lv, "save_automation", %{})

      assert [automation] = Automations.list_alerts(project.id)
      assert automation.monitor_type == "flaky_run_count"
      assert automation.trigger_config["threshold"] == 3
    end

    test "switching the comparison to lt persists it without touching threshold or actions", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = open(conn, organization, project)

      render_hook(lv, "open_create_automation_modal", %{})
      render_hook(lv, "update_create_automation_form_name", %{"value" => "Cleanup"})
      render_hook(lv, "update_create_automation_form_metric", %{"data" => "flaky_run_count"})
      render_hook(lv, "update_create_automation_form_comparison", %{"data" => "lt"})
      render_hook(lv, "save_automation", %{})

      assert [automation] = Automations.list_alerts(project.id)
      assert automation.monitor_type == "flaky_run_count"
      assert automation.trigger_config["comparison"] == "lt"
      # Threshold stays at the metric default (3) — switching comparison
      # doesn't clobber whatever the user typed.
      assert automation.trigger_config["threshold"] == 3
      # Trigger actions stay at the form default; the user picks Unmark as
      # flaky explicitly via the action dropdown.
      assert [%{"type" => "add_label", "label" => "flaky"}] = automation.trigger_actions
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

    test "defaults to last_days window_type with the existing window string", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = open(conn, organization, project)

      render_hook(lv, "open_create_automation_modal", %{})
      render_hook(lv, "update_create_automation_form_name", %{"value" => "Default"})
      render_hook(lv, "save_automation", %{})

      assert [automation] = Automations.list_alerts(project.id)
      assert automation.trigger_config["window_type"] == "last_days"
      assert automation.trigger_config["window"] == "30d"
      refute Map.has_key?(automation.trigger_config, "rolling_window_size")
    end

    test "switching to rolling window persists rolling_window_size and drops the days window", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = open(conn, organization, project)

      render_hook(lv, "open_create_automation_modal", %{})
      render_hook(lv, "update_create_automation_form_name", %{"value" => "Rolling"})
      render_hook(lv, "update_create_automation_form_window_type", %{"data" => "rolling"})
      render_hook(lv, "update_create_automation_form_rolling_window_size", %{"value" => "50"})
      render_hook(lv, "save_automation", %{})

      assert [automation] = Automations.list_alerts(project.id)
      assert automation.trigger_config["window_type"] == "rolling"
      assert automation.trigger_config["rolling_window_size"] == 50
      refute Map.has_key?(automation.trigger_config, "window")
    end

    test "ignores window_type values that are not in the allowlist", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = open(conn, organization, project)

      render_hook(lv, "open_create_automation_modal", %{})
      render_hook(lv, "update_create_automation_form_name", %{"value" => "Bogus"})
      render_hook(lv, "update_create_automation_form_window_type", %{"data" => "weekly"})
      render_hook(lv, "save_automation", %{})

      assert [automation] = Automations.list_alerts(project.id)
      assert automation.trigger_config["window_type"] == "last_days"
    end

    test "disables Save when rolling_window_size is above the cap", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = open(conn, organization, project)

      render_hook(lv, "open_create_automation_modal", %{})
      render_hook(lv, "update_create_automation_form_name", %{"value" => "Over cap"})
      render_hook(lv, "update_create_automation_form_window_type", %{"data" => "rolling"})
      render_hook(lv, "update_create_automation_form_rolling_window_size", %{"value" => "100000"})

      # The Save button itself is rendered as disabled, so the user can't
      # click it and the changeset's cap is never exercised silently.
      assert render(lv) =~
               ~s(<button class="noora-button" data-variant="primary" data-size="large" disabled="" type="button" phx-click="save_automation"><span>Create</span></button>)

      # And even if we force the click, no alert is created.
      render_hook(lv, "save_automation", %{})
      assert Automations.list_alerts(project.id) == []
    end

    test "re-enables Save when rolling_window_size is brought within the cap", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = open(conn, organization, project)

      render_hook(lv, "open_create_automation_modal", %{})
      render_hook(lv, "update_create_automation_form_name", %{"value" => "Within cap"})
      render_hook(lv, "update_create_automation_form_window_type", %{"data" => "rolling"})
      render_hook(lv, "update_create_automation_form_rolling_window_size", %{"value" => "100000"})
      render_hook(lv, "update_create_automation_form_rolling_window_size", %{"value" => "500"})

      render_hook(lv, "save_automation", %{})
      assert [automation] = Automations.list_alerts(project.id)
      assert automation.trigger_config["rolling_window_size"] == 500
    end

    test "rolling recovery window persists rolling_window_size and drops the days window", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = open(conn, organization, project)

      render_hook(lv, "open_create_automation_modal", %{})
      render_hook(lv, "update_create_automation_form_name", %{"value" => "Rolling recovery"})
      render_hook(lv, "toggle_create_automation_form_recovery", %{})
      render_hook(lv, "update_create_automation_form_recovery_window_type", %{"data" => "rolling"})

      render_hook(lv, "update_create_automation_form_recovery_rolling_window_size", %{
        "value" => "25"
      })

      render_hook(lv, "save_automation", %{})

      assert [automation] = Automations.list_alerts(project.id)
      assert automation.recovery_config["window_type"] == "rolling"
      assert automation.recovery_config["rolling_window_size"] == 25
      refute Map.has_key?(automation.recovery_config, "window")
    end

    test "last_days recovery window persists window string", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = open(conn, organization, project)

      render_hook(lv, "open_create_automation_modal", %{})
      render_hook(lv, "update_create_automation_form_name", %{"value" => "Days recovery"})
      render_hook(lv, "toggle_create_automation_form_recovery", %{})
      render_hook(lv, "save_automation", %{})

      assert [automation] = Automations.list_alerts(project.id)
      assert automation.recovery_config["window_type"] == "last_days"
      assert automation.recovery_config["window"] == "14d"
      refute Map.has_key?(automation.recovery_config, "rolling_window_size")
    end

    test "creates a test_updated automation subscribed to the default marked_flaky event", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = open(conn, organization, project)

      render_hook(lv, "open_create_automation_modal", %{})
      render_hook(lv, "update_create_automation_form_name", %{"value" => "Quarantine on manual mark"})
      render_hook(lv, "update_create_automation_form_metric", %{"data" => "test_updated"})
      # Switching the metric stripped the default add_label trigger action;
      # layer on an explicit change_state.
      render_hook(lv, "add_create_automation_form_trigger_action", %{"data" => "change_state"})
      render_hook(lv, "save_automation", %{})

      assert [automation] = Automations.list_alerts(project.id)
      assert automation.monitor_type == "test_updated"
      assert automation.trigger_config == %{"events" => ["marked_flaky"]}
      assert [%{"type" => "change_state", "state" => "muted"}] = automation.trigger_actions
    end

    test "toggle_create_automation_form_event adds and removes events from the subscription", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = open(conn, organization, project)

      render_hook(lv, "open_create_automation_modal", %{})
      render_hook(lv, "update_create_automation_form_name", %{"value" => "State subscriber"})
      render_hook(lv, "update_create_automation_form_metric", %{"data" => "test_updated"})
      # Default events = ["marked_flaky"]; subscribe to state_changed_to_muted too.
      render_hook(lv, "toggle_create_automation_form_event", %{"data" => "state_changed_to_muted"})
      # Unsubscribe from marked_flaky.
      render_hook(lv, "toggle_create_automation_form_event", %{"data" => "marked_flaky"})
      render_hook(lv, "add_create_automation_form_trigger_action", %{"data" => "change_state"})
      render_hook(lv, "save_automation", %{})

      assert [automation] = Automations.list_alerts(project.id)
      assert automation.trigger_config["events"] == ["state_changed_to_muted"]
    end

    test "hides threshold/window/recovery section for test_updated", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = open(conn, organization, project)

      render_hook(lv, "open_create_automation_modal", %{})
      # Toggle recovery on before switching — the type switch must force it off.
      render_hook(lv, "toggle_create_automation_form_recovery", %{})
      render_hook(lv, "update_create_automation_form_metric", %{"data" => "test_updated"})

      # Re-render explicitly so we assert against the full post-event DOM,
      # not just the hook's reply payload. This catches stale window /
      # threshold / recovery inputs that the gate would let through.
      html = render(lv)

      refute html =~ "create-automation-threshold"
      refute html =~ ~s(id="create-automation-window")
      refute html =~ ~s(id="create-automation-window-type-dropdown")
      refute html =~ ~s(id="create-automation-rolling-window-size")
      refute html =~ "create-automation-recovery-days"
      refute html =~ "create-automation-recovery-toggle"
      # The inline events multi-select renders instead.
      assert html =~ "create-automation-events"
      assert html =~ "create-automation-event-marked_flaky"
    end

    test "switching to test_updated forces recovery off", %{conn: conn, organization: organization, project: project} do
      {:ok, lv, _html} = open(conn, organization, project)

      render_hook(lv, "open_create_automation_modal", %{})
      render_hook(lv, "toggle_create_automation_form_recovery", %{})
      render_hook(lv, "update_create_automation_form_metric", %{"data" => "test_updated"})
      render_hook(lv, "update_create_automation_form_name", %{"value" => "Mark trigger"})
      render_hook(lv, "add_create_automation_form_trigger_action", %{"data" => "change_state"})
      render_hook(lv, "save_automation", %{})

      assert [automation] = Automations.list_alerts(project.id)
      refute automation.recovery_enabled
    end

    test "Save is disabled when switching to test_updated strips the only action", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      # The new form starts with a single `add_label flaky` action. Switching to
      # `test_updated` removes that default (the label flip fights the events
      # the user picks), so the action list is empty and the changeset would
      # reject the save with `trigger_actions can't be blank`. The Save button
      # must reflect that and stay disabled until the user adds an action.
      {:ok, lv, _html} = open(conn, organization, project)

      render_hook(lv, "open_create_automation_modal", %{})
      render_hook(lv, "update_create_automation_form_metric", %{"data" => "test_updated"})
      render_hook(lv, "update_create_automation_form_name", %{"value" => "Mark trigger"})

      assert render(lv) =~
               ~s(<button class="noora-button" data-variant="primary" data-size="large" disabled="" type="button" phx-click="save_automation"><span>Create</span></button>)

      # Adding an action re-enables Save.
      render_hook(lv, "add_create_automation_form_trigger_action", %{"data" => "change_state"})

      refute render(lv) =~
               ~s(<button class="noora-button" data-variant="primary" data-size="large" disabled="" type="button" phx-click="save_automation"><span>Create</span></button>)
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
