defmodule TuistWeb.API.NotificationRulesController do
  @moduledoc """
  The signed-in user's notification rules (`Tuist.Notifications`). Event
  conditions differ per event type, so request bodies are validated by
  `Tuist.Notifications` against the event's `conditions_schema` rather than by
  `TuistWeb.Plugs.CastAndValidate`.
  """
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Notifications
  alias Tuist.Projects
  alias TuistWeb.API.Responses
  alias TuistWeb.API.Schemas.Error

  # Reject other credentials before reading their requests.
  plug TuistWeb.Plugs.AppSessionPlug

  tags ["Notification rules"]

  @action %Schema{
    title: "NotificationRuleAction",
    type: :object,
    properties: %{type: %Schema{type: :string, description: "Known values: `push`, to the user's Tuist app devices."}},
    required: [:type]
  }

  @conditions %Schema{
    type: :object,
    additionalProperties: true,
    description: "Filters on the event. Their shape depends on the event; see `conditions_schema` in its event type."
  }

  @projects %Schema{
    type: :array,
    items: %Schema{type: :string},
    description:
      "`account/project` handles the rule covers. Empty means every project the user can get the event's notifications for, including later ones."
  }

  @rule %Schema{
    title: "NotificationRule",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      event: %Schema{type: :string, description: "The event type's ID, for example `preview_published`."},
      enabled: %Schema{type: :boolean},
      projects: @projects,
      conditions: @conditions,
      actions: %Schema{type: :array, items: @action},
      inserted_at: %Schema{type: :string, format: :"date-time"},
      updated_at: %Schema{type: :string, format: :"date-time"}
    },
    required: [:id, :event, :enabled, :projects, :conditions, :actions, :inserted_at, :updated_at]
  }

  @rule_id [in: :path, type: :string, required: true, description: "The rule's ID."]

  @common_errors %{
    unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
    forbidden: {"Only the signed-in Tuist app can manage notification rules", "application/json", Error}
  }

  operation(:events,
    summary: "Lists the event types notification rules can subscribe to",
    operation_id: "listNotificationEvents",
    responses:
      Map.put(
        @common_errors,
        :ok,
        {"The event types", "application/json",
         %Schema{
           title: "NotificationEvents",
           type: :object,
           properties: %{
             events: %Schema{
               type: :array,
               items: %Schema{
                 title: "NotificationEvent",
                 type: :object,
                 properties: %{
                   id: %Schema{type: :string},
                   title: %Schema{type: :string},
                   description: %Schema{type: :string},
                   conditions_schema: %Schema{type: :object, description: "A JSON Schema for the rule's conditions."}
                 },
                 required: [:id, :title, :description, :conditions_schema]
               }
             }
           },
           required: [:events]
         }}
      )
  )

  def events(conn, _params) do
    json(conn, %{events: Enum.map(Notifications.events(), &Notifications.event_to_map/1)})
  end

  operation(:condition_options,
    summary: "Suggests condition values for an event in a project",
    description:
      "Returns values a client can offer for the event's conditions, for example the tracks and branches of the project's recent previews.",
    operation_id: "listNotificationConditionOptions",
    parameters: [
      event: [in: :path, type: :string, required: true, description: "The event type's ID."],
      account_handle: [in: :path, type: :string, required: true],
      project_handle: [in: :path, type: :string, required: true]
    ],
    responses:
      Map.merge(@common_errors, %{
        ok:
          {"Suggested values per condition", "application/json",
           %Schema{
             title: "NotificationConditionOptions",
             type: :object,
             properties: %{
               options: %Schema{
                 type: :object,
                 additionalProperties: %Schema{type: :array, items: %Schema{type: :string}},
                 description: "Suggested values per condition, for example `track` and `git_branch`."
               }
             },
             required: [:options]
           }},
        not_found: {"The event or project doesn't exist, or the user can't subscribe to it", "application/json", Error}
      })
  )

  def condition_options(conn, %{"event" => event, "account_handle" => account, "project_handle" => project}) do
    with {:ok, project} <- Projects.get_project_by_slug("#{account}/#{project}"),
         {:ok, options} <- Notifications.condition_options(conn.assigns.app_user, event, project) do
      json(conn, %{options: options})
    else
      _ -> not_found(conn)
    end
  end

  operation(:index,
    summary: "Lists the signed-in user's notification rules",
    description: "A user with no rules gets no notifications.",
    operation_id: "listNotificationRules",
    responses:
      Map.put(
        @common_errors,
        :ok,
        {"The rules, oldest first", "application/json",
         %Schema{
           title: "NotificationRules",
           type: :object,
           properties: %{rules: %Schema{type: :array, items: @rule}},
           required: [:rules]
         }}
      )
  )

  def index(conn, _params) do
    json(conn, %{rules: conn.assigns.app_user |> Notifications.list_rules() |> Enum.map(&Notifications.rule_to_map/1)})
  end

  operation(:show,
    summary: "Gets one of the signed-in user's notification rules",
    operation_id: "getNotificationRule",
    parameters: [id: @rule_id],
    responses:
      Map.merge(@common_errors, %{
        ok: {"The rule", "application/json", @rule},
        not_found: {"The rule doesn't exist", "application/json", Error}
      })
  )

  def show(conn, %{"id" => id}) do
    case Notifications.get_rule(conn.assigns.app_user, id) do
      {:ok, rule} -> json(conn, Notifications.rule_to_map(rule))
      {:error, :not_found} -> not_found(conn)
    end
  end

  operation(:create,
    summary: "Creates a notification rule for the signed-in user",
    operation_id: "createNotificationRule",
    request_body:
      {"The rule", "application/json",
       %Schema{
         title: "CreateNotificationRule",
         type: :object,
         properties: %{
           event: %Schema{type: :string, description: "The event type's ID."},
           enabled: %Schema{type: :boolean, default: true},
           projects: @projects,
           conditions: @conditions,
           actions: %Schema{type: :array, items: @action, minItems: 1}
         },
         required: [:event, :actions]
       }, required: true},
    responses:
      Map.merge(@common_errors, %{
        created: {"The rule", "application/json", @rule},
        bad_request: {"The rule is invalid", "application/json", Error},
        too_many_requests: Responses.app_writes_throttled(),
        unprocessable_entity: {"The user has too many rules", "application/json", Error}
      })
  )

  def create(conn, _params) do
    case Notifications.create_rule(conn.assigns.app_user, conn.body_params) do
      {:ok, rule} -> conn |> put_status(:created) |> json(Notifications.rule_to_map(rule))
      {:error, reason} -> invalid(conn, reason)
    end
  end

  operation(:update,
    summary: "Updates one of the signed-in user's notification rules",
    description: "Only the given fields change. Its event can't change, and `projects` replaces the rule's projects.",
    operation_id: "updateNotificationRule",
    parameters: [id: @rule_id],
    request_body:
      {"The fields to change", "application/json",
       %Schema{
         title: "UpdateNotificationRule",
         type: :object,
         properties: %{
           enabled: %Schema{type: :boolean},
           projects: @projects,
           conditions: @conditions,
           actions: %Schema{type: :array, items: @action, minItems: 1}
         }
       }, required: true},
    responses:
      Map.merge(@common_errors, %{
        ok: {"The rule", "application/json", @rule},
        bad_request: {"The rule is invalid", "application/json", Error},
        not_found: {"The rule doesn't exist", "application/json", Error},
        too_many_requests: Responses.app_writes_throttled()
      })
  )

  def update(conn, %{"id" => id}) do
    user = conn.assigns.app_user

    with {:ok, rule} <- Notifications.get_rule(user, id),
         {:ok, rule} <- Notifications.update_rule(user, rule, Map.delete(conn.body_params, "id")) do
      json(conn, Notifications.rule_to_map(rule))
    else
      {:error, :not_found} -> not_found(conn)
      {:error, reason} -> invalid(conn, reason)
    end
  end

  operation(:delete,
    summary: "Deletes one of the signed-in user's notification rules",
    operation_id: "deleteNotificationRule",
    parameters: [id: @rule_id],
    responses:
      Map.merge(@common_errors, %{
        no_content: "The rule was deleted",
        not_found: {"The rule doesn't exist", "application/json", Error},
        too_many_requests: Responses.app_writes_throttled()
      })
  )

  def delete(conn, %{"id" => id}) do
    user = conn.assigns.app_user

    case Notifications.get_rule(user, id) do
      {:ok, rule} ->
        :ok = Notifications.delete_rule(user, rule)
        send_resp(conn, :no_content, "")

      {:error, :not_found} ->
        not_found(conn)
    end
  end

  defp not_found(conn), do: conn |> put_status(:not_found) |> json(%{message: "Not found."})

  defp invalid(conn, :limit_reached),
    do: conn |> put_status(:unprocessable_entity) |> json(%{message: Notifications.error_message(:limit_reached)})

  defp invalid(conn, reason),
    do: conn |> put_status(:bad_request) |> json(%{message: Notifications.error_message(reason)})
end
