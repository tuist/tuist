defmodule TuistWeb.API.AutomationsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Automations
  alias TuistWeb.API.Schemas.Error

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :automation)

  tags ["Automations"]

  @action_schema %Schema{
    type: :object,
    properties: %{
      type: %Schema{type: :string, enum: ["change_state", "send_slack", "mark_as_flaky", "unmark_as_flaky"]},
      state: %Schema{type: :string, enum: ["enabled", "muted"], description: "Required for change_state actions."},
      channel: %Schema{type: :string, description: "Slack channel ID. Required for send_slack actions."},
      channel_name: %Schema{type: :string, description: "Slack channel name for display."},
      message: %Schema{type: :string, description: "Message template. Required for send_slack actions. Supports {{variable}} interpolation."}
    },
    required: [:type]
  }

  @automation_schema %Schema{
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      name: %Schema{type: :string},
      enabled: %Schema{type: :boolean},
      automation_type: %Schema{type: :string, enum: ["flakiness_rate", "flaky_run_count"]},
      config: %Schema{type: :object},
      cadence: %Schema{type: :string},
      trigger_actions: %Schema{type: :array, items: @action_schema},
      recovery_enabled: %Schema{type: :boolean},
      recovery_config: %Schema{type: :object},
      recovery_actions: %Schema{type: :array, items: @action_schema}
    },
    required: [:id, :name, :enabled, :automation_type, :config, :cadence, :trigger_actions]
  }

  operation(:index,
    summary: "List automations for a project.",
    operation_id: "listAutomations",
    parameters: [
      account_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The handle of the account."
      ],
      project_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The handle of the project."
      ]
    ],
    responses: %{
      ok:
        {"List of automations", "application/json",
         %Schema{
           type: :object,
           properties: %{
             automations: %Schema{
               type: :array,
               items: @automation_schema
             }
           },
           required: [:automations]
         }},
      forbidden: {"Forbidden", "application/json", Error}
    }
  )

  def index(%{assigns: %{selected_project: project}} = conn, _params) do
    automations = Automations.list_automations(project.id)

    json(conn, %{
      automations: Enum.map(automations, &serialize_automation/1)
    })
  end

  operation(:show,
    summary: "Get an automation by ID.",
    operation_id: "getAutomation",
    parameters: [
      account_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The handle of the account."
      ],
      project_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The handle of the project."
      ],
      automation_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "The ID of the automation."
      ]
    ],
    responses: %{
      ok: {"Automation details", "application/json", @automation_schema},
      not_found: {"Not found", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error}
    }
  )

  def show(%{assigns: %{selected_project: project}, params: %{automation_id: automation_id}} = conn, _params) do
    case Automations.get_automation(automation_id) do
      {:ok, automation} ->
        if automation.project_id == project.id do
          json(conn, serialize_automation(automation))
        else
          conn |> put_status(:not_found) |> json(%{message: "Automation not found."})
        end

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{message: "Automation not found."})
    end
  end

  operation(:create,
    summary: "Create an automation.",
    operation_id: "createAutomation",
    parameters: [
      account_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The handle of the account."
      ],
      project_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The handle of the project."
      ]
    ],
    request_body:
      {"Automation", "application/json",
       %Schema{
         type: :object,
         properties: %{
           name: %Schema{type: :string},
           automation_type: %Schema{type: :string, enum: ["flakiness_rate", "flaky_run_count"]},
           config: %Schema{type: :object},
           cadence: %Schema{type: :string},
           trigger_actions: %Schema{type: :array, items: @action_schema},
           recovery_enabled: %Schema{type: :boolean},
           recovery_config: %Schema{type: :object},
           recovery_actions: %Schema{type: :array, items: @action_schema}
         },
         required: [:name, :automation_type, :trigger_actions]
       }},
    responses: %{
      created: {"Created automation", "application/json", @automation_schema},
      unprocessable_entity: {"Validation error", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error}
    }
  )

  def create(%{assigns: %{selected_project: project}, body_params: body_params} = conn, _params) do
    attrs =
      body_params
      |> normalize_params()
      |> Map.put("project_id", project.id)

    case Automations.create_automation(attrs) do
      {:ok, automation} ->
        conn |> put_status(:created) |> json(serialize_automation(automation))

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{message: format_errors(changeset)})
    end
  end

  operation(:update,
    summary: "Update an automation.",
    operation_id: "updateAutomation",
    parameters: [
      account_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The handle of the account."
      ],
      project_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The handle of the project."
      ],
      automation_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "The ID of the automation."
      ]
    ],
    request_body:
      {"Automation update", "application/json",
       %Schema{
         type: :object,
         properties: %{
           name: %Schema{type: :string},
           enabled: %Schema{type: :boolean},
           config: %Schema{type: :object},
           cadence: %Schema{type: :string},
           trigger_actions: %Schema{type: :array, items: @action_schema},
           recovery_enabled: %Schema{type: :boolean},
           recovery_config: %Schema{type: :object},
           recovery_actions: %Schema{type: :array, items: @action_schema}
         }
       }},
    responses: %{
      ok: {"Updated automation", "application/json", @automation_schema},
      not_found: {"Not found", "application/json", Error},
      unprocessable_entity: {"Validation error", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error}
    }
  )

  def update(
        %{assigns: %{selected_project: project}, params: %{automation_id: automation_id}, body_params: body_params} = conn,
        _params
      ) do
    with {:ok, automation} <- Automations.get_automation(automation_id),
         true <- automation.project_id == project.id do
      attrs = normalize_params(body_params)

      case Automations.update_automation(automation, attrs) do
        {:ok, updated} ->
          json(conn, serialize_automation(updated))

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{message: format_errors(changeset)})
      end
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{message: "Automation not found."})

      false ->
        conn |> put_status(:not_found) |> json(%{message: "Automation not found."})
    end
  end

  operation(:delete,
    summary: "Delete an automation.",
    operation_id: "deleteAutomation",
    parameters: [
      account_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The handle of the account."
      ],
      project_handle: [
        in: :path,
        type: :string,
        required: true,
        description: "The handle of the project."
      ],
      automation_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "The ID of the automation."
      ]
    ],
    responses: %{
      no_content: {"Deleted", "application/json", nil},
      not_found: {"Not found", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error}
    }
  )

  def delete(%{assigns: %{selected_project: project}, params: %{automation_id: automation_id}} = conn, _params) do
    with {:ok, automation} <- Automations.get_automation(automation_id),
         true <- automation.project_id == project.id,
         {:ok, _} <- Automations.delete_automation(automation) do
      send_resp(conn, :no_content, "")
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{message: "Automation not found."})

      false ->
        conn |> put_status(:not_found) |> json(%{message: "Automation not found."})
    end
  end

  defp serialize_automation(automation) do
    %{
      id: automation.id,
      name: automation.name,
      enabled: automation.enabled,
      automation_type: automation.automation_type,
      config: automation.config,
      cadence: automation.cadence,
      trigger_actions: automation.trigger_actions,
      recovery_enabled: automation.recovery_enabled,
      recovery_config: automation.recovery_config,
      recovery_actions: automation.recovery_actions
    }
  end

  defp normalize_params(params) when is_map(params) and not is_struct(params) do
    Map.new(params, fn {key, value} -> {to_string(key), normalize_params(value)} end)
  end

  defp normalize_params(params) when is_list(params) do
    Enum.map(params, &normalize_params/1)
  end

  defp normalize_params(value), do: value

  defp format_errors(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map_join(", ", fn {field, errors} -> "#{field}: #{Enum.join(errors, ", ")}" end)
  end
end
