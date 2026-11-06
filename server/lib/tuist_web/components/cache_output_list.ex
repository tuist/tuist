defmodule TuistWeb.Components.CacheOutputList do
  @moduledoc false
  use TuistWeb, :html
  use Noora

  attr :id, :string, required: true
  attr :outputs, :list, required: true
  slot :empty_state

  def cache_output_list(assigns) do
    ~H"""
    <div data-part="cas-outputs-list">
      {if @outputs == [], do: render_slot(@empty_state)}
      <div :for={{output, index} <- Enum.with_index(@outputs)} data-part="cas-output-item">
        <span data-part="cas-output-text">
          <span data-part="cas-output-label">{output.label}</span>
          <.popover id={"#{@id}-#{index}-popover"} tabindex="-1" placement="top">
            <:trigger :let={attrs}>
              <span {attrs}>{String.slice(output.key, 0, 40)}</span>
            </:trigger>
            <div data-part="hash-tooltip-content">
              <p data-part="hash-tooltip-text">{output.key}</p>
              <.button
                id={"#{@id}-#{index}-copy"}
                variant="secondary"
                size="small"
                label={dgettext("dashboard_builds", "Copy")}
                phx-hook="Clipboard"
                tabindex="-1"
                data-clipboard-value={output.key}
                phx-click={JS.dispatch("pointerdown", to: "body")}
              >
                <:icon_right><.copy /></:icon_right>
              </.button>
            </div>
          </.popover>
          <span :if={String.length(output.key) > 40} data-part="cas-output-label">...</span>
        </span>
      </div>
    </div>
    """
  end
end
