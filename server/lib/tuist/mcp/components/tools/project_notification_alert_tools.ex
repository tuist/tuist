defmodule Tuist.MCP.Components.Tools.ListProjectNotificationAlerts do
  @moduledoc """
  List a project's notification alert rules.
  """

  use Tuist.MCP.Tool,
    name: "list_project_notification_alerts",
    title: "List Project Notification Alerts",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{"type" => "string", "description" => "The account handle."},
        "project_handle" => %{"type" => "string", "description" => "The project handle."}
      },
      "required" => ["account_handle", "project_handle"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "alert_rules" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "string"},
              "name" => %{"type" => "string"},
              "category" => %{"type" => "string"},
              "metric" => %{"type" => "string"},
              "deviation_percentage" => %{"type" => "number"},
              "rolling_window_size" => %{"type" => ["integer", "null"]},
              "git_branch" => %{"type" => ["string", "null"]},
              "scheme" => %{"type" => "string"},
              "bundle_name" => %{"type" => "string"},
              "environment" => %{"type" => "string"},
              "slack_channel_id" => %{"type" => ["string", "null"]},
              "slack_channel_name" => %{"type" => ["string", "null"]},
              "webhook_configured" => %{"type" => "boolean"},
              "inserted_at" => %{"type" => "string"},
              "updated_at" => %{"type" => "string"}
            },
            "required" => [
              "id",
              "name",
              "category",
              "metric",
              "deviation_percentage",
              "rolling_window_size",
              "git_branch",
              "scheme",
              "bundle_name",
              "environment",
              "slack_channel_id",
              "slack_channel_name",
              "webhook_configured",
              "inserted_at",
              "updated_at"
            ],
            "additionalProperties" => false
          }
        }
      },
      "required" => ["alert_rules"],
      "additionalProperties" => false
    }

  alias Tuist.Alerts
  alias Tuist.MCP.Formatter
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description, do: "List a project's notification alert rules. Webhook addresses are never returned."

  @impl EMCP.Tool
  def call(conn, arguments) do
    case MCPTool.resolve_and_authorize_project(arguments, conn.assigns, :update, :project) do
      {:ok, project} ->
        MCPTool.json_response(
          %{alert_rules: Enum.map(Alerts.get_project_alert_rules(project), &serialize/1)},
          __MODULE__
        )

      {:error, message} ->
        EMCP.Tool.error(message)
    end
  end

  defp serialize(alert_rule) do
    %{
      id: alert_rule.id,
      name: alert_rule.name,
      category: to_string(alert_rule.category),
      metric: to_string(alert_rule.metric),
      deviation_percentage: alert_rule.deviation_percentage,
      rolling_window_size: alert_rule.rolling_window_size,
      git_branch: alert_rule.git_branch,
      scheme: alert_rule.scheme,
      bundle_name: alert_rule.bundle_name,
      environment: to_string(alert_rule.environment),
      slack_channel_id: alert_rule.slack_channel_id,
      slack_channel_name: alert_rule.slack_channel_name,
      webhook_configured: is_binary(alert_rule.slack_webhook_url) and alert_rule.slack_webhook_url != "",
      inserted_at: Formatter.iso8601(alert_rule.inserted_at),
      updated_at: Formatter.iso8601(alert_rule.updated_at)
    }
  end
end
