defmodule TuistWeb.Noora.Label do
  @moduledoc "A label"

  use Phoenix.Component

  attr :label, :string, required: true, doc: "The label"
  attr :sublabel, :string, default: nil, doc: "A sublabel"
  attr :required, :boolean, default: false, doc: "Whether the field is required"

  attr :rest, :global

  def label(assigns) do
    ~H"""
    <div class="noora-label">
      <label {@rest}>
        {@label}
      </label>
      <span :if={@required} class="noora-label__required">*</span>
      <span :if={@sublabel} class="noora-label__sublabel">
        {@sublabel}
      </span>
    </div>
    """
  end
end
