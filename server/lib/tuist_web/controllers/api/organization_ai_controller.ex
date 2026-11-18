defmodule TuistWeb.API.OrganizationAIController do
  @moduledoc """
  An organization's AI configuration (`Tuist.Accounts.OrganizationAI`): providers,
  models, the default model and task routes, as on its AI settings page. Every
  request needs account administrator permission and the organization's `luft`
  flag, and every write returns the whole configuration. Provider keys are write-only;
  linking a Claude organization happens in the dashboard.
  """
  use OpenApiSpex.ControllerSpecs
  use TuistWeb, :controller

  alias OpenApiSpex.Schema
  alias Tuist.Accounts.OrganizationAI
  alias Tuist.Accounts.OrganizationAI.Schemas
  alias TuistWeb.API.Schemas.Error
  alias TuistWeb.Authentication

  plug(TuistWeb.Plugs.LoaderPlug)

  plug(TuistWeb.Plugs.CastAndValidate,
    json_render_error_v2: true,
    render_error: TuistWeb.RenderAPIErrorPlug
  )

  tags ["Organization AI"]

  @account_parameter [account_handle: [in: :path, type: :string, required: true, description: "The organization handle."]]
  @id_parameter [id: [in: :path, type: :integer, required: true, description: "The record ID."]]

  @responses %{
    ok: {"The organization's AI configuration", "application/json", Schemas.configuration()},
    unauthorized: {"You need to be authenticated to access this resource", "application/json", Error},
    forbidden: {"Only an organization administrator can manage its AI configuration", "application/json", Error},
    not_found: {"The organization, its AI configuration or the record wasn't found", "application/json", Error}
  }

  @write_responses Map.put(
                     @responses,
                     :unprocessable_entity,
                     {"The configuration is invalid", "application/json", Error}
                   )

  operation(:show,
    summary: "Shows an organization's AI configuration",
    description:
      "Lists providers (without keys), models, the default model, task routes and the model each task uses now.",
    operation_id: "getOrganizationAIConfiguration",
    parameters: @account_parameter,
    responses: @responses
  )

  def show(conn, _params), do: respond(conn, OrganizationAI.settings(subject(conn), conn.assigns.selected_account))

  @provider_body %Schema{
    type: :object,
    properties: %{
      name: %Schema{type: :string},
      base_url: %Schema{
        type: :string,
        description:
          "Public HTTPS endpoint for an OpenAI-compatible API, including any /v1 prefix. Requests append /chat/completions."
      },
      api_key: %Schema{
        type: :string,
        description:
          "Stored encrypted and never returned. When updating, omit it to keep the current key, unless the base URL changes."
      }
    }
  }

  operation(:create_provider,
    summary: "Adds an AI provider",
    operation_id: "createOrganizationAIProvider",
    parameters: @account_parameter,
    request_body:
      {"The provider", "application/json", %{@provider_body | required: [:name, :base_url, :api_key]}, required: true},
    responses: @write_responses
  )

  def create_provider(conn, _params), do: write(conn, &OrganizationAI.save_connection/3, provider_attrs(conn, nil))

  operation(:update_provider,
    summary: "Updates an AI provider",
    description:
      "A new key replaces the old one for every model using the provider. Linked Claude organizations can't be edited.",
    operation_id: "updateOrganizationAIProvider",
    parameters: @account_parameter ++ @id_parameter,
    request_body: {"The fields to change", "application/json", @provider_body, required: true},
    responses: @write_responses
  )

  def update_provider(conn, _params),
    do: write(conn, &OrganizationAI.save_connection/3, provider_attrs(conn, conn.params.id))

  operation(:delete_provider,
    summary: "Removes an AI provider",
    description:
      "Deletes its stored key, its models and their task routes. Removing a linked Claude organization first unlinks it at Anthropic. Revoke the key at the provider to revoke access there.",
    operation_id: "deleteOrganizationAIProvider",
    parameters: @account_parameter ++ @id_parameter,
    responses:
      Map.put(@responses, :bad_gateway, {"Anthropic couldn't unlink the Claude organization", "application/json", Error})
  )

  def delete_provider(conn, _params), do: remove(conn, &OrganizationAI.remove_connection/3)

  @model_body %Schema{
    type: :object,
    properties: %{
      name: %Schema{type: :string},
      provider_id: %Schema{type: :integer},
      upstream_model_id: %Schema{
        type: :string,
        description: "The model ID from the provider, unique for the provider."
      }
    }
  }

  operation(:create_model,
    summary: "Adds a model",
    description: "Adding a model never selects it as the default.",
    operation_id: "createOrganizationAIModel",
    parameters: @account_parameter,
    request_body:
      {"The model", "application/json", %{@model_body | required: [:name, :provider_id, :upstream_model_id]},
       required: true},
    responses: @write_responses
  )

  def create_model(conn, _params), do: write(conn, &OrganizationAI.save_model/3, model_attrs(conn, nil))

  operation(:update_model,
    summary: "Updates a model",
    operation_id: "updateOrganizationAIModel",
    parameters: @account_parameter ++ @id_parameter,
    request_body: {"The fields to change", "application/json", @model_body, required: true},
    responses: @write_responses
  )

  def update_model(conn, _params), do: write(conn, &OrganizationAI.save_model/3, model_attrs(conn, conn.params.id))

  operation(:delete_model,
    summary: "Removes a model",
    description:
      "Also removes its task routes, so those tasks fall back to the default model. If no default remains (none was selected, or this was it), every task without a route stops sending requests until a default is selected.",
    operation_id: "deleteOrganizationAIModel",
    parameters: @account_parameter ++ @id_parameter,
    responses: @responses
  )

  def delete_model(conn, _params), do: remove(conn, &OrganizationAI.remove_model/3)

  operation(:set_default_model,
    summary: "Selects the default model",
    description: "Tasks without a route use the default. Null clears it, so only routed tasks send requests.",
    operation_id: "setOrganizationAIDefaultModel",
    parameters: @account_parameter,
    request_body:
      {"The default model", "application/json",
       %Schema{
         type: :object,
         properties: %{model_id: %Schema{type: :integer, nullable: true}},
         required: [:model_id]
       }, required: true},
    responses: @responses
  )

  def set_default_model(%{body_params: body} = conn, _params) do
    respond(
      conn,
      OrganizationAI.set_default(subject(conn), conn.assigns.selected_account, Map.get(body, :model_id))
    )
  end

  @route_body %Schema{
    type: :object,
    properties: %{
      task: Schemas.task_property(),
      model_id: %Schema{type: :integer, description: "The configured model the task uses."}
    }
  }

  operation(:create_task_route,
    summary: "Routes a task to a model",
    description: "A task has at most one route; tasks without one use the default model.",
    operation_id: "createOrganizationAITaskRoute",
    parameters: @account_parameter,
    request_body: {"The route", "application/json", %{@route_body | required: [:task, :model_id]}, required: true},
    responses: @write_responses
  )

  def create_task_route(conn, _params), do: write(conn, &OrganizationAI.save_route/3, route_attrs(conn, nil))

  operation(:update_task_route,
    summary: "Updates a task route",
    operation_id: "updateOrganizationAITaskRoute",
    parameters: @account_parameter ++ @id_parameter,
    request_body: {"The fields to change", "application/json", @route_body, required: true},
    responses: @write_responses
  )

  def update_task_route(conn, _params), do: write(conn, &OrganizationAI.save_route/3, route_attrs(conn, conn.params.id))

  operation(:delete_task_route,
    summary: "Removes a task route",
    description: "The task uses the default model again, or sends no requests without one.",
    operation_id: "deleteOrganizationAITaskRoute",
    parameters: @account_parameter ++ @id_parameter,
    responses: @responses
  )

  def delete_task_route(conn, _params), do: remove(conn, &OrganizationAI.remove_route/3)

  defp provider_attrs(conn, id), do: conn.body_params |> Map.take([:name, :base_url, :api_key]) |> Schemas.attrs(id)

  defp model_attrs(conn, id),
    do: conn.body_params |> Map.take([:name, :provider_id, :upstream_model_id]) |> Schemas.attrs(id)

  defp route_attrs(conn, id), do: conn.body_params |> Map.take([:task, :model_id]) |> Schemas.attrs(id)

  defp write(conn, save, attrs), do: respond(conn, save.(subject(conn), conn.assigns.selected_account, attrs))

  defp remove(conn, remove), do: respond(conn, remove.(subject(conn), conn.assigns.selected_account, conn.params.id))

  # Writes return the whole configuration, read after the write committed.
  defp respond(conn, {:ok, %{connections: _} = configuration}) do
    conn |> put_resp_header("cache-control", "no-store") |> json(Schemas.serialize(configuration))
  end

  defp respond(conn, {:ok, _}), do: respond(conn, OrganizationAI.settings(subject(conn), conn.assigns.selected_account))

  defp respond(conn, {:error, reason}) do
    {status, message} =
      case reason do
        :forbidden -> {:forbidden, "Only an organization administrator can manage its AI configuration."}
        :invalid_configuration -> {:unprocessable_entity, "The configuration is invalid."}
        :unlink_failed -> {:bad_gateway, "Claude couldn't unlink the organization. Try again later."}
        _ -> {:not_found, "Not found."}
      end

    conn |> put_status(status) |> json(%{message: message})
  end

  defp subject(conn), do: Authentication.authenticated_subject(conn)
end
