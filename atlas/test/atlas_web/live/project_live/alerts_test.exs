defmodule AtlasWeb.ProjectLive.AlertsTest do
  use AtlasWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Atlas.Engineering.Alerts
  alias Atlas.Engineering.Projects

  test "creates a disabled webhook rule and edits it without disclosing or clearing its destination", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{scopes: ["engineering:write"]})
    {:ok, project} = Projects.create_project(%{name: "alerts-#{System.unique_integer([:positive])}"})
    {:ok, view, _} = live(conn, ~p"/engineering/projects/#{project.id}")

    assert has_element?(view, "#project-show #project-alerts")
    view |> element("#add-error-alert-rule") |> render_click()
    assert_push_event(view, "open-modal", %{id: "error-alert-modal"})
    assert has_element?(view, "#error-alert-modal")

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

    render_hook(view, "save_rule", %{"rule" => params})
    assert_push_event(view, "close-modal", %{id: "error-alert-modal"})
    assert [rule] = Alerts.list_rules_for_project(project)
    refute rule.enabled
    assert has_element?(view, "#rules-#{rule.id}")

    view |> element("#rules-#{rule.id} button[phx-click='edit_rule']") |> render_click()
    assert_push_event(view, "open-modal", %{id: "error-alert-modal"})
    assert rule_field_value(view, "webhook_url") == ""
    render_hook(view, "save_rule", %{"rule" => %{params | "name" => "Updated spike", "webhook_url" => ""}})
    assert {:ok, updated} = Alerts.get_rule(rule.id)
    assert updated.name == "Updated spike"
    assert updated.webhook_url == rule.webhook_url

    render_click(view, "toggle_rule", %{"id" => rule.id})
    assert {:ok, %{enabled: true}} = Alerts.get_rule(rule.id)
  end

  test "readers see project rules but cannot manage them", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{scopes: ["engineering:read"]})
    {:ok, project} = Projects.create_project(%{name: "alerts-#{System.unique_integer([:positive])}"})

    {:ok, rule} =
      Alerts.create_rule(project, %{
        name: "Existing Slack",
        trigger: :event_rate,
        slack_channel_id: "test-channel",
        enabled: false
      })

    {:ok, view, _} = live(conn, ~p"/engineering/projects/#{project.id}")
    assert has_element?(view, "#rules-#{rule.id}")
    refute has_element?(view, "#add-error-alert-rule")
    refute has_element?(view, "#error-alert-modal")
    render_click(view, "toggle_rule", %{"id" => rule.id})
    assert {:ok, %{enabled: false}} = Alerts.get_rule(rule.id)
  end

  test "invalid drafts stay editable and dismissing the modal discards them", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{scopes: ["engineering:write"]})
    {:ok, project} = Projects.create_project(%{name: "alerts-#{System.unique_integer([:positive])}"})
    {:ok, view, _} = live(conn, ~p"/engineering/projects/#{project.id}")

    view |> element("#add-error-alert-rule") |> render_click()
    render_hook(view, "save_rule", %{"rule" => %{"name" => "Unfinished draft", "threshold_window_minutes" => "61"}})
    assert Alerts.list_rules_for_project(project) == []
    assert rule_field_value(view, "name") == "Unfinished draft"

    render_hook(view, "rule_modal_open_change", %{"open" => false})
    view |> element("#add-error-alert-rule") |> render_click()
    assert rule_field_value(view, "name") == ""
    assert rule_field_value(view, "threshold_window_minutes") == "5"
    assert Alerts.list_rules_for_project(project) == []
  end

  test "writers cannot edit, enable or preview another project's rules", %{conn: conn} do
    {conn, _user} = log_in_user(conn, %{scopes: ["engineering:write"]})
    {:ok, project} = Projects.create_project(%{name: "alerts-#{System.unique_integer([:positive])}"})
    {:ok, other} = Projects.create_project(%{name: "other-#{System.unique_integer([:positive])}"})

    {:ok, rule} =
      Alerts.create_rule(other, %{
        name: "Another project",
        trigger: :event_spike,
        environment: "prod",
        min_level: :error,
        threshold_event_count: 100,
        threshold_window_minutes: 5,
        slack_channel_id: "test-channel",
        enabled: false
      })

    {:ok, view, _} = live(conn, ~p"/engineering/projects/#{project.id}")
    render_click(view, "edit_rule", %{"id" => rule.id})
    assert rule_field_value(view, "name") == ""
    render_click(view, "toggle_rule", %{"id" => rule.id})
    render_click(view, "select_preview", %{"id" => rule.id})
    refute has_element?(view, "#error-alert-preview")
    assert {:ok, %{enabled: false}} = Alerts.get_rule(rule.id)
  end

  defp rule_field_value(view, field) do
    [{"template", _, children}] =
      view |> element("#error-alert-modal-portal") |> render() |> LazyHTML.from_fragment() |> LazyHTML.to_tree()

    inputs = children |> LazyHTML.from_tree() |> LazyHTML.query("input[name='rule[#{field}]']")
    assert Enum.count(inputs) == 1
    inputs |> LazyHTML.attribute("value") |> List.first() || ""
  end
end
