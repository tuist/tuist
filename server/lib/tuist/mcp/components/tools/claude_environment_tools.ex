defmodule Tuist.MCP.Components.Tools.ClaudeEnvironmentTools do
  @moduledoc false

  alias Tuist.FeatureFlags
  alias Tuist.MCP.Formatter
  alias Tuist.MCP.Tool, as: MCPTool
  alias Tuist.Sandboxes.Anthropic.Federation

  # Environments hold Anthropic credentials and run agent sessions on the
  # account's sandboxes, so, as on the dashboard, every call requires an
  # account administrator and the sandboxes flag.
  def authorize_account(arguments, assigns) do
    with {:ok, account} <- MCPTool.resolve_and_authorize_account(arguments, assigns, :update, :account) do
      if FeatureFlags.sandboxes_enabled?(account),
        do: {:ok, account},
        else: {:error, "Agent sandboxes are not enabled for this account."}
    end
  end

  def environment_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "integer"},
        "anthropic_environment_id" => %{"type" => "string"},
        "name" => %{"type" => ["string", "null"]},
        "platform" => %{"type" => "string", "enum" => ["linux", "darwin"]},
        "vcpus" => %{"type" => "integer"},
        "memory_mb" => %{"type" => "integer"},
        "enabled" => %{"type" => "boolean"},
        "authentication" => %{
          "type" => "string",
          "enum" => ["federation", "api_key", "none"],
          "description" => "The credential Tuist starts agent sessions with."
        },
        "inserted_at" => %{"type" => "string"}
      },
      "required" => [
        "id",
        "anthropic_environment_id",
        "name",
        "platform",
        "vcpus",
        "memory_mb",
        "enabled",
        "authentication",
        "inserted_at"
      ],
      "additionalProperties" => false
    }
  end

  def serialize(agent_environment) do
    %{
      id: agent_environment.id,
      anthropic_environment_id: agent_environment.anthropic_environment_id,
      name: agent_environment.name,
      platform: agent_environment.platform,
      vcpus: agent_environment.vcpus,
      memory_mb: agent_environment.memory_mb,
      enabled: agent_environment.enabled,
      authentication: authentication(agent_environment),
      inserted_at: Formatter.iso8601(agent_environment.inserted_at)
    }
  end

  defp authentication(agent_environment) do
    cond do
      Federation.federated?(agent_environment) -> "federation"
      is_binary(agent_environment.anthropic_api_key) -> "api_key"
      true -> "none"
    end
  end

  def account_handle_property, do: %{"type" => "string", "description" => "The account or organization handle."}
end

defmodule Tuist.MCP.Components.Tools.ListClaudeEnvironments do
  @moduledoc """
  List an account's connected Claude Managed Agents environments.
  """

  use Tuist.MCP.Tool,
    name: "list_claude_environments",
    title: "List Claude Environments",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => Tuist.MCP.Components.Tools.ClaudeEnvironmentTools.account_handle_property()
      },
      "required" => ["account_handle"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "environments" => %{
          "type" => "array",
          "items" => Tuist.MCP.Components.Tools.ClaudeEnvironmentTools.environment_schema()
        },
        "federation_issuer_url" => %{
          "type" => "string",
          "description" => "The account's OpenID Connect issuer to register as a federation issuer in Anthropic."
        },
        "federation_subject_prefix" => %{
          "type" => "string",
          "description" => "The subject prefix a federation rule should match, covering every environment of the account."
        }
      },
      "required" => ["environments", "federation_issuer_url", "federation_subject_prefix"],
      "additionalProperties" => false
    }

  alias Tuist.MCP.Components.Tools.ClaudeEnvironmentTools
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.Anthropic.Federation

  @impl EMCP.Tool
  def description,
    do:
      "List the Claude Managed Agents self-hosted environments connected to an account, whose sessions run in " <>
        "Tuist sandboxes, with the credential each uses. Also returns the issuer URL and subject prefix to trust " <>
        "in an Anthropic workload identity federation rule before connecting with a federated identity. " <>
        "Requires account administrator permission."

  def execute(conn, arguments) do
    with {:ok, account} <- ClaudeEnvironmentTools.authorize_account(arguments, conn.assigns) do
      environments =
        account
        |> Sandboxes.list_agent_environments()
        |> Enum.filter(&(&1.kind == :managed_agents))
        |> Enum.map(&ClaudeEnvironmentTools.serialize/1)

      {:ok,
       %{
         environments: environments,
         federation_issuer_url: Federation.issuer(account.id),
         federation_subject_prefix: "account:#{account.id}:*"
       }}
    end
  end
end

defmodule Tuist.MCP.Components.Tools.ConnectClaudeEnvironment do
  @moduledoc """
  Connect a Claude Managed Agents self-hosted environment to an account.
  """

  use Tuist.MCP.Tool,
    name: "connect_claude_environment",
    title: "Connect Claude Environment",
    read_only_hint: false,
    destructive_hint: false,
    open_world_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => Tuist.MCP.Components.Tools.ClaudeEnvironmentTools.account_handle_property(),
        "environment_id" => %{
          "type" => "string",
          "description" => "The ID of a self-hosted Anthropic environment, `env_...`."
        },
        "environment_key" => %{
          "type" => "string",
          "description" =>
            "Secret. The environment key, which only the Claude Console generates. Only pass a key the user explicitly provided."
        },
        "api_key" => %{
          "type" => "string",
          "description" =>
            "Secret. An Anthropic API key with the developer role in the environment's workspace. Provide it or the four federation IDs."
        },
        "organization_id" => %{"type" => "string", "description" => "Federation: the Anthropic organization ID."},
        "workspace_id" => %{"type" => "string", "description" => "Federation: the environment's workspace ID."},
        "service_account_id" => %{"type" => "string", "description" => "Federation: the service account ID."},
        "federation_rule_id" => %{
          "type" => "string",
          "description" =>
            "Federation: the ID of a rule that trusts the issuer URL and subject prefix from `list_claude_environments` with the workspace:developer scope."
        },
        "platform" => %{
          "type" => "string",
          "enum" => ["linux", "darwin"],
          "description" => "The OS sessions run on by default. Defaults to linux."
        },
        "vcpus" => %{"type" => "integer", "description" => "Sandbox vCPUs, set with memory_mb."},
        "memory_mb" => %{
          "type" => "integer",
          "description" =>
            "Sandbox memory, set with vcpus. Linux: 2x4096, 4x8192 or 8x16384 (default 2x4096); macOS: 8x8192, 8x16384 or 8x24576 (default 8x8192)."
        }
      },
      "required" => ["account_handle", "environment_id", "environment_key"],
      "additionalProperties" => false
    },
    output_schema: Tuist.MCP.Components.Tools.ClaudeEnvironmentTools.environment_schema()

  alias Tuist.MCP.Components.Tools.ClaudeEnvironmentTools
  alias Tuist.Sandboxes
  alias Tuist.Sandboxes.AgentEnvironment
  alias Tuist.Sandboxes.Anthropic.Federation

  @id_arguments %{
    "organization_id" => "anthropic_organization_id",
    "workspace_id" => "anthropic_workspace_id",
    "service_account_id" => "anthropic_service_account_id",
    "federation_rule_id" => "anthropic_federation_rule_id"
  }

  @impl EMCP.Tool
  def description,
    do:
      "Connect a Claude Managed Agents self-hosted environment to an account so its sessions run in Tuist " <>
        "sandboxes, like Settings → Integrations → Claude. Create the environment with Anthropic's API or Console " <>
        "first; only the Claude Console generates its environment key, so ask the user for it. Tuist starts sessions " <>
        "with either an API key or a workload identity federation (the four federation IDs, with a rule that trusts " <>
        "the issuer from `list_claude_environments`), and fetches the environment with it before saving, so a wrong " <>
        "credential or ID fails here. The keys are secrets: only pass ones the user explicitly provided. " <>
        "Never returns credentials. Requires account administrator permission."

  def execute(conn, arguments) do
    with {:ok, account} <- ClaudeEnvironmentTools.authorize_account(arguments, conn.assigns),
         {:ok, credential, credential_attrs} <- credential(arguments),
         attrs =
           Map.merge(credential_attrs, %{
             anthropic_environment_id: String.trim(arguments["environment_id"]),
             environment_key: String.trim(arguments["environment_key"]),
             platform: arguments["platform"],
             vcpus: arguments["vcpus"],
             memory_mb: arguments["memory_mb"]
           }),
         {:ok, agent_environment} <- Sandboxes.connect_managed_agents_environment(account, credential, attrs) do
      {:ok, ClaudeEnvironmentTools.serialize(agent_environment)}
    else
      {:error, message} when is_binary(message) -> {:error, message}
      {:error, %Ecto.Changeset{} = changeset} -> {:error, changeset_message(changeset)}
      {:error, reason} -> {:error, connect_error(arguments, reason)}
    end
  end

  defp credential(arguments) do
    ids = Map.new(@id_arguments, fn {argument, field} -> {field, String.trim(arguments[argument] || "")} end)
    federation? = Enum.any?(ids, fn {_field, value} -> value != "" end)

    case {String.trim(arguments["api_key"] || ""), federation?} do
      {"", false} ->
        {:error, "Provide api_key or the four federation IDs."}

      {api_key, false} ->
        {:ok, {:api_key, api_key}, %{anthropic_api_key: api_key}}

      {"", true} ->
        case ids |> AgentEnvironment.federation_changeset() |> Ecto.Changeset.apply_action(:validate) do
          {:ok, struct} ->
            {:ok, Federation.ids(struct), Map.new(ids, fn {key, value} -> {String.to_existing_atom(key), value} end)}

          {:error, changeset} ->
            {:error, changeset_message(changeset)}
        end

      {_api_key, true} ->
        {:error, "Provide either api_key or the four federation IDs, not both."}
    end
  end

  defp connect_error(_arguments, {:federation_rejected, %{status: 401}}),
    do:
      "Anthropic rejected the federated token. Check that the federation rule trusts the issuer URL and subject " <>
        "prefix from list_claude_environments and names this service account."

  defp connect_error(_arguments, {:federation_rejected, %{message: message}}),
    do: "Anthropic rejected the token exchange: #{message}"

  defp connect_error(_arguments, :not_self_hosted),
    do: "This environment is not self-hosted. Connect a self-hosted environment."

  defp connect_error(%{"api_key" => _}, %{status: 401}), do: "Anthropic rejected the API key."

  defp connect_error(%{"api_key" => _}, %{status: 403}),
    do: "This API key cannot read the environment. Use a key with the developer role in the environment's workspace."

  defp connect_error(_arguments, %{status: 403}),
    do: "Anthropic refused the federated token. Set the federation rule's scope to workspace:developer."

  defp connect_error(_arguments, %{status: 404}),
    do: "Anthropic has no environment with this ID in the credential's workspace."

  defp connect_error(_arguments, %{status: status, message: message}), do: "Anthropic answered #{status}: #{message}"
  defp connect_error(_arguments, _reason), do: "Could not reach Anthropic. Try again."

  defp changeset_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, opts} ->
      Regex.replace(~r/%{(\w+)}/, message, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
    |> Enum.map_join("; ", fn {field, messages} -> "#{argument_name(field)} #{Enum.join(messages, ", ")}" end)
  end

  # Reports a federation id under the argument the agent passed.
  defp argument_name(field) do
    Enum.find_value(@id_arguments, to_string(field), fn {argument, id_field} ->
      if id_field == to_string(field), do: argument
    end)
  end
end
