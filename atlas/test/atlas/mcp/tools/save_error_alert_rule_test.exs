defmodule Atlas.MCP.Tools.SaveErrorAlertRuleTest do
  use Atlas.MCP.ToolCase
  use Mimic

  alias Atlas.Audit.Activity
  alias Atlas.Engineering.Alerts
  alias Atlas.Engineering.Alerts.Notification
  alias Atlas.Engineering.Errors
  alias Atlas.Engineering.Projects
  alias Atlas.MCP.Server
  alias Atlas.MCP.Tools.DeleteErrorAlertRule
  alias Atlas.MCP.Tools.ListErrorAlertRules
  alias Atlas.MCP.Tools.PreviewErrorAlertRule
  alias Atlas.MCP.Tools.SaveErrorAlertRule
  alias Atlas.Repo

  test "operators can create disabled rules, preview without notifying, enable, and delete them without exposing secrets" do
    conn = mcp_conn(insert_user!(%{scopes: ["engineering:write"]}))
    {:ok, project} = Projects.create_project(%{name: "alerts-#{System.unique_integer([:positive])}"})

    args = %{"project_id" => project.id, "attributes" => attrs()}
    assert {:ok, %{"rule" => saved}} = execute_tool(SaveErrorAlertRule, conn, args)
    assert saved.enabled == false
    refute Map.has_key?(saved, :webhook_url)
    refute Map.has_key?(saved, :webhook_signing_secret)
    assert saved.webhook_configured

    assert {:ok, %{"rules" => [^saved]}} = execute_tool(ListErrorAlertRules, conn, %{"project_id" => project.id})
    stub(Errors, :enabled?, fn -> true end)
    stub(Alerts, :spike_matches, fn _, _ -> {:ok, [%{issue_id: Ecto.UUID.generate(), event_count: 105}]} end)

    assert {:ok, %{"matches" => [%{event_count: 105}]}} =
             execute_tool(PreviewErrorAlertRule, conn, %{"id" => saved.id, "at" => "2026-10-27T08:20:00Z"})

    assert Repo.aggregate(Notification, :count) == 0
    assert Repo.aggregate(Oban.Job, :count) == 0

    assert {:ok, %{"rule" => %{enabled: true}}} =
             execute_tool(SaveErrorAlertRule, conn, %{
               "project_id" => project.id,
               "id" => saved.id,
               "attributes" => %{"enabled" => true}
             })

    assert {:ok, %{"deleted" => true}} = execute_tool(DeleteErrorAlertRule, conn, %{"id" => saved.id})
    assert {:ok, %{"rules" => []}} = execute_tool(ListErrorAlertRules, conn, %{"project_id" => project.id})
  end

  test "readers cannot mutate rules through direct calls, dispatch, or discovery" do
    user = insert_user!(%{scopes: ["engineering:read"]})
    conn = mcp_conn(user)
    {:ok, project} = Projects.create_project(%{name: "alerts-#{System.unique_integer([:positive])}"})
    assert {:error, _} = execute_tool(SaveErrorAlertRule, conn, %{"project_id" => project.id, "attributes" => attrs()})
    assert Alerts.list_rules_for_project(project) == []

    listed = Server.handle_message(conn, %{"jsonrpc" => "2.0", "method" => "tools/list", "id" => 1})
    names = Enum.map(listed["result"]["tools"], & &1["name"])
    assert "list_error_alert_rules" in names
    refute "save_error_alert_rule" in names
    refute "delete_error_alert_rule" in names

    denied =
      Server.handle_message(conn, %{
        "jsonrpc" => "2.0",
        "method" => "tools/call",
        "id" => 2,
        "params" => %{
          "name" => "save_error_alert_rule",
          "arguments" => %{"project_id" => project.id, "attributes" => attrs()}
        }
      })

    assert denied["error"] || denied["result"]["isError"]
  end

  test "successful and malformed save calls omit all credentials from tool audits" do
    conn = mcp_conn(insert_user!(%{scopes: ["engineering:write"]}))
    {:ok, project} = Projects.create_project(%{name: "alerts-#{System.unique_integer([:positive])}"})
    valid = %{"project_id" => project.id, "attributes" => attrs()}

    for args <- [valid, Map.put(valid, "webhook_url", "https://receiver.example.org/outer-secret")] do
      Server.handle_message(conn, %{
        "jsonrpc" => "2.0",
        "method" => "tools/call",
        "id" => 1,
        "params" => %{"name" => "save_error_alert_rule", "arguments" => args}
      })
    end

    calls = Repo.all(from(activity in Activity, where: activity.action == "mcp.tool_called"))
    assert length(calls) == 2
    assert Enum.sort(Enum.map(calls, & &1.metadata["status"])) == ["error", "ok"]
    assert Enum.all?(calls, &(&1.metadata["arguments"] == %{}))
    refute inspect(Repo.all(Activity)) =~ "private-token"
    refute inspect(Repo.all(Activity)) =~ "outer-secret"
  end

  test "window, environment and level are mandatory and rules cannot be moved across projects" do
    conn = mcp_conn(insert_user!(%{scopes: ["engineering:write"]}))
    {:ok, project} = Projects.create_project(%{name: "alerts-#{System.unique_integer([:positive])}"})

    for invalid <- [
          Map.delete(attrs(), "environment"),
          Map.delete(attrs(), "min_level"),
          Map.delete(attrs(), "threshold_window_minutes"),
          Map.put(attrs(), "threshold_window_minutes", 61)
        ] do
      assert {:error, _} =
               execute_tool(SaveErrorAlertRule, conn, %{"project_id" => project.id, "attributes" => invalid})
    end

    assert {:ok, %{"rule" => saved}} =
             execute_tool(SaveErrorAlertRule, conn, %{"project_id" => project.id, "attributes" => attrs()})

    {:ok, other} = Projects.create_project(%{name: "other-#{System.unique_integer([:positive])}"})

    assert {:error, _} =
             execute_tool(SaveErrorAlertRule, conn, %{
               "project_id" => other.id,
               "id" => saved.id,
               "attributes" => %{"enabled" => true}
             })

    assert {:ok, %{enabled: false, project_id: project_id}} = Alerts.get_rule(saved.id)
    assert project_id == project.id
  end

  defp attrs do
    %{
      "name" => "Production error spike",
      "trigger" => "event_spike",
      "tier" => "incident",
      "environment" => "prod",
      "min_level" => "error",
      "threshold_event_count" => 100,
      "threshold_window_minutes" => 5,
      "cooldown_minutes" => 60,
      "destination_type" => "webhook",
      "webhook_url" => "https://receiver.example.org/private-token"
    }
  end
end
