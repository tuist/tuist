defmodule Noora.Label do
  @moduledoc """
  Renders a label with an optional sublabel and a required indicator.

  ## Example

  ```elixir
  <.label label="Email Address" required={true} />
  ```
  """

  use Phoenix.Component

  attr(:label, :string, required: true, doc: "The label")
  attr(:sublabel, :string, default: nil, doc: "A sublabel")
  attr(:required, :boolean, default: false, doc: "Whether the field is required")
  attr(:disabled, :boolean, default: false, doc: "Whether the label is disabled")

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
    </div>
    """
  end
end
