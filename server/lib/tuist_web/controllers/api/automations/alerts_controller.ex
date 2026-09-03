defmodule TuistWeb.API.Automations.AlertsController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Automations
  alias TuistWeb.API.RequestParams
  alias TuistWeb.API.Responses
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
      forbidden: {"Forbidden", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
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
      forbidden: {"Forbidden", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
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

  @revision_schema %Schema{
    title: "AutomationAlertRevision",
    type: :object,
    properties: %{
      id: %Schema{type: :string, format: :uuid},
      event: %Schema{type: :string, enum: ["created", "updated"]},
      source: %Schema{type: :string},
      actor: %Schema{
        type: :object,
        nullable: true,
        properties: %{id: %Schema{type: :integer}, name: %Schema{type: :string}, email: %Schema{type: :string}},
        required: [:id, :name, :email]
      },
      changes: %Schema{type: :object},
      snapshot: %Schema{type: :object},
      inserted_at: %Schema{type: :string, format: "date-time"}
    },
    required: [:id, :event, :source, :actor, :changes, :snapshot, :inserted_at]
  }

  operation(:index_revisions,
    summary: "List an automation alert's revision history.",
    operation_id: "listAutomationAlertRevisions",
    parameters: [
      account_handle: [in: :path, type: :string, required: true, description: "The handle of the account."],
      project_handle: [in: :path, type: :string, required: true, description: "The handle of the project."],
      alert_id: [in: :path, schema: %Schema{type: :string, format: :uuid}, required: true],
      before: [in: :query, schema: %Schema{type: :string, format: :uuid}, required: false],
      page_size: [in: :query, type: :integer, required: false, description: "Results per page, up to 100."]
    ],
    responses: %{
      ok:
        {"Automation alert revisions", "application/json",
         %Schema{
           type: :object,
           properties: %{
             revisions: %Schema{type: :array, items: @revision_schema},
             next_before: %Schema{type: :string, format: :uuid, nullable: true}
           },
           required: [:revisions, :next_before]
         }},
      not_found: {"Not found", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def index_revisions(%{assigns: %{selected_project: project}, params: params} = conn, _params) do
    with {:ok, alert} <- Automations.get_alert(params.alert_id),
         true <- alert.project_id == project.id,
         {:ok, before} <- revision_cursor(alert.id, Map.get(params, :before)) do
      page_size = params |> Map.get(:page_size, 20) |> max(1) |> min(100)
      revisions = Automations.list_alert_revisions(alert.id, before: before, limit: page_size + 1)
      {page, remaining} = Enum.split(revisions, page_size)

      json(conn, %{
        revisions: Enum.map(page, &Automations.redact_revision/1),
        next_before: if(remaining == [], do: nil, else: List.last(page).id)
      })
    else
      {:error, :not_found} -> conn |> put_status(:not_found) |> json(%{message: "Automation alert revision not found."})
      false -> conn |> put_status(:not_found) |> json(%{message: "Automation alert not found."})
    end
  end

  defp revision_cursor(_alert_id, nil), do: {:ok, nil}

  defp revision_cursor(alert_id, revision_id), do: Automations.get_alert_revision(alert_id, revision_id)

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
           monitor_type: %Schema{type: :string, enum: ["flakiness_rate", "flaky_run_count", "reliability_rate"]},
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
      internal_server_error: {"An internal server error occurred", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def create(%{assigns: %{selected_project: project}, body_params: body_params} = conn, _params) do
    attrs =
      body_params
      |> RequestParams.normalize()
      |> Map.put("project_id", project.id)

    case Automations.create_alert(attrs, actor: conn.assigns[:current_user], source: "integration") do
      {:ok, alert} ->
        conn |> put_status(:created) |> json(AutomationAlert.from_model(alert))

      {:error, :revision} ->
        conn |> put_status(:internal_server_error) |> json(%{message: "Could not record automation history."})

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
      internal_server_error: {"An internal server error occurred", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
    }
  )

  def update(
        %{assigns: %{selected_project: project}, params: %{alert_id: alert_id}, body_params: body_params} = conn,
        _params
      ) do
    with {:ok, alert} <- Automations.get_alert(alert_id),
         true <- alert.project_id == project.id do
      attrs = RequestParams.normalize(body_params)

      case Automations.update_alert(alert, attrs, actor: conn.assigns[:current_user], source: "integration") do
        {:ok, updated} ->
          json(conn, AutomationAlert.from_model(updated))

        {:error, :revision} ->
          conn |> put_status(:internal_server_error) |> json(%{message: "Could not record automation history."})

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
      forbidden: {"Forbidden", "application/json", Error},
      too_many_requests: Responses.authorization_throttled()
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
