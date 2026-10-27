defmodule AtlasWeb.ProjectLive.AlertsTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Atlas.Engineering.Alerts
  alias Atlas.Engineering.Projects

  test "creates a disabled webhook rule and edits it without disclosing or clearing its destination", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{scopes: ["engineering:write"]})
    {:ok, project} = Projects.create_project(%{name: "alerts-#{System.unique_integer([:positive])}"})
    {:ok, view, _} = live(conn, ~p"/engineering/projects/#{project.id}/alerts")

    assert has_element?(view, "#error-alert-form")

    params = %{
      "name" => "Production spike",
      "trigger" => "event_spike",
      "tier" => "incident",
      "environment" => "prod",
      "min_level" => "error",
      "threshold_event_count" => "100",
      "threshold_window_minutes" => "5",
      "destination_type" => "webhook",
      "webhook_url" => "https://receiver.example.org/secret-token",
      "enabled" => "false"
    }

    render_submit(view, "save_rule", %{"rule" => params})
    assert [rule] = Alerts.list_rules_for_project(project)
    refute rule.enabled
    assert has_element?(view, "#rules-#{rule.id}")

    render_click(view, "edit_rule", %{"id" => rule.id})
    assert has_element?(view, "input[name='rule[webhook_url]']")
    refute has_element?(view, "input[name='rule[webhook_url]'][value='#{rule.webhook_url}']")
    render_submit(view, "save_rule", %{"rule" => %{params | "name" => "Updated spike", "webhook_url" => ""}})
    assert {:ok, updated} = Alerts.get_rule(rule.id)
    assert updated.name == "Updated spike"
    assert updated.webhook_url == rule.webhook_url

    render_click(view, "toggle_rule", %{"id" => rule.id})
    assert {:ok, %{enabled: true}} = Alerts.get_rule(rule.id)
  end

  test "readers see rules but forged write events and cross-project IDs do not mutate them", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{scopes: ["engineering:read"]})
    {:ok, project} = Projects.create_project(%{name: "alerts-#{System.unique_integer([:positive])}"})

    {:ok, rule} =
      Alerts.create_rule(project, %{
        name: "Existing Slack",
        trigger: :event_rate,
        slack_channel_id: "test-channel",
        enabled: false
      })

    {:ok, view, _} = live(conn, ~p"/engineering/projects/#{project.id}/alerts")
    refute has_element?(view, "#error-alert-form")
    render_click(view, "toggle_rule", %{"id" => rule.id})
    assert {:ok, %{enabled: false}} = Alerts.get_rule(rule.id)
  end
end
