defmodule Tuist.MCP.Observability do
  @moduledoc false

  alias Tuist.Projects.Project

  @opentelemetry_attribute_names %{
    mcp_account_handle: "mcp.account.handle",
    mcp_project_handle: "mcp.project.handle",
    mcp_tool_name: "mcp.tool.name"
  }

  def set_project_context(%Project{name: project_handle, account: %{name: account_handle}}) do
    set_context(%{
      mcp_account_handle: account_handle,
      mcp_project_handle: project_handle
    })
  end

  def set_project_context(%Project{}), do: :ok

  def set_tool_context(tool_name) when is_binary(tool_name) do
    set_context(%{mcp_tool_name: tool_name})
  end

  defp set_context(context) do
    Logger.metadata(context)

    Enum.each(context, fn {key, value} ->
      OpenTelemetry.Tracer.set_attribute(Map.fetch!(@opentelemetry_attribute_names, key), value)
    end)
  end
end
