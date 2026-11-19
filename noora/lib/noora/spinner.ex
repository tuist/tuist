defmodule Noora.Spinner do
  @moduledoc """
  A loading spinner: a solid arc that runs around a dim ring of dashes,
  pulling itself up against gravity and dropping through the bottom as if
  yanked by a magnet. Every lap moves differently.

  ```elixir
  <.spinner />
  <.button label="Deploying" disabled>
    <:icon_left><.spinner /></:icon_left>
  </.button>
  ```

  Use it in place of an icon. Inside a button or a badge's icon slot it
  takes that icon's size; elsewhere, its `size`. It follows the text color.
  The `<noora-spinner>` element animates the arc (see `js/Spinner.js`), so it
  needs no id. For people who prefer reduced motion, the arc turns slowly at a
  constant speed.
  """
  use Phoenix.Component

  attr(:size, :string,
    values: [nil | ~w(small medium large)],
    default: nil,
    doc: "12px, 16px, or 20px. Inside a button or a badge, it takes the icon's size instead."
  )

  attr(:label, :string, default: "Loading", doc: "What's loading, announced to screen readers")
  attr(:rest, :global, doc: "Additional HTML attributes")

  def spinner(assigns) do
    ~H"""
    <noora-spinner class="noora-spinner" data-size={@size} role="status" aria-label={@label} {@rest}>
      <svg data-part="track" viewBox="0 0 24 24" aria-hidden="true">
        <circle cx="12" cy="12" r="8" pathLength="100" />
      </svg>
      <svg data-part="arc" viewBox="0 0 24 24" aria-hidden="true">
        <circle cx="12" cy="12" r="8" pathLength="100" />
      </svg>
    </noora-spinner>
    """
  end
end
