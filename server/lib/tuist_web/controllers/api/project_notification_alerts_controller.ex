defmodule TuistWeb.API.ProjectNotificationAlertsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Alerts
  alias TuistWeb.API.Responses
  alias TuistWeb.API.Schemas.Error

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, {:project, :project, :update})

  tags ["Project Notification Alerts"]

  @alert_rule_schema %Schema{
    title: "ProjectNotificationAlert",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      name: %Schema{type: :string},
      category: %Schema{type: :string},
      metric: %Schema{type: :string},
      deviation_percentage: %Schema{type: :number},
      rolling_window_size: %Schema{type: :integer, nullable: true},
      git_branch: %Schema{type: :string, nullable: true},
      scheme: %Schema{type: :string},
      bundle_name: %Schema{type: :string},
      environment: %Schema{type: :string},
      slack_channel_id: %Schema{type: :string, nullable: true},
      slack_channel_name: %Schema{type: :string, nullable: true},
      webhook_configured: %Schema{type: :boolean},
      inserted_at: %Schema{type: :string, format: "date-time"},
      updated_at: %Schema{type: :string, format: "date-time"}
    },
    required: [
      :id,
      :name,
      :category,
      :metric,
      :deviation_percentage,
      :rolling_window_size,
      :git_branch,
      :scheme,
      :bundle_name,
      :environment,
      :slack_channel_id,
      :slack_channel_name,
      :webhook_configured,
      :inserted_at,
      :updated_at
    ]
  }

  operation(:index,
    summary: "List a project's notification alert rules.",
    operation_id: "listProjectNotificationAlerts",
    parameters: [
      account_handle: [in: :path, type: :string, required: true, description: "The handle of the account."],
      project_handle: [in: :path, type: :string, required: true, description: "The handle of the project."]
    ],
    responses: %{
      ok:
        {"Project notification alert rules", "application/json",
         %Schema{
           type: :object,
           properties: %{alert_rules: %Schema{type: :array, items: @alert_rule_schema}},
           required: [:alert_rules]
         }},
      forbidden: {"Forbidden", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def index(%{assigns: %{selected_project: project}} = conn, _params) do
    json(conn, %{alert_rules: Enum.map(Alerts.get_project_alert_rules(project), &serialize/1)})
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
      inserted_at: alert_rule.inserted_at,
      updated_at: alert_rule.updated_at
    }
  end
end
