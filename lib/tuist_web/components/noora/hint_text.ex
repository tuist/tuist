defmodule TuistWeb.Noora.HintText do
  @moduledoc false
  use Phoenix.Component

  alias TuistWeb.Noora.Icon

  attr :label, :string, required: true, doc: "The hint text"

  attr :variant, :string,
    values: ~w(default error disabled),
    default: "default",
    doc: "The variant of the hint text"

  def hint_text(assigns) do
    ~H"""
    <div class="noora-hint-text" data-variant={@variant}>
      <Icon.alert_circle />
      <span>
        <%= @label %>
      </span>
    </div>
    """
  end
end
