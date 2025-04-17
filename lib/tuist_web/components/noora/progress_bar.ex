defmodule TuistWeb.Noora.ProgressBar do
  @moduledoc """
  Progress bar component
  """
  use Phoenix.Component

  import TuistWeb.Noora.Utils

  attr :value, :integer, required: true, doc: "The current value."
  attr :max, :integer, required: true, doc: "Maximum value."
  attr :title, :string, default: nil

  attr :rest, :global

  slot :description

  def progress_bar(assigns) do
    ~H"""
    <div class="noora-progress-bar" {@rest}>
      <div :if={@title} data-part="header">
        <span data-part="title">
          {@title}
        </span>
        <span data-part="value">
          {@value}
        </span>
        <span data-part="max-value">
          {@max}
        </span>
      </div>
      <div data-part="progress-bar">
        <div data-part="max-bar" max={@max} value={@value}></div>
        <div data-part="value-bar" style={"width: #{min((@value / @max) * 100, 100)}%"}></div>
      </div>
      <%= if has_slot_content?(@description, assigns) do %>
        {render_slot(@description)}
      <% end %>
    </div>
    """
  end
end
