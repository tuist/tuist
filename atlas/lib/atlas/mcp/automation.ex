defmodule Atlas.MCP.Automation do
  @moduledoc false
  alias Atlas.Automations.Interface
  alias Atlas.MCP.Tool

  defdelegate signal_operation?(operation), to: Interface

  # Slack currently runs as a shared operator, not the person requesting evidence.
  def allowed_context?(%{assigns: %{audit_interface: "slack"}}, operation), do: not signal_operation?(operation)

  def allowed_context?(%{assigns: %{mcp_claims: %{"slack_agent" => _}}}, operation),
    do: not signal_operation?(operation)

  def allowed_context?(_conn, _operation), do: true

  defdelegate schema(operation), to: Interface
  defdelegate output_schema(), to: Interface

  def execute(operation, conn, args) do
    if allowed_context?(conn, operation) do
      execute_authorized(operation, conn, args)
    else
      {:error, "Signal tools require requester-specific authorization and are unavailable in shared Slack sessions."}
    end
  end

  defp execute_authorized(operation, conn, args) do
    case Interface.execute(operation, Tool.current_user(conn), args, interface: "mcp") do
      {:ok, result} -> {:ok, result}
      {:error, %Ecto.Changeset{}} -> {:error, "Invalid automation fields."}
      {:error, error} when is_binary(error) -> {:error, error}
      {:error, error} -> {:error, "Automation action failed: #{error}."}
    end
  end
end
