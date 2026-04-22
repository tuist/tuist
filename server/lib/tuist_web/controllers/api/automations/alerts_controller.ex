defmodule TuistWeb.API.Automations.AlertsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Automations
  alias TuistWeb.API.RequestParams
  alias TuistWeb.API.Schemas.AutomationAlert
  alias TuistWeb.API.Schemas.AutomationAlertAction
  alias TuistWeb.API.Schemas.Error

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :automation_alert)

  tags ["Automation Alerts"]

  operation(:index,
    summary: "List automation alerts for a project.",
    operation_id: "listAutomationAlerts",
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
        {"List of automation alerts", "application/json",
         %Schema{
           type: :object,
           properties: %{
             alerts: %Schema{
               type: :array,
               items: AutomationAlert
             }
           },
           required: [:alerts]
         }},
      forbidden: {"Forbidden", "application/json", Error}
    }
  )

  def index(%{assigns: %{selected_project: project}} = conn, _params) do
    alerts = Automations.list_alerts(project.id)

    json(conn, %{
      alerts: Enum.map(alerts, &AutomationAlert.from_model/1)
    })
  end

  operation(:show,
    summary: "Get an automation alert by ID.",
    operation_id: "getAutomationAlert",
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
      alert_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "The ID of the alert."
      ]
    ],
    responses: %{
      ok: {"Alert details", "application/json", AutomationAlert},
      not_found: {"Not found", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error}
    }
  )

  def show(%{assigns: %{selected_project: project}, params: %{alert_id: alert_id}} = conn, _params) do
    case Automations.get_alert(alert_id) do
      {:ok, alert} ->
        if alert.project_id == project.id do
          json(conn, AutomationAlert.from_model(alert))
        else
          conn |> put_status(:not_found) |> json(%{message: "Alert not found."})
        end

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{message: "Alert not found."})
    end
  end

  operation(:create,
    summary: "Create an automation alert.",
    operation_id: "createAutomationAlert",
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
      {"Automation alert", "application/json",
       %Schema{
         type: :object,
         properties: %{
           name: %Schema{type: :string},
           monitor_type: %Schema{type: :string, enum: ["flakiness_rate", "flaky_run_count"]},
           trigger_config: %Schema{type: :object},
           cadence: %Schema{type: :string},
           trigger_actions: %Schema{type: :array, items: AutomationAlertAction},
           recovery_enabled: %Schema{type: :boolean},
           recovery_config: %Schema{type: :object},
           recovery_actions: %Schema{type: :array, items: AutomationAlertAction}
         },
         required: [:name, :monitor_type, :trigger_actions]
       }},
    responses: %{
      created: {"Created alert", "application/json", AutomationAlert},
      unprocessable_entity: {"Validation error", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error}
    }
  )

  def create(%{assigns: %{selected_project: project}, body_params: body_params} = conn, _params) do
    attrs =
      body_params
      |> RequestParams.normalize()
      |> Map.put("project_id", project.id)

    case Automations.create_alert(attrs) do
      {:ok, alert} ->
        conn |> put_status(:created) |> json(AutomationAlert.from_model(alert))

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{message: RequestParams.format_errors(changeset)})
    end
  end

  operation(:update,
    summary: "Update an automation alert.",
    operation_id: "updateAutomationAlert",
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
      alert_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "The ID of the alert."
      ]
    ],
    request_body:
      {"Automation alert update", "application/json",
       %Schema{
         type: :object,
         properties: %{
           name: %Schema{type: :string},
           enabled: %Schema{type: :boolean},
           trigger_config: %Schema{type: :object},
           cadence: %Schema{type: :string},
           trigger_actions: %Schema{type: :array, items: AutomationAlertAction},
           recovery_enabled: %Schema{type: :boolean},
           recovery_config: %Schema{type: :object},
           recovery_actions: %Schema{type: :array, items: AutomationAlertAction}
         }
       }},
    responses: %{
      ok: {"Updated alert", "application/json", AutomationAlert},
      not_found: {"Not found", "application/json", Error},
      unprocessable_entity: {"Validation error", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error}
    }
  )

  def update(
        %{assigns: %{selected_project: project}, params: %{alert_id: alert_id}, body_params: body_params} = conn,
        _params
      ) do
    with {:ok, alert} <- Automations.get_alert(alert_id),
         true <- alert.project_id == project.id do
      attrs = RequestParams.normalize(body_params)

      case Automations.update_alert(alert, attrs) do
        {:ok, updated} ->
          json(conn, AutomationAlert.from_model(updated))

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{message: RequestParams.format_errors(changeset)})
      end
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{message: "Alert not found."})

      false ->
        conn |> put_status(:not_found) |> json(%{message: "Alert not found."})
    end
  end

  operation(:delete,
    summary: "Delete an automation alert.",
    operation_id: "deleteAutomationAlert",
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
      alert_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "The ID of the alert."
      ]
    ],
    responses: %{
      no_content: {"Deleted", "application/json", nil},
      not_found: {"Not found", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error}
    }
  )

  def delete(%{assigns: %{selected_project: project}, params: %{alert_id: alert_id}} = conn, _params) do
    with {:ok, alert} <- Automations.get_alert(alert_id),
         true <- alert.project_id == project.id,
         {:ok, _} <- Automations.delete_alert(alert) do
      send_resp(conn, :no_content, "")
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{message: "Alert not found."})

      false ->
        conn |> put_status(:not_found) |> json(%{message: "Alert not found."})
    end
  end
end
