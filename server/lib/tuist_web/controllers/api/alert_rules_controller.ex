defmodule TuistWeb.API.AlertRulesController do
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Automations
  alias TuistWeb.API.Schemas.AlertRule
  alias TuistWeb.API.Schemas.AlertRuleAction
  alias TuistWeb.API.Schemas.Error

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  plug(TuistWeb.Plugs.LoaderPlug)
  plug(TuistWeb.API.Authorization.AuthorizationPlug, :project)

  tags ["Alert Rules"]

  operation(:index,
    summary: "List alert rules for a project.",
    operation_id: "listAlertRules",
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
        {"List of alert rules", "application/json",
         %Schema{
           type: :object,
           properties: %{
             alert_rules: %Schema{
               type: :array,
               items: AlertRule
             }
           },
           required: [:alert_rules]
         }},
      forbidden: {"Forbidden", "application/json", Error}
    }
  )

  def index(%{assigns: %{selected_project: project}} = conn, _params) do
    alert_rules = Automations.list_alert_rules(project.id)

    json(conn, %{
      alert_rules: Enum.map(alert_rules, &serialize_alert_rule/1)
    })
  end

  operation(:show,
    summary: "Get an alert rule by ID.",
    operation_id: "getAlertRule",
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
      alert_rule_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "The ID of the alert rule."
      ]
    ],
    responses: %{
      ok: {"Alert rule details", "application/json", AlertRule},
      not_found: {"Not found", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error}
    }
  )

  def show(%{assigns: %{selected_project: project}, params: %{alert_rule_id: alert_rule_id}} = conn, _params) do
    case Automations.get_alert_rule(alert_rule_id) do
      {:ok, alert_rule} ->
        if alert_rule.project_id == project.id do
          json(conn, serialize_alert_rule(alert_rule))
        else
          conn |> put_status(:not_found) |> json(%{message: "Alert rule not found."})
        end

      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{message: "Alert rule not found."})
    end
  end

  operation(:create,
    summary: "Create an alert rule.",
    operation_id: "createAlertRule",
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
      {"Alert rule", "application/json",
       %Schema{
         type: :object,
         properties: %{
           name: %Schema{type: :string},
           monitor_type: %Schema{type: :string, enum: ["flakiness_rate", "flaky_run_count"]},
           trigger_config: %Schema{type: :object},
           cadence: %Schema{type: :string},
           trigger_actions: %Schema{type: :array, items: AlertRuleAction},
           recovery_enabled: %Schema{type: :boolean},
           recovery_config: %Schema{type: :object},
           recovery_actions: %Schema{type: :array, items: AlertRuleAction}
         },
         required: [:name, :monitor_type, :trigger_actions]
       }},
    responses: %{
      created: {"Created alert rule", "application/json", AlertRule},
      unprocessable_entity: {"Validation error", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error}
    }
  )

  def create(%{assigns: %{selected_project: project}, body_params: body_params} = conn, _params) do
    attrs =
      body_params
      |> normalize_params()
      |> Map.put("project_id", project.id)

    case Automations.create_alert_rule(attrs) do
      {:ok, alert_rule} ->
        conn |> put_status(:created) |> json(serialize_alert_rule(alert_rule))

      {:error, changeset} ->
        conn
        |> put_status(:unprocessable_entity)
        |> json(%{message: format_errors(changeset)})
    end
  end

  operation(:update,
    summary: "Update an alert rule.",
    operation_id: "updateAlertRule",
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
      alert_rule_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "The ID of the alert rule."
      ]
    ],
    request_body:
      {"Alert rule update", "application/json",
       %Schema{
         type: :object,
         properties: %{
           name: %Schema{type: :string},
           enabled: %Schema{type: :boolean},
           trigger_config: %Schema{type: :object},
           cadence: %Schema{type: :string},
           trigger_actions: %Schema{type: :array, items: AlertRuleAction},
           recovery_enabled: %Schema{type: :boolean},
           recovery_config: %Schema{type: :object},
           recovery_actions: %Schema{type: :array, items: AlertRuleAction}
         }
       }},
    responses: %{
      ok: {"Updated alert rule", "application/json", AlertRule},
      not_found: {"Not found", "application/json", Error},
      unprocessable_entity: {"Validation error", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error}
    }
  )

  def update(
        %{assigns: %{selected_project: project}, params: %{alert_rule_id: alert_rule_id}, body_params: body_params} = conn,
        _params
      ) do
    with {:ok, alert_rule} <- Automations.get_alert_rule(alert_rule_id),
         true <- alert_rule.project_id == project.id do
      attrs = normalize_params(body_params)

      case Automations.update_alert_rule(alert_rule, attrs) do
        {:ok, updated} ->
          json(conn, serialize_alert_rule(updated))

        {:error, changeset} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{message: format_errors(changeset)})
      end
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{message: "Alert rule not found."})

      false ->
        conn |> put_status(:not_found) |> json(%{message: "Alert rule not found."})
    end
  end

  operation(:delete,
    summary: "Delete an alert rule.",
    operation_id: "deleteAlertRule",
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
      alert_rule_id: [
        in: :path,
        schema: %Schema{type: :string, format: :uuid},
        required: true,
        description: "The ID of the alert rule."
      ]
    ],
    responses: %{
      no_content: {"Deleted", "application/json", nil},
      not_found: {"Not found", "application/json", Error},
      forbidden: {"Forbidden", "application/json", Error}
    }
  )

  def delete(%{assigns: %{selected_project: project}, params: %{alert_rule_id: alert_rule_id}} = conn, _params) do
    with {:ok, alert_rule} <- Automations.get_alert_rule(alert_rule_id),
         true <- alert_rule.project_id == project.id,
         {:ok, _} <- Automations.delete_alert_rule(alert_rule) do
      send_resp(conn, :no_content, "")
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{message: "Alert rule not found."})

      false ->
        conn |> put_status(:not_found) |> json(%{message: "Alert rule not found."})
    end
  end

  defp serialize_alert_rule(alert_rule) do
    %{
      id: alert_rule.id,
      name: alert_rule.name,
      enabled: alert_rule.enabled,
      monitor_type: alert_rule.monitor_type,
      trigger_config: alert_rule.trigger_config,
      cadence: alert_rule.cadence,
      trigger_actions: alert_rule.trigger_actions,
      recovery_enabled: alert_rule.recovery_enabled,
      recovery_config: alert_rule.recovery_config,
      recovery_actions: alert_rule.recovery_actions
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
