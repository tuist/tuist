defmodule TuistWeb.ProjectAutomationsLiveTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use TuistTestSupport.Cases.LiveCase
  use TuistTestSupport.Cases.StubCase, dashboard_project: true
  use Mimic

  import Phoenix.LiveViewTest

  alias Tuist.Projects
  alias Tuist.Repo

  describe "page rendering" do
    test "renders the project automations page", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, _lv, html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/automations")

      assert html =~ "Automations"
      assert html =~ "Flaky test detection"
      assert html =~ "Test quarantine"
    end

    test "shows correct default values for new project", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, _lv, html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/automations")

      # Default values: auto_mark_flaky_tests=true, auto_mark_flaky_threshold=1, auto_quarantine_flaky_tests=true
      assert html =~ "Auto-mark tests as flaky"
      assert html =~ "Auto-quarantine flaky tests"
      assert html =~ ~s|value="1"|
    end
  end

  describe "auto-mark flaky tests" do
    test "toggles auto-mark flaky setting", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/automations")

      assert project.auto_mark_flaky_tests

      _html = lv |> element(~s|#auto-mark-flaky-toggle|) |> render_click()

      updated_project = Projects.get_project_by_id(project.id)
      refute updated_project.auto_mark_flaky_tests
    end

    test "updates auto-mark flaky threshold", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/automations")

      assert project.auto_mark_flaky_threshold == 1

      lv
      |> element(~s|#auto-mark-flaky-threshold|)
      |> render_keyup(%{"value" => "5"})

      updated_project = Projects.get_project_by_id(project.id)
      assert updated_project.auto_mark_flaky_threshold == 5
    end

    test "ignores invalid threshold values", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/automations")

      assert project.auto_mark_flaky_threshold == 1

      lv
      |> element(~s|#auto-mark-flaky-threshold|)
      |> render_keyup(%{"value" => "invalid"})

      updated_project = Projects.get_project_by_id(project.id)
      assert updated_project.auto_mark_flaky_threshold == 1
    end

    test "ignores zero or negative threshold values", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/automations")

      lv
      |> element(~s|#auto-mark-flaky-threshold|)
      |> render_keyup(%{"value" => "0"})

      updated_project = Projects.get_project_by_id(project.id)
      assert updated_project.auto_mark_flaky_threshold == 1

      lv
      |> element(~s|#auto-mark-flaky-threshold|)
      |> render_keyup(%{"value" => "-1"})

      updated_project = Projects.get_project_by_id(project.id)
      assert updated_project.auto_mark_flaky_threshold == 1
    end
  end

  describe "auto-quarantine" do
    test "toggles auto-quarantine setting", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/automations")

      assert project.auto_quarantine_flaky_tests

      _html = lv |> element(~s|#auto-quarantine-toggle|) |> render_click()

      updated_project = Projects.get_project_by_id(project.id)
      refute updated_project.auto_quarantine_flaky_tests
    end

    test "can toggle auto-quarantine back on", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, _} = Projects.update_project(project, %{auto_quarantine_flaky_tests: false})

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/automations")

      _html = lv |> element(~s|#auto-quarantine-toggle|) |> render_click()

      updated_project = Projects.get_project_by_id(project.id)
      assert updated_project.auto_quarantine_flaky_tests
    end
  end

  describe "flaky alerts" do
    test "toggles flaky alerts when channel is configured", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      account = Repo.preload(organization.account, [:slack_installation])

      {:ok, _installation} =
        Tuist.Slack.create_installation(%{
          account_id: account.id,
          team_id: "T123",
          team_name: "Test Team",
          access_token: "xoxb-test-token",
          bot_user_id: "U123"
        })

      {:ok, _} =
        Projects.update_project(project, %{
          flaky_test_alerts_slack_channel_id: "C123",
          flaky_test_alerts_slack_channel_name: "alerts"
        })

      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/automations")

      refute project.flaky_test_alerts_enabled

      _html = lv |> element(~s|#flaky-alerts-toggle|) |> render_click()

      updated_project = Projects.get_project_by_id(project.id)
      assert updated_project.flaky_test_alerts_enabled
    end

    test "handles flaky_alert_channel_selected event", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, lv, _html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/automations")

      render_hook(lv, "flaky_alert_channel_selected", %{"channel_id" => "C456", "channel_name" => "new-alerts"})

      updated_project = Projects.get_project_by_id(project.id)
      assert updated_project.flaky_test_alerts_slack_channel_id == "C456"
      assert updated_project.flaky_test_alerts_slack_channel_name == "new-alerts"
      assert updated_project.flaky_test_alerts_enabled
    end

    test "shows connect slack button when no slack installation", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      {:ok, _lv, html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/automations")

      assert html =~ "Connect Slack"
    end

    test "shows channel tag when channel is configured", %{
      conn: conn,
      organization: organization,
      project: project
    } do
      account = Repo.preload(organization.account, [:slack_installation])

      {:ok, _installation} =
        Tuist.Slack.create_installation(%{
          account_id: account.id,
          team_id: "T123",
          team_name: "Test Team",
          access_token: "xoxb-test-token",
          bot_user_id: "U123"
        })

      {:ok, _} =
        Projects.update_project(project, %{
          flaky_test_alerts_slack_channel_id: "C123",
          flaky_test_alerts_slack_channel_name: "my-channel"
        })

      {:ok, _lv, html} = live(conn, ~p"/#{organization.account.name}/#{project.name}/settings/automations")

      assert html =~ "#my-channel"
    end
  end
end
