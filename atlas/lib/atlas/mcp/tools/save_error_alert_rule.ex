defmodule Atlas.MCP.Tools.SaveErrorAlertRule do
  @moduledoc "Creates a disabled error alert rule or updates an existing rule."

  use Atlas.MCP.Tool,
    name: "save_error_alert_rule",
    schema: %{
      "type" => "object",
      "required" => ["project_id", "attributes"],
      "properties" => %{
        "project_id" => %{"type" => "string", "format" => "uuid"},
        "id" => %{"type" => "string", "format" => "uuid"},
        "attributes" => Atlas.MCP.Tools.ErrorAlertRules.attributes_schema()
      },
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "required" => ["rule"],
      "properties" => %{"rule" => %{"type" => "object"}},
      "additionalProperties" => false
    }

  alias Atlas.Engineering.Alerts
  alias Atlas.MCP.Tool
  alias Atlas.MCP.Tools.ErrorAlertRules

  @impl EMCP.Tool
  def description do
    "Create or update an error alert rule. Requires engineering:write. New rules default to disabled; " <>
      "preview historical windows before explicitly enabling. event_spike needs a count, window (1–60 minutes), " <>
      "exact environment and minimum level. event_rate is cumulative, not windowed. " <>
      "The incident tier is metadata: the webhook receiver must route it to an incident-declaration escalation chain."
  end

  def execute(conn, args) do
    with :ok <- ErrorAlertRules.validate(__MODULE__, conn, args, "write"),
         {:ok, project} <- ErrorAlertRules.project(conn, args["project_id"]),
         {:ok, rule} <- save(conn, project, args) do
      {:ok, %{"rule" => ErrorAlertRules.serialize(rule)}}
    else
      {:error, :not_found} -> {:error, "Project or alert rule not found."}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, Tool.format_changeset_errors(changeset)}
      error -> error
    end
  end

  defp save(conn, project, %{"id" => id, "attributes" => attrs}) do
    case ErrorAlertRules.rule(conn, id) do
      {:ok, %{project_id: project_id} = rule} when project_id == project.id -> Alerts.update_rule(rule, attrs)
      _ -> {:error, :not_found}
    end
  end

  defp save(_conn, project, %{"attributes" => attrs}),
    do: Alerts.create_rule(project, Map.put_new(attrs, "enabled", false))
end
