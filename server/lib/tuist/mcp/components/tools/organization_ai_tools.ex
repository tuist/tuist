defmodule Tuist.MCP.Components.Tools.OrganizationAITools do
  @moduledoc false

  alias Tuist.Accounts.OrganizationAI
  alias Tuist.Accounts.OrganizationAI.Schemas
  alias Tuist.MCP.Tool, as: MCPTool

  def account_handle_property, do: %{"type" => "string", "description" => "The organization handle."}
  def id_property(description), do: %{"type" => "integer", "description" => description}

  def output_schema, do: MCPTool.json_schema(Schemas.configuration())

  @doc """
  Authorizes account administration as the MCP endpoint does, then runs `operation`
  as the user behind the credential, so `OrganizationAI` applies the same checks
  (administrator, `luft` flag) as the dashboard and the API.
  """
  def run(module, conn, arguments, operation) do
    with :ok <- MCPTool.validate_input(module, arguments),
         {:ok, account} <- MCPTool.resolve_and_authorize_account(arguments, conn.assigns, :update, :account),
         subject = conn.assigns[:current_user] || MCPTool.authenticated_subject(conn.assigns),
         {:ok, result} <- operation.(subject, account),
         {:ok, configuration} <- configuration(result, subject, account) do
      MCPTool.json_response(Schemas.serialize(configuration), module)
    else
      {:error, message} when is_binary(message) -> EMCP.Tool.error(message)
      {:error, reason} -> EMCP.Tool.error(error_message(reason))
    end
  end

  defp configuration(%{connections: _} = configuration, _subject, _account), do: {:ok, configuration}
  defp configuration(_result, subject, account), do: OrganizationAI.settings(subject, account)

  defp error_message(:disabled), do: "AI settings are not available for this organization."
  defp error_message(:forbidden), do: "Only an organization administrator can manage its AI configuration."
  defp error_message(:not_found), do: "Not found. Read the configuration with get_organization_ai_configuration."

  defp error_message(:invalid_configuration),
    do:
      "The configuration is invalid: check required fields, that referenced providers and models belong to the organization, and that a task has only one route."

  defp error_message(:unlink_failed), do: "Claude couldn't unlink the organization. Try again later."
  defp error_message(_reason), do: "The configuration couldn't be changed."
end

defmodule Tuist.MCP.Components.Tools.GetOrganizationAIConfiguration do
  @moduledoc """
  Read an organization's AI providers, models, default model and task routes.
  """

  use Tuist.MCP.Tool,
    name: "get_organization_ai_configuration",
    title: "Get Organization AI Configuration",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => Tuist.MCP.Components.Tools.OrganizationAITools.account_handle_property()
      },
      "required" => ["account_handle"],
      "additionalProperties" => false
    },
    output_schema: Tuist.MCP.Components.Tools.OrganizationAITools.output_schema()

  alias Tuist.Accounts.OrganizationAI
  alias Tuist.MCP.Components.Tools.OrganizationAITools

  @impl EMCP.Tool
  def description,
    do:
      "Read the AI configuration Tuist uses for an organization's server-side AI tasks: providers (keys are never " <>
        "returned), configured models, the default model, task routes, and for every task the model it uses now and " <>
        "whether that comes from its route, the default, or nothing. Requires organization administrator permission."

  @impl EMCP.Tool
  def call(conn, arguments), do: OrganizationAITools.run(__MODULE__, conn, arguments, &OrganizationAI.settings/2)
end

defmodule Tuist.MCP.Components.Tools.RemoveOrganizationAIProvider do
  @moduledoc """
  Remove an organization AI provider with its models and their task routes.
  """

  use Tuist.MCP.Tool,
    name: "remove_organization_ai_provider",
    title: "Remove Organization AI Provider",
    read_only_hint: false,
    destructive_hint: true,
    open_world_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => Tuist.MCP.Components.Tools.OrganizationAITools.account_handle_property(),
        "provider_id" => Tuist.MCP.Components.Tools.OrganizationAITools.id_property("The provider ID.")
      },
      "required" => ["account_handle", "provider_id"],
      "additionalProperties" => false
    },
    output_schema: Tuist.MCP.Components.Tools.OrganizationAITools.output_schema()

  alias Tuist.Accounts.OrganizationAI
  alias Tuist.MCP.Components.Tools.OrganizationAITools

  @impl EMCP.Tool
  def description,
    do:
      "Remove an AI provider from an organization. This deletes its stored key, its models and their task routes; " <>
        "removing a linked Claude organization first unlinks it at Anthropic. Confirm with the user first. Adding or " <>
        "editing a provider takes an API key, so it is done in the dashboard or the REST API, never here. Requires " <>
        "organization administrator permission."

  @impl EMCP.Tool
  def call(conn, arguments) do
    OrganizationAITools.run(__MODULE__, conn, arguments, fn subject, account ->
      OrganizationAI.remove_connection(subject, account, arguments["provider_id"])
    end)
  end
end

defmodule Tuist.MCP.Components.Tools.SaveOrganizationAIModel do
  @moduledoc """
  Add or update an organization AI model.
  """

  use Tuist.MCP.Tool,
    name: "save_organization_ai_model",
    title: "Save Organization AI Model",
    read_only_hint: false,
    destructive_hint: false,
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => Tuist.MCP.Components.Tools.OrganizationAITools.account_handle_property(),
        "id" =>
          Tuist.MCP.Components.Tools.OrganizationAITools.id_property(
            "The model to update. Omit it to add a model, which then needs all other fields."
          ),
        "name" => %{"type" => "string", "description" => "A display name."},
        "provider_id" => Tuist.MCP.Components.Tools.OrganizationAITools.id_property("The provider serving the model."),
        "upstream_model_id" => %{
          "type" => "string",
          "description" => "The model ID requests send to the provider, unique for the provider."
        }
      },
      "required" => ["account_handle"],
      "additionalProperties" => false
    },
    output_schema: Tuist.MCP.Components.Tools.OrganizationAITools.output_schema()

  alias Tuist.Accounts.OrganizationAI
  alias Tuist.Accounts.OrganizationAI.Schemas
  alias Tuist.MCP.Components.Tools.OrganizationAITools

  @impl EMCP.Tool
  def description,
    do:
      "Add a model to an organization's AI configuration, or update one. Adding a model never selects it as the " <>
        "default. Requires organization administrator permission."

  @impl EMCP.Tool
  def call(conn, arguments) do
    attrs = arguments |> Map.take(["name", "provider_id", "upstream_model_id"]) |> Schemas.attrs(arguments["id"])

    OrganizationAITools.run(__MODULE__, conn, arguments, fn subject, account ->
      OrganizationAI.save_model(subject, account, attrs)
    end)
  end
end

defmodule Tuist.MCP.Components.Tools.RemoveOrganizationAIModel do
  @moduledoc """
  Remove an organization AI model and its task routes.
  """

  use Tuist.MCP.Tool,
    name: "remove_organization_ai_model",
    title: "Remove Organization AI Model",
    read_only_hint: false,
    destructive_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => Tuist.MCP.Components.Tools.OrganizationAITools.account_handle_property(),
        "model_id" => Tuist.MCP.Components.Tools.OrganizationAITools.id_property("The configured model ID.")
      },
      "required" => ["account_handle", "model_id"],
      "additionalProperties" => false
    },
    output_schema: Tuist.MCP.Components.Tools.OrganizationAITools.output_schema()

  alias Tuist.Accounts.OrganizationAI
  alias Tuist.MCP.Components.Tools.OrganizationAITools

  @impl EMCP.Tool
  def description,
    do:
      "Remove a configured model, not its provider. Its task routes are removed too, so those tasks fall back to the " <>
        "default model. If no default remains (none was selected, or this was it), every task without a route stops " <>
        "sending requests until a default is selected. " <> "Requires organization administrator permission."

  @impl EMCP.Tool
  def call(conn, arguments) do
    OrganizationAITools.run(__MODULE__, conn, arguments, fn subject, account ->
      OrganizationAI.remove_model(subject, account, arguments["model_id"])
    end)
  end
end

defmodule Tuist.MCP.Components.Tools.SetOrganizationAIDefaultModel do
  @moduledoc """
  Select or clear an organization's default AI model.
  """

  use Tuist.MCP.Tool,
    name: "set_organization_ai_default_model",
    title: "Set Organization AI Default Model",
    read_only_hint: false,
    destructive_hint: false,
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => Tuist.MCP.Components.Tools.OrganizationAITools.account_handle_property(),
        "model_id" => %{
          "type" => ["integer", "null"],
          "description" => "The configured model ID, or null to clear the default."
        }
      },
      "required" => ["account_handle", "model_id"],
      "additionalProperties" => false
    },
    output_schema: Tuist.MCP.Components.Tools.OrganizationAITools.output_schema()

  alias Tuist.Accounts.OrganizationAI
  alias Tuist.MCP.Components.Tools.OrganizationAITools

  @impl EMCP.Tool
  def description,
    do:
      "Select the model an organization's AI tasks use when they have no task route, or clear it with null. Without " <>
        "a default, only routed tasks send requests. Requires organization administrator permission."

  @impl EMCP.Tool
  def call(conn, arguments) do
    OrganizationAITools.run(__MODULE__, conn, arguments, fn subject, account ->
      OrganizationAI.set_default(subject, account, arguments["model_id"])
    end)
  end
end

defmodule Tuist.MCP.Components.Tools.SaveOrganizationAITaskRoute do
  @moduledoc """
  Route an organization AI task to a configured model, or update a route.
  """

  use Tuist.MCP.Tool,
    name: "save_organization_ai_task_route",
    title: "Save Organization AI Task Route",
    read_only_hint: false,
    destructive_hint: false,
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => Tuist.MCP.Components.Tools.OrganizationAITools.account_handle_property(),
        "id" =>
          Tuist.MCP.Components.Tools.OrganizationAITools.id_property(
            "The route to update. Omit it to add a route, which then needs task and model_id."
          ),
        "task" => Tuist.MCP.Tool.json_schema(Tuist.Accounts.OrganizationAI.Schemas.task_property()),
        "model_id" => Tuist.MCP.Components.Tools.OrganizationAITools.id_property("The configured model the task uses.")
      },
      "required" => ["account_handle"],
      "additionalProperties" => false
    },
    output_schema: Tuist.MCP.Components.Tools.OrganizationAITools.output_schema()

  alias Tuist.Accounts.OrganizationAI
  alias Tuist.Accounts.OrganizationAI.Schemas
  alias Tuist.MCP.Components.Tools.OrganizationAITools

  @impl EMCP.Tool
  def description,
    do:
      "Route one of an organization's AI tasks to a configured model, overriding the default model, or change an " <>
        "existing route. A task has at most one route; tasks without one use the default. Requires organization " <>
        "administrator permission."

  @impl EMCP.Tool
  def call(conn, arguments) do
    attrs = arguments |> Map.take(["task", "model_id"]) |> Schemas.attrs(arguments["id"])

    OrganizationAITools.run(__MODULE__, conn, arguments, fn subject, account ->
      OrganizationAI.save_route(subject, account, attrs)
    end)
  end
end

defmodule Tuist.MCP.Components.Tools.RemoveOrganizationAITaskRoute do
  @moduledoc """
  Remove an organization AI task route.
  """

  use Tuist.MCP.Tool,
    name: "remove_organization_ai_task_route",
    title: "Remove Organization AI Task Route",
    read_only_hint: false,
    destructive_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => Tuist.MCP.Components.Tools.OrganizationAITools.account_handle_property(),
        "route_id" => Tuist.MCP.Components.Tools.OrganizationAITools.id_property("The task route ID.")
      },
      "required" => ["account_handle", "route_id"],
      "additionalProperties" => false
    },
    output_schema: Tuist.MCP.Components.Tools.OrganizationAITools.output_schema()

  alias Tuist.Accounts.OrganizationAI
  alias Tuist.MCP.Components.Tools.OrganizationAITools

  @impl EMCP.Tool
  def description,
    do:
      "Remove a task route, so the task uses the default model again, or sends no requests without one. Requires " <>
        "organization administrator permission."

  @impl EMCP.Tool
  def call(conn, arguments) do
    OrganizationAITools.run(__MODULE__, conn, arguments, fn subject, account ->
      OrganizationAI.remove_route(subject, account, arguments["route_id"])
    end)
  end
end
