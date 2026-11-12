defmodule Noora.CheckboxControl do
  @moduledoc false

  use Phoenix.Component

  @doc """
  Renders just the checkbox control without label or hook.
  Used internally by other Noora components like dropdown items and checkbox.

  The control is a 20px box, the line height of medium body text, with the
  16px checkbox centered inside, so it lines up with a label next to it
  without an offset.
  """
  attr(:checked, :boolean, default: false, doc: "Whether the checkbox is checked.")
  attr(:indeterminate, :boolean, default: false, doc: "Whether the checkbox is indeterminate.")
  attr(:rest, :global, doc: "Additional attributes")

  def checkbox_control(assigns) do
    ~H"""
    <div
      class="noora-checkbox-control"
      data-state={
        cond do
          @indeterminate -> "indeterminate"
          @checked -> "checked"
          true -> "unchecked"
        end
      }
      {@rest}
    >
      <div data-part="box">
        <%!-- Drawn on the box's 16px grid, each stroke (caps included)
             centered in it. pathLength lets the CSS draw them along
             their length. --%>
        <svg data-part="check" viewBox="0 0 16 16" fill="none" aria-hidden="true">
          <path
            d="M3 7.75L6.5 11.25L13 4.75"
            pathLength="1"
            stroke="currentColor"
            stroke-width="1.5"
            stroke-linecap="round"
            stroke-linejoin="round"
          />
        </svg>
        <svg data-part="minus" viewBox="0 0 16 16" fill="none" aria-hidden="true">
          <path
            d="M3 8H13"
            pathLength="1"
            stroke="currentColor"
            stroke-width="1.5"
            stroke-linecap="round"
          />
        </svg>
      </div>
    </div>
    """
  end
end
