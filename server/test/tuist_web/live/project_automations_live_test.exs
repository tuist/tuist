defmodule TuistWeb.ProjectAutomationsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: false
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true

  import Phoenix.LiveViewTest

  alias Tuist.Accounts
  alias Tuist.Automations
  alias Tuist.Repo
  alias TuistTestSupport.Fixtures.AccountsFixtures
  alias TuistTestSupport.Fixtures.AutomationsFixtures

  setup do
    stub(Automations, :count_existing_matches, fn _alert -> 0 end)
    :ok
  end

  describe "existing match preview" do
    test "loads asynchronously, refreshes the condition, and never shows an obsolete result", context do
      test_pid = self()

      stub(Automations, :count_existing_matches, fn alert ->
        send(test_pid, {:counting, self(), alert.trigger_config})

        receive do
          {:count, count} -> count
        end
      end)

      {:ok, lv, _html} = open(context.conn, context.organization, context.project)
      html = render_hook(lv, "open_create_automation_modal", %{})
      assert html =~ "Counting matching tests"
      assert_receive {:counting, first_task, %{"threshold" => 10.0}}

      monitor = Process.monitor(first_task)
      render_hook(lv, "update_create_automation_form_threshold", %{"value" => "25"})
      assert_receive {:DOWN, ^monitor, :process, ^first_task, _}
      assert_receive {:counting, second_task, %{"threshold" => 25.0}}, 1000
      send(second_task, {:count, 24})
      assert render_async(lv) =~ "24 tests that currently match"

      render_hook(lv, "toggle_create_automation_form_trigger_state", %{"data" => "muted"})
      assert_receive {:counting, third_task, %{"states" => ["muted"]}}, 1000
      send(third_task, {:count, 1})
      assert render_async(lv) =~ "1 test that currently matches"

      html = render_hook(lv, "update_create_automation_form_threshold", %{"value" => ""})
      refute html =~ "1 test that currently matches"
      assert render(lv) =~ "Complete a valid condition"
      refute_receive {:counting, _, _}

      render_hook(lv, "update_create_automation_form_metric", %{"data" => "test_updated"})
      refute has_element?(lv, "#apply-existing-matches-count")
      refute_receive {:counting, _, _}
    end

    test "debounces edits and bounds async state while cancelling in-flight counts", context do
      test_pid = self()

      stub(Automations, :count_existing_matches, fn alert ->
        send(test_pid, {:counting, self(), alert.trigger_config["threshold"]})

        receive do
          :finish -> 1
        end
      end)

      {:ok, lv, _} = open(context.conn, context.organization, context.project)
      render_hook(lv, "open_create_automation_modal", %{})
      assert_receive {:counting, first, 10.0}

      for value <- ["1", "12", "12.", "12.5"] do
        render_hook(lv, "update_create_automation_form_threshold", %{"value" => value})
      end

      refute_receive {:counting, _, _}, 200
      assert_receive {:counting, second, 12.5}, 1000
      refute Process.alive?(first)
      render_hook(lv, "update_create_automation_form_threshold", %{"value" => "20"})
      assert_receive {:counting, third, 20.0}, 1000
      refute Process.alive?(second)
      state = :sys.get_state(lv.pid)
      assert map_size(state.socket.private.live_async) == 1
      send(third, :finish)
      assert render_async(lv) =~ "1 test that currently matches"
    end

    test "invalid conditions cannot be saved and unknown sections preserve the form", context do
      {:ok, lv, _} = open(context.conn, context.organization, context.project)
      render_hook(lv, "open_create_automation_modal", %{})
      render_hook(lv, "update_create_automation_form_name", %{"value" => "Valid name"})

      for value <- ["", "oops", "101"] do
        render_hook(lv, "update_create_automation_form_threshold", %{"value" => value})
        assert render(lv) =~ "Complete a valid condition."
        assert render(lv) =~ ~s(disabled="" type="button" phx-click="save_automation")
        render_hook(lv, "save_automation", %{})
        assert Automations.list_alerts(context.project.id) == []
      end

      assert render_hook(lv, "toggle_create_automation_form_section", %{"section" => "unexpected"}) =~ "Valid name"
      render_hook(lv, "update_create_automation_form_threshold", %{"value" => "25"})
      render_hook(lv, "save_automation", %{})
      assert [automation] = Automations.list_alerts(context.project.id)
      assert automation.trigger_config["threshold"] == 25.0
    end

    test "editing shows pending actions and an unchecked save cancels them", context do
      automation =
        AutomationsFixtures.automation_alert_fixture(
          project: context.project,
          baseline_established_at: nil,
          trigger_config: %{
            "threshold" => 10,
            "window_type" => "last_days",
            "window" => "30d",
            "apply_actions_to_existing_matches" => true
          }
        )

      {:ok, lv, _} = open(context.conn, context.organization, context.project)
      render_hook(lv, "edit_automation", %{"id" => automation.id})
      assert render(lv) =~ "cancel any remaining actions"
      render_hook(lv, "save_automation", %{})
      updated = Repo.reload!(automation)
      refute updated.trigger_config["apply_actions_to_existing_matches"]
      assert updated.baseline_generation == automation.baseline_generation + 1
    end

    test "cancels the in-flight count when the dialog closes without the dismiss button", context do
      test_pid = self()

      stub(Automations, :count_existing_matches, fn _alert ->
        send(test_pid, {:counting, self()})

        receive do
          :finish -> 1
        end
      end)

      {:ok, lv, _} = open(context.conn, context.organization, context.project)
      render_hook(lv, "open_create_automation_modal", %{})
      assert_receive {:counting, task}

      # Escape and click-outside close the dialog client-side and only reach the
      # server through `on_open_change`, never through `on_dismiss`.
      render_hook(lv, "create_automation_modal_open_change", %{"open" => false})

      monitor = Process.monitor(task)
      assert_receive {:DOWN, ^monitor, :process, ^task, _}
      refute render(lv) =~ "Counting matching tests"
    end

    test "an unchanged save records no revision and leaves trigger_config alone", context do
      # The form normalises the threshold and always emits a comparison, so the
      # fixture starts from the config a dashboard save would produce. Any
      # remaining diff is then the one this test is about.
      automation =
        AutomationsFixtures.automation_alert_fixture(
          project: context.project,
          trigger_config: %{
            "threshold" => 10.0,
            "comparison" => "gte",
            "window_type" => "last_days",
            "window" => "30d"
          }
        )

      revisions_before = length(Automations.list_alert_revisions(automation.id))

      {:ok, lv, _} = open(context.conn, context.organization, context.project)
      render_hook(lv, "edit_automation", %{"id" => automation.id})
      render_hook(lv, "save_automation", %{})

      reloaded = Repo.reload!(automation)
      refute Map.has_key?(reloaded.trigger_config, "apply_actions_to_existing_matches")
      assert reloaded.trigger_config == automation.trigger_config
      assert length(Automations.list_alert_revisions(automation.id)) == revisions_before
    end

    test "a malformed recovery window blocks save instead of silently doing nothing", context do
      {:ok, lv, _} = open(context.conn, context.organization, context.project)
      render_hook(lv, "open_create_automation_modal", %{})
      render_hook(lv, "update_create_automation_form_name", %{"value" => "Recovery window"})
      render_hook(lv, "toggle_create_automation_form_recovery", %{})
      html = render_hook(lv, "update_create_automation_form_recovery_window", %{"value" => "14"})

      assert html =~ ~s(disabled="" type="button" phx-click="save_automation")
      render_hook(lv, "save_automation", %{})
      assert Automations.list_alerts(context.project.id) == []

      render_hook(lv, "update_create_automation_form_recovery_window", %{"value" => "14d"})
      render_hook(lv, "save_automation", %{})
      assert [automation] = Automations.list_alerts(context.project.id)
      assert automation.recovery_config["window"] == "14d"
    end

    test "shows failure without blocking save and refreshes when reopened for editing", context do
      stub(Automations, :count_existing_matches, fn _alert -> exit(:unavailable) end)
      {:ok, lv, _html} = open(context.conn, context.organization, context.project)
      render_hook(lv, "open_create_automation_modal", %{})
      assert render_async(lv) =~ "Match count unavailable. You can still save."

      render_hook(lv, "update_create_automation_form_name", %{"value" => "Preview unavailable"})
      render_hook(lv, "save_automation", %{})
      assert [automation] = Automations.list_alerts(context.project.id)

      stub(Automations, :count_existing_matches, fn _alert -> 0 end)
      render_hook(lv, "edit_automation", %{"id" => automation.id})
      assert render_async(lv) =~ "0 tests that currently match"
    end
  end

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

    test "links each automation to its detail page", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      automation = AutomationsFixtures.automation_alert_fixture(project: project, name: "Auto-quarantine")

      {:ok, live_view, _html} = open(conn, organization, project)

      assert has_element?(
               live_view,
               "a[href='/#{organization.account.name}/#{project.name}/settings/automations/#{automation.id}']"
             )
    end

    test "does not let a regular project member forge automation mutations", %{
      organization: organization,
      project: project
    } do
      regular_user = AccountsFixtures.user_fixture()
      Accounts.add_user_to_organization(regular_user, organization, role: :user)
      automation = AutomationsFixtures.automation_alert_fixture(project: project, name: "Protected automation")

      conn = log_in_user(build_conn(), regular_user)
      {:ok, live_view, html} = open(conn, organization, project)

      refute html =~ "Add automation"
      refute has_element?(live_view, "button[phx-click='delete_automation']")

      render_hook(live_view, "open_create_automation_modal", %{})
      render_hook(live_view, "update_create_automation_form_name", %{"value" => "Forged automation"})
      render_hook(live_view, "save_automation", %{})
      render_hook(live_view, "delete_automation", %{"id" => automation.id})

      assert [%{id: id}] = Automations.list_alerts(project.id)
      assert id == automation.id
    end
  end

  describe "creating an automation" do
    test "expands condition and actions for creation, but collapses every section when editing", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = open(conn, organization, project)
      html = render_hook(lv, "open_create_automation_modal", %{})
      document = Floki.parse_document!(html)
      assert Floki.attribute(document, "#automation-condition-toggle", "aria-expanded") == ["true"]
      assert Floki.attribute(document, "#automation-actions-toggle", "aria-expanded") == ["true"]
      assert Floki.attribute(document, "#automation-recovery-toggle", "aria-expanded") == ["false"]

      render_hook(lv, "toggle_create_automation_form_section", %{"section" => "condition"})
      render_hook(lv, "update_create_automation_form_threshold", %{"value" => "25"})
      html = render(lv)
      document = Floki.parse_document!(html)
      assert Floki.attribute(document, "#automation-condition-toggle", "aria-expanded") == ["false"]
      assert Floki.attribute(document, "#automation-actions-toggle", "aria-expanded") == ["true"]
      assert document |> Floki.find("#automation-condition-toggle") |> Floki.text() =~ "25%"

      render_hook(lv, "toggle_create_automation_form_section", %{"section" => "recovery"})
      render_hook(lv, "toggle_create_automation_form_recovery", %{})
      html = render_hook(lv, "toggle_create_automation_form_section", %{"section" => "actions"})

      assert html |> Floki.parse_document!() |> Floki.find("#automation-recovery-toggle") |> Floki.text() =~
               "After 14d without a trigger: Unmark test as flaky."

      render_hook(lv, "update_create_automation_form_name", %{"value" => "Folded automation"})
      render_hook(lv, "save_automation", %{})
      assert [automation] = Automations.list_alerts(project.id)
      assert automation.trigger_config["threshold"] == 25
      assert automation.recovery_enabled

      html = render_hook(lv, "edit_automation", %{"id" => automation.id})

      document = Floki.parse_document!(html)

      for section <- ["condition", "actions", "recovery"] do
        assert Floki.attribute(document, "#automation-#{section}-toggle", "aria-expanded") == ["false"]
      end

      assert document |> Floki.find("#automation-condition-toggle") |> Floki.text() =~ "25%"

      assert document |> Floki.find("#automation-actions-toggle") |> Floki.text() =~
               "For each matching test: Mark test as flaky."

      assert document |> Floki.find("#automation-recovery-toggle") |> Floki.text() =~ "After 14d without a trigger"
    end

    test "applies once on creation and resets the checkbox when editing", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = open(conn, organization, project)
      render_hook(lv, "open_create_automation_modal", %{})
      render_hook(lv, "update_create_automation_form_name", %{"value" => "Recover healthy tests"})
      html = render_hook(lv, "toggle_create_automation_form_apply_existing_matches", %{})
      assert html =~ "Create and apply actions"
      render_hook(lv, "save_automation", %{})

      assert [automation] = Automations.list_alerts(project.id)
      assert automation.trigger_config["apply_actions_to_existing_matches"]

      render_hook(lv, "edit_automation", %{"id" => automation.id})
      html = render(lv)
      assert html =~ "create-automation-apply-existing-matches-checkbox-#{automation.id}"
      assert html =~ ~s(aria-checked="false")
      refute html =~ "Save and apply actions"
      render_hook(lv, "save_automation", %{})
      assert Repo.reload!(automation).baseline_generation == automation.baseline_generation + 1

      render_hook(lv, "edit_automation", %{"id" => automation.id})
      html = render_hook(lv, "toggle_create_automation_form_apply_existing_matches", %{})
      assert html =~ "Save and apply actions"
      render_hook(lv, "save_automation", %{})
      assert Repo.reload!(automation).baseline_generation == automation.baseline_generation + 2

      render_hook(lv, "edit_automation", %{"id" => automation.id})
      render_hook(lv, "update_create_automation_form_threshold", %{"value" => "20"})
      render_hook(lv, "save_automation", %{})
      refute Repo.reload!(automation).trigger_config["apply_actions_to_existing_matches"]
    end

    test "enabling existing-match actions from the form resets a silent baseline", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      automation = AutomationsFixtures.automation_alert_fixture(project: project)
      {:ok, lv, _html} = open(conn, organization, project)
      render_hook(lv, "edit_automation", %{"id" => automation.id})
      render_hook(lv, "toggle_create_automation_form_apply_existing_matches", %{})
      render_hook(lv, "save_automation", %{})

      updated = Repo.reload!(automation)
      assert updated.trigger_config["apply_actions_to_existing_matches"]
      assert updated.baseline_established_at == nil
      assert updated.baseline_generation == automation.baseline_generation + 1
    end

    test "creates an automation through the modal form", %{conn: conn, organization: organization, project: project} do
      {:ok, lv, _html} = open(conn, organization, project)

      render_hook(lv, "open_create_automation_modal", %{})
      render_hook(lv, "update_create_automation_form_name", %{"value" => "Auto-quarantine"})
      render_hook(lv, "save_automation", %{})

      assert [automation] = Automations.list_alerts(project.id)
      refute automation.trigger_config["apply_actions_to_existing_matches"]
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

    test "defaults reliability-rate automations to less-than 90 percent", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = open(conn, organization, project)

      render_hook(lv, "open_create_automation_modal", %{})
      render_hook(lv, "update_create_automation_form_name", %{"value" => "Low reliability"})
      render_hook(lv, "update_create_automation_form_metric", %{"data" => "reliability_rate"})
      render_hook(lv, "save_automation", %{})

      assert [automation] = Automations.list_alerts(project.id)
      assert automation.monitor_type == "reliability_rate"
      assert automation.trigger_config["comparison"] == "lt"
      assert automation.trigger_config["threshold"] == 90.0
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
      render_hook(lv, "update_create_automation_form_rolling_window_size", %{"value" => "1001"})

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
      render_hook(lv, "update_create_automation_form_rolling_window_size", %{"value" => "1001"})
      render_hook(lv, "update_create_automation_form_rolling_window_size", %{"value" => "75"})

      render_hook(lv, "save_automation", %{})
      assert [automation] = Automations.list_alerts(project.id)
      assert automation.trigger_config["rolling_window_size"] == 75
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

    test "persists trigger and recovery state filters", %{conn: conn, organization: organization, project: project} do
      {:ok, lv, _html} = open(conn, organization, project)

      render_hook(lv, "open_create_automation_modal", %{})
      render_hook(lv, "update_create_automation_form_name", %{"value" => "State-aware recovery"})
      render_hook(lv, "toggle_create_automation_form_trigger_state", %{"data" => "enabled"})
      render_hook(lv, "toggle_create_automation_form_recovery", %{})
      render_hook(lv, "toggle_create_automation_form_recovery_state", %{"data" => "muted"})
      render_hook(lv, "save_automation", %{})

      assert [automation] = Automations.list_alerts(project.id)
      assert automation.trigger_config["states"] == ["enabled"]
      assert automation.recovery_config["states"] == ["muted"]
    end

    test "state filters are multi-select", %{conn: conn, organization: organization, project: project} do
      {:ok, lv, _html} = open(conn, organization, project)

      render_hook(lv, "open_create_automation_modal", %{})
      render_hook(lv, "update_create_automation_form_name", %{"value" => "Reliability for live tests"})
      render_hook(lv, "toggle_create_automation_form_trigger_state", %{"data" => "enabled"})
      render_hook(lv, "toggle_create_automation_form_trigger_state", %{"data" => "muted"})
      # Toggling the same state again removes it.
      render_hook(lv, "toggle_create_automation_form_trigger_state", %{"data" => "muted"})
      render_hook(lv, "save_automation", %{})

      assert [automation] = Automations.list_alerts(project.id)
      assert automation.trigger_config["states"] == ["enabled"]
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
      refute html =~ "create-automation-apply-existing-matches-checkbox"
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

    test "requires an event selection before saving a test_updated automation", context do
      {:ok, lv, _html} = open(context.conn, context.organization, context.project)
      render_hook(lv, "open_create_automation_modal", %{})
      render_hook(lv, "update_create_automation_form_metric", %{"data" => "test_updated"})
      render_hook(lv, "update_create_automation_form_name", %{"value" => "State change"})
      render_hook(lv, "add_create_automation_form_trigger_action", %{"data" => "change_state"})
      render_hook(lv, "toggle_create_automation_form_event", %{"data" => "marked_flaky"})
      assert render(lv) =~ ~s(disabled="" type="button" phx-click="save_automation")
      assert render(lv) =~ "Complete a valid condition."
      render_hook(lv, "save_automation", %{})
      assert Automations.list_alerts(context.project.id) == []

      render_hook(lv, "toggle_create_automation_form_event", %{"data" => "marked_flaky"})
      refute render(lv) =~ ~s(disabled="" type="button" phx-click="save_automation")
      render_hook(lv, "save_automation", %{})
      assert [automation] = Automations.list_alerts(context.project.id)
      assert automation.trigger_config["events"] == ["marked_flaky"]
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

    test "can disable an existing automation whose rolling window is now unsupported", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      automation =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          enabled: true,
          trigger_config: %{
            "threshold" => 10,
            "window_type" => "rolling",
            "rolling_window_size" => 75
          }
        )

      automation
      |> Ecto.Changeset.change(
        trigger_config: %{
          "threshold" => 10,
          "window_type" => "rolling",
          "rolling_window_size" => 1001
        }
      )
      |> Repo.update!()

      {:ok, lv, _html} = open(conn, organization, project)
      render_hook(lv, "toggle_automation_enabled", %{"id" => automation.id})

      assert {:ok, %{enabled: false}} = Automations.get_alert(automation.id)
    end

    test "keeps an unsupported legacy automation disabled and explains how to enable it", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      automation =
        AutomationsFixtures.automation_alert_fixture(
          project: project,
          enabled: false,
          trigger_config: %{
            "threshold" => 10,
            "window_type" => "rolling",
            "rolling_window_size" => 75
          }
        )

      automation
      |> Ecto.Changeset.change(
        trigger_config: %{
          "threshold" => 10,
          "window_type" => "rolling",
          "rolling_window_size" => 1001
        }
      )
      |> Repo.update!()

      {:ok, lv, _html} = open(conn, organization, project)
      html = render_hook(lv, "toggle_automation_enabled", %{"id" => automation.id})

      assert html =~ "This automation uses an unsupported trigger configuration. Edit it before enabling it."
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

  describe "branch scope" do
    test "the summary describes reliability as trunk-scoped rather than across branches", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      AutomationsFixtures.automation_alert_fixture(
        project: project,
        monitor_type: "reliability_rate",
        trigger_config: %{"threshold" => 90, "comparison" => "lt", "window_type" => "last_days", "window" => "30d"}
      )

      {:ok, _lv, html} = open(conn, organization, project)

      assert html =~ "on the default branch"
      refute html =~ "across branches"
    end
  end
end
