defmodule Tuist.MCP.Tool do
  @moduledoc false

  defmacro __using__(opts) do
    quote do
      @behaviour EMCP.Tool

      alias Tuist.MCP.Components.ToolSupport

      @mcp_tool_name Keyword.fetch!(unquote(opts), :name)
      @mcp_tool_schema Keyword.fetch!(unquote(opts), :schema)

      @impl EMCP.Tool
      def name, do: @mcp_tool_name

      @impl EMCP.Tool
      def input_schema, do: @mcp_tool_schema

      @impl EMCP.Tool
      def call(conn, args) do
        case execute(conn, args) do
          {:ok, data} -> ToolSupport.json_response(data)
          {:error, message} -> EMCP.Tool.error(message)
        end
      end

      defoverridable call: 2
    end
  end
end
