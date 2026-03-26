defmodule TuistWeb.Marketing.Components.AgentPrompt do
  @moduledoc false
  use Phoenix.Component
  use Noora

  attr :id, :string, required: true
  attr :title, :string, default: "bash"
  attr :prompt, :string, required: true
  attr :response, :any, required: true
  attr :action, :string, required: true
  attr :current_user, :any, default: nil

  def agent_prompt(assigns) do
    shell_prompt = shell_prompt(assigns.current_user)

    assigns =
      assigns
      |> assign(:response_steps_json, JSON.encode!(normalize_response_steps(assigns.response)))
      |> assign(:shell_prompt, shell_prompt)

    ~H"""
    <div
      id={"agent_prompt_window-" <> @id}
      phx-hook="AgentPrompt"
      phx-update="ignore"
    >
      <div data-part="bar">
        <div data-part="language">{@title}</div>
      </div>
      <div data-part="code">
        <div data-part="terminal-line">
          <span data-part="shell-prompt">{@shell_prompt}</span>{" "}<span
            data-part="prompt-text"
            data-value={@prompt}
          ></span><span
            data-part="prompt-cursor"
            style="visibility: hidden;"
          >
          </span>
        </div>
        <div data-part="trigger-container">
          <.button
            label={@action}
            variant="primary"
            size="medium"
            data-part="trigger"
            id={@id <> "-trigger"}
          >
            <:icon_left><.player_play /></:icon_left>
          </.button>
        </div>
        <div data-part="response-section" data-response-steps={@response_steps_json}>
          <span data-part="response-text"></span><span
            data-part="response-cursor"
            style="visibility: hidden;"
          ></span>
        </div>
      </div>
    </div>
    """
  end

  defp normalize_response_steps(response) when is_binary(response), do: [normalize_response_step(response)]
  defp normalize_response_steps(response) when is_list(response), do: Enum.map(response, &normalize_response_step/1)

  defp normalize_response_step(step) when is_binary(step), do: %{text: step, wait_ms: 0}

  defp normalize_response_step({text, wait_ms}) when is_binary(text) and is_integer(wait_ms) and wait_ms >= 0 do
    %{text: text, wait_ms: wait_ms}
  end

  defp shell_prompt(%{account: %{name: handle}}) when is_binary(handle) and handle != "" do
    "#{handle}@tuist:~$"
  end

  defp shell_prompt(_current_user), do: "~$"
end
