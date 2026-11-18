defmodule Tuist.MCP.Components.Tools.AmpWorkspaceTools do
  @moduledoc false

  alias Tuist.MCP.Formatter
  alias Tuist.MCP.Tool, as: MCPTool

  # Connections grant CI access to the whole account, so reading them requires
  # the same account administration permission as the dashboard.
  def authorize_account(arguments, assigns),
    do: MCPTool.resolve_and_authorize_account(arguments, assigns, :update, :account)

  def connection_schema do
    %{
      "type" => "object",
      "properties" => %{
        "id" => %{"type" => "integer"},
        "workspace_id" => %{"type" => "string"},
        "project_id" => %{"type" => ["string", "null"]},
        "inserted_at" => %{"type" => "string"}
      },
      "required" => ["id", "workspace_id", "project_id", "inserted_at"],
      "additionalProperties" => false
    }
  end

  def serialize(connection) do
    %{
      id: connection.id,
      workspace_id: connection.workspace_id,
      project_id: connection.project_id,
      inserted_at: Formatter.iso8601(connection.inserted_at)
    }
  end

  def account_handle_property, do: %{"type" => "string", "description" => "The account or organization handle."}
end

defmodule Tuist.MCP.Components.Tools.ListAmpWorkspaceConnections do
  @moduledoc """
  List the Amp workspaces whose orbs can sign in to an account.
  """

  use Tuist.MCP.Tool,
    name: "list_amp_workspace_connections",
    title: "List Amp Workspace Connections",
    read_only_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => Tuist.MCP.Components.Tools.AmpWorkspaceTools.account_handle_property()
      },
      "required" => ["account_handle"],
      "additionalProperties" => false
    },
    output_schema: %{
      "type" => "object",
      "properties" => %{
        "connections" => %{
          "type" => "array",
          "items" => Tuist.MCP.Components.Tools.AmpWorkspaceTools.connection_schema()
        }
      },
      "required" => ["connections"],
      "additionalProperties" => false
    }

  alias Tuist.Accounts
  alias Tuist.MCP.Components.Tools.AmpWorkspaceTools
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description,
    do:
      "List the Amp workspaces connected to an account. Orbs of a connected workspace (or, when a connection names " <>
        "a project ID, of that Amp project) sign in with `tuist auth login` and get CI access to every project in the " <>
        "account. Requires account administrator permission."

  @impl EMCP.Tool
  def call(conn, arguments) do
    with :ok <- MCPTool.validate_input(__MODULE__, arguments),
         {:ok, account} <- AmpWorkspaceTools.authorize_account(arguments, conn.assigns) do
      connections = account |> Accounts.list_amp_workspace_connections() |> Enum.map(&AmpWorkspaceTools.serialize/1)
      MCPTool.json_response(%{connections: connections}, __MODULE__)
    else
      {:error, message} -> EMCP.Tool.error(message)
    end
  end
end

defmodule Tuist.MCP.Components.Tools.ConnectAmpWorkspace do
  @moduledoc """
  Connect an Amp workspace, optionally limited to one Amp project, to an account.
  """

  use Tuist.MCP.Tool,
    name: "connect_amp_workspace",
    title: "Connect Amp Workspace",
    read_only_hint: false,
    destructive_hint: false,
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => Tuist.MCP.Components.Tools.AmpWorkspaceTools.account_handle_property(),
        "workspace_id" => %{
          "type" => "string",
          "description" => "The Amp workspace ID, a UUID. In an orb of the workspace it is `$AMP_WORKSPACE_ID`."
        },
        "project_id" => %{
          "type" => "string",
          "description" =>
            "Optional Amp project ID, a UUID (`$AMP_PROJECT_ID` in an orb). When set, only orbs of that Amp project can sign in. Omit it to admit every orb of the workspace."
        }
      },
      "required" => ["account_handle", "workspace_id"],
      "additionalProperties" => false
    },
    output_schema: Tuist.MCP.Components.Tools.AmpWorkspaceTools.connection_schema()

  alias Tuist.Accounts
  alias Tuist.MCP.Components.Tools.AmpWorkspaceTools
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description,
    do:
      "Connect an Amp workspace to an account so its orbs can run `tuist auth login` without a stored token. " <>
        "Every orb the connection admits gets CI access, including cache uploads, to all current and future projects " <>
        "in the account, so confirm with the user before connecting. Tuist can't verify that the user belongs to the " <>
        "workspace. A workspace can be connected to an account once; disconnect it first to change its project. " <>
        "Requires account administrator permission."

  @impl EMCP.Tool
  def call(conn, arguments) do
    with :ok <- MCPTool.validate_input(__MODULE__, arguments),
         {:ok, account} <- AmpWorkspaceTools.authorize_account(arguments, conn.assigns),
         {:ok, connection} <-
           Accounts.create_amp_workspace_connection(account, Map.take(arguments, ["workspace_id", "project_id"])) do
      MCPTool.json_response(AmpWorkspaceTools.serialize(connection), __MODULE__)
    else
      {:error, %Ecto.Changeset{} = changeset} -> EMCP.Tool.error(error_message(changeset))
      {:error, message} -> EMCP.Tool.error(message)
    end
  end

  defp error_message(changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.map_join("; ", fn {field, messages} -> "#{field} #{Enum.join(messages, ", ")}" end)
  end
end

defmodule Tuist.MCP.Components.Tools.DisconnectAmpWorkspace do
  @moduledoc """
  Remove an Amp workspace connection from an account.
  """

  use Tuist.MCP.Tool,
    name: "disconnect_amp_workspace",
    title: "Disconnect Amp Workspace",
    read_only_hint: false,
    destructive_hint: true,
    schema: %{
      "type" => "object",
      "properties" => %{
        "account_handle" => Tuist.MCP.Components.Tools.AmpWorkspaceTools.account_handle_property(),
        "connection_id" => %{
          "type" => "integer",
          "description" => "The connection ID from `list_amp_workspace_connections`."
        }
      },
      "required" => ["account_handle", "connection_id"],
      "additionalProperties" => false
    },
    output_schema: Tuist.MCP.Components.Tools.AmpWorkspaceTools.connection_schema()

  alias Tuist.Accounts
  alias Tuist.MCP.Components.Tools.AmpWorkspaceTools
  alias Tuist.MCP.Tool, as: MCPTool

  @impl EMCP.Tool
  def description,
    do:
      "Disconnect an Amp workspace from an account. Its orbs can no longer sign in; sessions they already have " <>
        "stay valid until they expire within an hour. Requires account administrator permission."

  @impl EMCP.Tool
  def call(conn, %{"connection_id" => connection_id} = arguments) do
    with :ok <- MCPTool.validate_input(__MODULE__, arguments),
         {:ok, account} <- AmpWorkspaceTools.authorize_account(arguments, conn.assigns),
         {:ok, connection} <- Accounts.delete_amp_workspace_connection(account, connection_id) do
      MCPTool.json_response(AmpWorkspaceTools.serialize(connection), __MODULE__)
    else
      {:error, :not_found} -> EMCP.Tool.error("Amp workspace connection not found: #{connection_id}")
      {:error, message} when is_binary(message) -> EMCP.Tool.error(message)
      {:error, other} -> EMCP.Tool.error(inspect(other))
    end
  end

  def call(_conn, _arguments), do: EMCP.Tool.error("Provide account_handle and connection_id.")
end
