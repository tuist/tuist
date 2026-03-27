defmodule Noora.HintText do
  @moduledoc """
  Renders hint text with an icon, providing contextual information or validation messages with different variants (default, error, disabled).

  ## Example

  ```elixir
  <.hint_text label="Password must be at least 8 characters" variant="default" />
  ```
  """
  use Phoenix.Component

  alias Noora.Icon

  attr(:label, :string, required: true, doc: "The hint text")

  attr(:variant, :string,
    values: ~w(default destructive disabled),
    default: "default",
    doc: "The variant of the hint text"
  )

  def hint_text(assigns) do
    ~H"""
    <div class="noora-hint-text" data-variant={@variant}>
      <Icon.alert_circle />
      <span>
        {@label}
      </span>
    </div>
    """
  end
end
