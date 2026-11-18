defmodule Tuist.MCP.Components.Tools.NotificationRuleTools do
  @moduledoc """
  Shared helpers for the tools that manage the authenticated user's own
  notification rules (`Tuist.Notifications`). They act only for a user. Rules
  span every account the user belongs to, so they aren't offered to dashboard
  pages (WebMCP), whose tools must stay within the page's account.
  """

  alias Tuist.Accounts.User
  alias Tuist.Notifications

  def rule_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "string"},
        "event" => %{"type" => "string"},
        "enabled" => %{"type" => "boolean"},
        "projects" => %{"type" => "array", "items" => %{"type" => "string"}},
        "conditions" => %{"type" => "object"},
        "actions" => %{"type" => "array", "items" => %{"type" => "object"}},
        "inserted_at" => %{"type" => "string"},
        "updated_at" => %{"type" => "string"}
      },
      "required" => ["id", "event", "enabled", "projects", "conditions", "actions", "inserted_at", "updated_at"],
      "additionalProperties" => false
    }
  end

  def rule_properties do
    %{
      "enabled" => %{"type" => "boolean", "description" => "Whether the rule notifies. Defaults to true."},
      "projects" => %{
        "type" => "array",
        "items" => %{"type" => "string"},
        "description" =>
          "account/project handles the rule covers. Empty covers every project the user can get the event's notifications for, including later ones."
      },
      "conditions" => %{
        "type" => "object",
        "description" =>
          "Filters on the event, in the shape of the event's conditions_schema from list_notification_events."
      },
      "actions" => %{
        "type" => "array",
        "minItems" => 1,
        "items" => %{
          "type" => "object",
          "properties" => %{"type" => %{"type" => "string", "enum" => Map.keys(Notifications.action_types())}},
          "required" => ["type"]
        },
        "description" => "What the rule does when it matches. push notifies the user's Tuist app devices."
      }
    }
  end

  def user(%{assigns: assigns}) do
    case assigns do
      %{mcp_account_scope: scope} when not is_nil(scope) ->
        {:error, "Notification rules aren't available on the dashboard."}

      %{current_user: %User{} = user} ->
        {:ok, user}

      _ ->
        {:error, "Notification rules are only available to an authenticated user."}
    end
  end

  def rule(user, id) do
    case Notifications.get_rule(user, id) do
      {:ok, rule} -> {:ok, rule}
      {:error, :not_found} -> {:error, "Notification rule not found."}
    end
  end

  def saved({:ok, rule}), do: {:ok, Notifications.rule_to_map(rule)}
  def saved({:error, reason}), do: {:error, Notifications.error_message(reason)}
end

defmodule Tuist.MCP.Components.Tools.ListNotificationEvents do
  @moduledoc """
  List the event types notification rules can subscribe to.
  """

  use Tuist.MCP.Tool,
    name: "list_notification_events",
    title: "List Notification Events",
    read_only_hint: true,
    schema: %{"type" => "object", "properties" => %{}, "additionalProperties" => false},
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "events" => %{
          "type" => "array",
          "items" => %{
            "type" => "object",
            "properties" => %{
              "id" => %{"type" => "string"},
              "title" => %{"type" => "string"},
              "description" => %{"type" => "string"},
              "conditions_schema" => %{"type" => "object"}
            },
            "required" => ["id", "title", "description", "conditions_schema"],
            "additionalProperties" => false
          }
        }
      },
      "required" => ["events"],
      "additionalProperties" => false
    }

  alias Tuist.MCP.Components.Tools.NotificationRuleTools
  alias Tuist.Notifications

  @impl EMCP.Tool
  def description do
    "List the event types the authenticated user's notification rules can subscribe to, each with a JSON Schema for its conditions."
  end

  def execute(conn, _args) do
    with {:ok, _user} <- NotificationRuleTools.user(conn) do
      {:ok, %{"events" => Enum.map(Notifications.events(), &Notifications.event_to_map/1)}}
    end
  end
end

defmodule Tuist.MCP.Components.Tools.ListNotificationConditionOptions do
  @moduledoc """
  Suggest condition values for an event in a project.
  """

  use Tuist.MCP.Tool,
    name: "list_notification_condition_options",
    title: "List Notification Condition Options",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "event" => %{"type" => "string", "description" => "The event type's id from list_notification_events."},
        "account_handle" => %{"type" => "string"},
        "project_handle" => %{"type" => "string"}
      },
      "required" => ["event", "account_handle", "project_handle"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "options" => %{
          "type" => "object",
          "description" => "Suggested values per condition, for example track and git_branch.",
          "additionalProperties" => %{"type" => "array", "items" => %{"type" => "string"}}
        }
      },
      "required" => ["options"],
      "additionalProperties" => false
    }

  alias Tuist.MCP.Components.Tools.NotificationRuleTools
  alias Tuist.Notifications
  alias Tuist.Projects

  @impl EMCP.Tool
  def description do
    "List values the authenticated user can use in a notification rule's conditions for a project, " <>
      "such as the tracks and branches of its recent previews."
  end

  def execute(conn, %{"event" => event, "account_handle" => account, "project_handle" => project}) do
    with {:ok, user} <- NotificationRuleTools.user(conn),
         {:ok, project} <- Projects.get_project_by_slug("#{account}/#{project}"),
         {:ok, options} <- Notifications.condition_options(user, event, project) do
      {:ok, %{"options" => options}}
    else
      {:error, message} when is_binary(message) -> {:error, message}
      _ -> {:error, "Unknown event, or a project you can't get its notifications for."}
    end
  end
end

defmodule Tuist.MCP.Components.Tools.ListNotificationRules do
  @moduledoc """
  List the authenticated user's notification rules.
  """

  use Tuist.MCP.Tool,
    name: "list_notification_rules",
    title: "List Notification Rules",
    read_only_hint: true,
    schema: %{"type" => "object", "properties" => %{}, "additionalProperties" => false},
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "rules" => %{"type" => "array", "items" => Tuist.MCP.Components.Tools.NotificationRuleTools.rule_schema()}
      },
      "required" => ["rules"],
      "additionalProperties" => false
    }

  alias Tuist.MCP.Components.Tools.NotificationRuleTools
  alias Tuist.Notifications

  @impl EMCP.Tool
  def description do
    "List the authenticated user's notification rules, oldest first. A user with no rules gets no notifications."
  end

  def execute(conn, _args) do
    with {:ok, user} <- NotificationRuleTools.user(conn) do
      {:ok, %{"rules" => user |> Notifications.list_rules() |> Enum.map(&Notifications.rule_to_map/1)}}
    end
  end
end

defmodule Tuist.MCP.Components.Tools.CreateNotificationRule do
  @moduledoc """
  Create a notification rule for the authenticated user.
  """

  use Tuist.MCP.Tool,
    name: "create_notification_rule",
    title: "Create Notification Rule",
    read_only_hint: false,
    schema: %{
      "type" => "object",
      "properties" =>
        Map.put(
          Tuist.MCP.Components.Tools.NotificationRuleTools.rule_properties(),
          "event",
          %{"type" => "string", "description" => "The event type's id from list_notification_events."}
        ),
      "required" => ["event", "actions"],
      "additionalProperties" => false
    },
    output_schema: Tuist.MCP.Components.Tools.NotificationRuleTools.rule_schema()

  alias Tuist.MCP.Components.Tools.NotificationRuleTools
  alias Tuist.Notifications

  @impl EMCP.Tool
  def description do
    "Create a notification rule for the authenticated user: when the event happens in the rule's projects and meets its conditions, run its actions. " <>
      "Projects must be ones the user belongs to."
  end

  def execute(conn, args) do
    with {:ok, user} <- NotificationRuleTools.user(conn) do
      user |> Notifications.create_rule(args) |> NotificationRuleTools.saved()
    end
  end
end

defmodule Tuist.MCP.Components.Tools.UpdateNotificationRule do
  @moduledoc """
  Update one of the authenticated user's notification rules.
  """

  use Tuist.MCP.Tool,
    name: "update_notification_rule",
    title: "Update Notification Rule",
    read_only_hint: false,
    destructive_hint: true,
    schema: %{
      "type" => "object",
      "properties" =>
        Map.put(Tuist.MCP.Components.Tools.NotificationRuleTools.rule_properties(), "rule_id", %{"type" => "string"}),
      "required" => ["rule_id"],
      "additionalProperties" => false
    },
    output_schema: Tuist.MCP.Components.Tools.NotificationRuleTools.rule_schema()

  alias Tuist.MCP.Components.Tools.NotificationRuleTools
  alias Tuist.Notifications

  @impl EMCP.Tool
  def description do
    "Update one of the authenticated user's notification rules. Only the given fields change; projects replaces the rule's projects, and its event can't change."
  end

  def execute(conn, %{"rule_id" => id} = args) do
    with {:ok, user} <- NotificationRuleTools.user(conn),
         {:ok, rule} <- NotificationRuleTools.rule(user, id) do
      user |> Notifications.update_rule(rule, Map.delete(args, "rule_id")) |> NotificationRuleTools.saved()
    end
  end
end

defmodule Tuist.MCP.Components.Tools.DeleteNotificationRule do
  @moduledoc """
  Delete one of the authenticated user's notification rules.
  """

  use Tuist.MCP.Tool,
    name: "delete_notification_rule",
    title: "Delete Notification Rule",
    read_only_hint: false,
    destructive_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{"rule_id" => %{"type" => "string"}},
      "required" => ["rule_id"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{"deleted" => %{"type" => "boolean"}},
      "required" => ["deleted"],
      "additionalProperties" => false
    }

  alias Tuist.MCP.Components.Tools.NotificationRuleTools
  alias Tuist.Notifications

  @impl EMCP.Tool
  def description, do: "Delete one of the authenticated user's notification rules."

  def execute(conn, %{"rule_id" => id}) do
    with {:ok, user} <- NotificationRuleTools.user(conn),
         {:ok, rule} <- NotificationRuleTools.rule(user, id) do
      :ok = Notifications.delete_rule(user, rule)
      {:ok, %{"deleted" => true}}
    end
  end
end
