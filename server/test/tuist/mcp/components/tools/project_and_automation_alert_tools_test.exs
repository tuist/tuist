defmodule Tuist.MCP.Components.Tools.ProjectAndAutomationAlertToolsTest do
  use TuistTestSupport.Cases.ConnCase, async: true
  use Mimic

  alias Tuist.Automations
  alias Tuist.Automations.Alerts.Revision
  alias Tuist.MCP.Components.Tools.GetAutomationAlert
  alias Tuist.MCP.Components.Tools.GetProject
  alias Tuist.MCP.Components.Tools.ListAutomationAlerts
  alias Tuist.Projects

  describe "get_project" do
    test "returns dashboard configuration" do
      account = %{id: 1, name: "acme"}

      project = %{
        id: 2,
        account: account,
        name: "app",
        default_branch: "main",
        visibility: :private,
        build_system: :xcode
      }

      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" -> project end)
      stub(Tuist.Authorization, :authorize, fn :project_read, :subject, ^project -> :ok end)
      stub(Projects, :get_repository_url, fn ^project -> "https://github.com/acme/app" end)

      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{"content" => [%{"type" => "text", "text" => text}]} =
               GetProject.call(conn, %{"account_handle" => "acme", "project_handle" => "app"})

      assert JSON.decode!(text) == %{
               "build_system" => "xcode",
               "default_branch" => "main",
               "full_handle" => "acme/app",
               "id" => 2,
               "repository_url" => "https://github.com/acme/app",
               "visibility" => "private"
             }
    end
  end

  describe "list_automation_alerts" do
    test "returns alerts for the authorized project" do
      project = %{id: 1, name: "app"}
      alert = alert_fixture(project.id)

      stub(Projects, :get_project_by_account_and_project_handles, fn "acme", "app" -> project end)
      stub(Tuist.Authorization, :authorize, fn :automation_alert_read, :subject, ^project -> :ok end)
      stub(Automations, :list_alerts, fn 1 -> [alert] end)

      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{"content" => [%{"type" => "text", "text" => text}]} =
               ListAutomationAlerts.call(conn, %{"account_handle" => "acme", "project_handle" => "app"})

      assert %{"alerts" => [%{"id" => "alert-1", "name" => "Flaky test detection"}]} = JSON.decode!(text)

      refute get_in(JSON.decode!(text), ["alerts", Access.at(0), "trigger_actions", Access.at(1), "webhook_url_encrypted"])
    end
  end

  describe "get_automation_alert" do
    test "returns an authorized alert" do
      project = %{id: 1, name: "app"}
      alert = alert_fixture(project.id)

      stub(Automations, :get_alert, fn "alert-1" -> {:ok, alert} end)
      stub(Projects, :get_project_by_id, fn 1 -> project end)
      stub(Tuist.Authorization, :authorize, fn :automation_alert_read, :subject, ^project -> :ok end)

      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{"content" => [%{"type" => "text", "text" => text}]} =
               GetAutomationAlert.call(conn, %{"alert_id" => "alert-1"})

      assert %{"id" => "alert-1", "monitor_type" => "flaky_run_count"} = JSON.decode!(text)
    end

    test "accepts a dashboard URL" do
      project = %{id: 1, name: "app"}
      alert = alert_fixture(project.id)

      stub(Automations, :get_alert, fn "alert-1" -> {:ok, alert} end)
      stub(Projects, :get_project_by_id, fn 1 -> project end)
      stub(Tuist.Authorization, :authorize, fn :automation_alert_read, :subject, ^project -> :ok end)

      conn = %Plug.Conn{assigns: %{current_subject: :subject}}

      assert %{"content" => [%{"type" => "text", "text" => text}]} =
               GetAutomationAlert.call(conn, %{
                 "alert_id" => "https://tuist.dev/acme/app/settings/automations/alert-1"
               })

      assert JSON.decode!(text)["id"] == "alert-1"
    end
  end

  describe "automation revision redaction" do
    test "removes encrypted webhook fields from snapshots and changes" do
      revision = %Revision{
        id: "revision-1",
        event: "updated",
        source: "dashboard",
        actor: %{id: 1, email: "user@example.com", account: %{name: "user"}},
        snapshot: %{
          "trigger_actions" => [%{"type" => "send_slack", "webhook_url_encrypted" => "ciphertext"}]
        },
        changes: %{
          "recovery_actions" => %{
            "from" => [%{"type" => "send_slack", "webhook_url_encrypted" => "old"}],
            "to" => [%{"type" => "send_slack", "webhook_url_encrypted" => "new"}]
          }
        },
        inserted_at: ~U[2026-08-28 10:00:00Z]
      }

      redacted = Automations.redact_revision(revision)

      refute get_in(redacted, [:snapshot, "trigger_actions", Access.at(0), "webhook_url_encrypted"])
      refute get_in(redacted, [:changes, "recovery_actions", "from", Access.at(0), "webhook_url_encrypted"])
      refute get_in(redacted, [:changes, "recovery_actions", "to", Access.at(0), "webhook_url_encrypted"])
    end
  end

  defp alert_fixture(project_id) do
    %{
      id: "alert-1",
      project_id: project_id,
      name: "Flaky test detection",
      enabled: true,
      monitor_type: "flaky_run_count",
      trigger_config: %{"threshold" => 3},
      cadence: "5m",
      trigger_actions: [
        %{"type" => "add_label", "label" => "flaky"},
        %{"type" => "send_slack", "channel" => "C123", "message" => "Alert", "webhook_url_encrypted" => "ciphertext"}
      ],
      recovery_enabled: true,
      recovery_config: %{"window" => "14d"},
      recovery_actions: [%{"type" => "remove_label", "label" => "flaky"}]
    }
  end
end
