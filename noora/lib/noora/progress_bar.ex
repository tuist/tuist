defmodule Noora.ProgressBar do
  @moduledoc """
  Progress bar component

  ## Example

  ```elixir
  <.progress_bar value={75} max={100} title="Upload Progress" />
  ```
  """
  use Phoenix.Component

  import Noora.Utils

  attr(:value, :integer, required: true, doc: "The current value.")
  attr(:max, :integer, required: true, doc: "Maximum value.")
  attr(:title, :string, default: nil, doc: "The title of the progress bar")

  attr(:value_label, :string,
    default: nil,
    doc: """
    Text to show in place of `value`. The bar still measures itself with
    `value`, so this is for presentation only: formatting a large count
    for the reader without making the geometry depend on a string.
    """
  )

  attr(:max_label, :string, default: nil, doc: "Text to show in place of `max`. See `value_label`.")

  attr(:rest, :global)

  slot(:description)

  def progress_bar(assigns) do
    ~H"""
    <div class="noora-progress-bar" {@rest}>
      <div :if={@title} data-part="header">
        <span data-part="title">
          {@title}
        </span>
        <span data-part="value">
          {@value_label || @value}
        </span>
        <span data-part="max-value">
          {@max_label || @max}
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
