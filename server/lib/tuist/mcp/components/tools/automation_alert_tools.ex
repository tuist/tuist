defmodule Tuist.MCP.Components.Tools.AutomationAlertTools do
  @moduledoc false

  alias Tuist.Automations
  alias Tuist.MCP.Formatter

  def alert_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "name" => %{"type" => "string"},
        "enabled" => %{"type" => "boolean"},
        "monitor_type" => %{"type" => "string"},
        "trigger_config" => %{"type" => "object"},
        "cadence" => %{"type" => "string"},
        "trigger_actions" => %{"type" => "array", "items" => %{"type" => "object"}},
        "recovery_enabled" => %{"type" => "boolean"},
        "recovery_config" => %{"type" => "object"},
        "recovery_actions" => %{"type" => "array", "items" => %{"type" => "object"}}
      },
      "required" => [
        "id",
        "name",
        "enabled",
        "monitor_type",
        "trigger_config",
        "cadence",
        "trigger_actions",
        "recovery_enabled",
        "recovery_config",
        "recovery_actions"
      ],
      "additionalProperties" => false
    }
  end

  def serialize(alert) do
    %{
      id: alert.id,
      name: alert.name,
      enabled: alert.enabled,
      monitor_type: alert.monitor_type,
      trigger_config: alert.trigger_config,
      cadence: alert.cadence,
      trigger_actions: Enum.map(alert.trigger_actions, &Automations.redact_action/1),
      recovery_enabled: alert.recovery_enabled,
      recovery_config: alert.recovery_config,
      recovery_actions: Enum.map(alert.recovery_actions, &Automations.redact_action/1)
    }
  end

  def revision_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "event" => %{"type" => "string", "enum" => ["created", "updated"]},
        "source" => %{"type" => "string"},
        "actor" => %{
          "type" => ["object", "null"],
          "properties" => %{
            "id" => %{"type" => "integer"},
            "name" => %{"type" => "string"},
            "email" => %{"type" => "string"}
          },
          "required" => ["id", "name", "email"],
          "additionalProperties" => false
        },
        "changes" => %{"type" => "object"},
        "snapshot" => %{"type" => "object"},
        "inserted_at" => %{"type" => "string"}
      },
      "required" => ["id", "event", "source", "actor", "changes", "snapshot", "inserted_at"],
      "additionalProperties" => false
    }
  end

  def serialize_revision(revision) do
    revision
    |> Automations.redact_revision()
    |> Map.update!(:inserted_at, &Formatter.iso8601/1)
  end
end

defmodule Tuist.MCP.Components.Tools.ListAutomationAlerts do
  @moduledoc """
  List automation alerts for a project.
  """

  use Tuist.MCP.Tool,
    name: "list_automation_alerts",
    title: "List Automation Alerts",
    read_only_hint: true,
    authorize: [action: :read, category: :automation_alert],
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => %{
          "type" => "string",
          "description" => "The account handle (organization or user)."
        },
        "project_handle" => %{
          "type" => "string",
          "description" => "The project handle."
        }
      },
      "required" => ["account_handle", "project_handle"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "alerts" => %{
          "type" => "array",
          "items" => Tuist.MCP.Components.Tools.AutomationAlertTools.alert_schema()
        }
      },
      "required" => ["alerts"],
      "additionalProperties" => false
    }

  alias Tuist.Automations
  alias Tuist.MCP.Components.Tools.AutomationAlertTools

  @impl EMCP.Tool
  def description,
    do:
      "List automation alerts for a project. The account_handle and project_handle can be extracted from a Tuist dashboard URL: #{Tuist.Environment.app_url()}/{account_handle}/{project_handle}."

  def execute(_conn, _args, project) do
    {:ok,
     %{
       alerts:
         project.id
         |> Automations.list_alerts()
         |> Enum.map(&AutomationAlertTools.serialize/1)
     }}
  end
end

defmodule Tuist.MCP.Components.Tools.GetAutomationAlert do
  @moduledoc """
  Get an automation alert.
  """

  use Tuist.MCP.Tool,
    name: "get_automation_alert",
    title: "Get Automation Alert",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "alert_id" => %{
          "type" => "string",
          "description" => "The alert ID, or a Tuist dashboard URL."
        }
      },
      "required" => ["alert_id"],
      "additionalProperties" => false
    },
    output_schema: Tuist.MCP.Components.Tools.AutomationAlertTools.alert_schema()

  alias Tuist.Automations
  alias Tuist.MCP.Components.Tools.AutomationAlertTools
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description,
    do:
      "Get an automation alert. The alert_id can also be a Tuist dashboard URL, e.g. #{Tuist.Environment.app_url()}/{account}/{project}/settings/automations/{id}."

  @impl EMCP.Tool
  def call(conn, %{"alert_id" => alert_id}) do
    alert_id = MCPTool.resource_id(alert_id)

    case MCPTool.load_and_authorize(
           Automations.get_alert(alert_id),
           conn.assigns,
           :read,
           :automation_alert,
           "Automation alert not found: #{alert_id}"
         ) do
      {:ok, alert, _project} -> MCPTool.json_response(AutomationAlertTools.serialize(alert), __MODULE__)
      {:error, message} -> EMCP.Tool.error(message)
    end
  end
end

defmodule Tuist.MCP.Components.Tools.ListAutomationAlertRevisions do
  @moduledoc """
  List an automation alert's revision history.
  """

  use Tuist.MCP.Tool,
    name: "list_automation_alert_revisions",
    title: "List Automation Alert Revisions",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "alert_id" => %{"type" => "string", "description" => "The alert ID, or a Tuist dashboard URL."},
        "before" => %{"type" => "string", "description" => "The revision ID to continue before."},
        "page_size" => %{"type" => "integer", "description" => "Results per page, up to 100."}
      },
      "required" => ["alert_id"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "revisions" => %{
          "type" => "array",
          "items" => Tuist.MCP.Components.Tools.AutomationAlertTools.revision_schema()
        },
        "next_before" => %{"type" => ["string", "null"]}
      },
      "required" => ["revisions", "next_before"],
      "additionalProperties" => false
    }

  alias Tuist.Automations
  alias Tuist.MCP.Components.Tools.AutomationAlertTools
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description, do: "List an automation alert's revision history."

  @impl EMCP.Tool
  def call(conn, %{"alert_id" => alert_id} = arguments) do
    alert_id = MCPTool.resource_id(alert_id)

    with {:ok, alert, _project} <-
           MCPTool.load_and_authorize(
             Automations.get_alert(alert_id),
             conn.assigns,
             :read,
             :automation_alert,
             "Automation alert not found: #{alert_id}"
           ),
         {:ok, before} <- revision_cursor(alert.id, Map.get(arguments, "before")) do
      page_size = arguments |> Map.get("page_size", 20) |> max(1) |> min(100)
      revisions = Automations.list_alert_revisions(alert.id, before: before, limit: page_size + 1)
      {page, remaining} = Enum.split(revisions, page_size)

      MCPTool.json_response(
        %{
          revisions: Enum.map(page, &AutomationAlertTools.serialize_revision/1),
          next_before: if(remaining == [], do: nil, else: List.last(page).id)
        },
        __MODULE__
      )
    else
      {:error, :not_found} -> EMCP.Tool.error("Automation alert revision not found.")
      {:error, message} -> EMCP.Tool.error(message)
    end
  end

  def call(_conn, _arguments), do: EMCP.Tool.error("Provide alert_id.")

  defp revision_cursor(_alert_id, nil), do: {:ok, nil}
  defp revision_cursor(alert_id, revision_id), do: Automations.get_alert_revision(alert_id, revision_id)
end
