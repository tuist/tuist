defmodule TuistWeb.Marketing.Components.AgentPrompt do
  @moduledoc false
  use Phoenix.Component

  attr :id, :string, required: true
  attr :prompt, :string, required: true
  attr :response, :string, required: true

  def agent_prompt(assigns) do
    ~H"""
    <div id={@id} phx-hook="AgentPrompt">
      <div id="marketing-agent-prompt">
        <div data-part="prompt">
          <div data-part="avatar">You</div>
          <div data-part="prompt-text" data-value={@prompt}>{@prompt}</div>
        </div>
        <div data-part="response-section">
          <div data-part="response-header">Agent</div>
          <div data-part="response-text" data-value={@response}>{@response}</div>
          <div data-part="cursor"></div>
        </div>
      </div>
    </div>
    """
  end
end
