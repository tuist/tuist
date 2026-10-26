defmodule Atlas.MCP.Automation do
  @moduledoc false
  alias Atlas.Automations.Interface
  alias Atlas.MCP.Tool

  defdelegate schema(operation), to: Interface
  defdelegate output_schema(), to: Interface

  def execute(operation, conn, args) do
    case Interface.execute(operation, Tool.current_user(conn), args, interface: "mcp") do
      {:ok, result} -> {:ok, result}
      {:error, %Ecto.Changeset{}} -> {:error, "Invalid automation fields."}
      {:error, error} when is_binary(error) -> {:error, error}
      {:error, error} -> {:error, "Automation action failed: #{error}."}
    end
  end
end
