defmodule Atlas.MCP.Tools.ErrorAlertRules do
  @moduledoc false

  alias Atlas.Engineering.Alerts
  alias Atlas.Engineering.Projects
  alias Atlas.MCP.Tool

  def attributes_schema do
    %{
      "type" => "object",
      "additionalProperties" => false,
      "properties" => %{
        "name" => %{"type" => "string"},
        "trigger" => %{"type" => "string", "enum" => ~w(event_spike event_rate regression)},
        "tier" => %{"type" => "string", "enum" => ~w(attention incident)},
        "enabled" => %{"type" => "boolean"},
        "threshold_event_count" => %{"type" => "integer", "minimum" => 1},
        "threshold_window_minutes" => %{"type" => "integer", "minimum" => 1, "maximum" => 60},
        "environment" => %{"type" => "string"},
        "min_level" => %{"type" => "string", "enum" => ~w(debug info warning error fatal)},
        "cooldown_minutes" => %{"type" => "integer", "minimum" => 0},
        "destination_type" => %{"type" => "string", "enum" => ~w(slack webhook)},
        "slack_channel_id" => %{"type" => "string"},
        "slack_mention" => %{"type" => "string", "enum" => ~w(none here channel)},
        "webhook_url" => %{"type" => "string"}
      }
    }
  end

  def validate(module, conn, args, action) do
    with :ok <- Tool.authorize_scope(conn, "engineering:#{action}", "Error alert rules"),
         :ok <- ExJsonSchema.Validator.validate(ExJsonSchema.Schema.resolve(module.input_schema()), args) do
      :ok
    else
      {:error, message} when is_binary(message) -> {:error, message}
      _ -> {:error, "Arguments do not match the error alert rule schema."}
    end
  end

  def project(conn, id), do: Projects.fetch_visible_project(id, Tool.current_user(conn))

  def rule(conn, id) do
    with {:ok, rule} <- Alerts.get_rule(id),
         {:ok, _project} <- project(conn, rule.project_id) do
      {:ok, rule}
    end
  end

  def serialize(rule) do
    fields =
      ~w(id project_id name source trigger tier enabled threshold_event_count threshold_window_minutes min_level environment cooldown_minutes destination_type slack_channel_id slack_mention)a

    rule
    |> Map.take(fields)
    |> Map.put(:webhook_configured, is_binary(rule.webhook_url) and rule.webhook_url != "")
  end
end
