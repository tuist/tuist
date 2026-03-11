defmodule Tuist.MCP.Prompt do
  @moduledoc false

  defmacro __using__(opts) do
    quote do
      @behaviour EMCP.Prompt

      alias Tuist.MCP.Components.PromptSupport

      @mcp_prompt_name Keyword.fetch!(unquote(opts), :name)
      @mcp_prompt_arguments Keyword.fetch!(unquote(opts), :arguments)

      @impl EMCP.Prompt
      def name, do: @mcp_prompt_name

      @impl EMCP.Prompt
      def arguments, do: @mcp_prompt_arguments
    end
  end

  def message(text) do
    %{role: "user", content: %{type: "text", text: text}}
  end
end
