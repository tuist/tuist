defmodule Noora.Label do
  @moduledoc """
  Renders a label with an optional sublabel, a required indicator and a help tooltip.

  ## Example

  ```elixir
  <.label label="Email Address" required={true} />
  <.label label="API token" tooltip="Used to read merge requests." tooltip_id="api-token-tooltip" />
  ```
  """

  use Phoenix.Component

  import Noora.Icon
  import Noora.Tooltip

  attr(:label, :string, required: true, doc: "The label")
  attr(:sublabel, :string, default: nil, doc: "A sublabel")
  attr(:required, :boolean, default: false, doc: "Whether the field is required")
  attr(:disabled, :boolean, default: false, doc: "Whether the label is disabled")

  attr(:tooltip, :string,
    default: nil,
    doc: "Help text shown in a tooltip from an icon after the label. Requires `tooltip_id`."
  )

  attr(:tooltip_id, :string, default: nil, doc: "A stable, unique ID for the tooltip")

  attr(:rest, :global, doc: "Additional HTML attributes")

  def label(assigns) do
    ~H"""
    <div class="noora-label" disabled={@disabled}>
      <label {@rest}>
        {@label}
      </label>
      <span :if={@required} data-part="required-indicator">*</span>
      <span :if={@sublabel} data-part="sublabel">
        {@sublabel}
      </span>
      <div :if={@tooltip} data-part="tooltip">
        <.tooltip id={@tooltip_id} title={@tooltip} placement="top-start">
          <:trigger :let={attrs}>
            <span {attrs} tabindex="0" aria-label={@tooltip}><.alert_circle /></span>
          </:trigger>
        </.tooltip>
      </div>
    </div>
    """
  end
end
