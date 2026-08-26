defmodule Tuist.MCP.Observability do
  @moduledoc false

  alias Tuist.Projects.Project

  def set_project_context(%Project{name: project_handle, account: %{name: account_handle}}) do
    set_context(%{
      mcp_account_handle: account_handle,
      mcp_project_handle: project_handle
    })
  end

  def set_tool_context(tool_name) when is_binary(tool_name) do
    set_context(%{mcp_tool_name: tool_name})
  end

  defp set_context(context) do
    Logger.metadata(context)

    Enum.each(context, fn {key, value} ->
      OpenTelemetry.Tracer.set_attribute(Atom.to_string(key), value)
    end)
  end
end
