defmodule TuistWeb.Marketing.Components.SetupPrompt do
  @moduledoc false
  use Phoenix.Component
  use Gettext, backend: TuistWeb.Gettext
  use Noora

  attr :id, :string, required: true

  def setup_prompt(assigns) do
    ~H"""
    <div
      id={@id}
      data-part="setup-prompt"
      data-static-hook="SetupPrompt"
      data-success-message={dgettext("marketing", "Copied! Paste it into your coding agent.")}
      data-error-message={
        dgettext("marketing", "Couldn't copy. Select the prompt and copy it manually.")
      }
    >
      <p id={@id <> "-instructions"} data-part="instructions">
        {dgettext("marketing", "Copy and paste this prompt into your coding agent.")}
      </p>
      <div data-part="prompt-row">
        <code data-part="prompt">
          {dgettext("marketing", "Connect my project to Tuist (https://tuist.dev)")}
        </code>
        <.button
          type="button"
          label={dgettext("marketing", "Copy prompt")}
          data-part="copy"
          aria-describedby={@id <> "-instructions"}
          disabled
        >
          <:icon_left><.copy /></:icon_left>
        </.button>
      </div>
      <p data-part="status" role="status" aria-live="polite" aria-atomic="true"></p>
    </div>
    """
  end
end
