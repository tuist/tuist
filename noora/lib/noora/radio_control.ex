defmodule Noora.RadioControl do
  @moduledoc false

  use Phoenix.Component

  @doc """
  Renders just the radio control without an input or label.
  Used internally by `Noora.Radio`, and by rows that draw their own option.

  The control is a 20px box, the line height of medium body text, with the
  16px circle centered inside, so it lines up with a label next to it
  without an offset.

  Pass `checked` to set the state yourself. Left out, the control follows
  the radio input rendered right before it.
  """
  attr(:checked, :boolean, default: nil, doc: "Whether the radio is selected.")
  attr(:disabled, :boolean, default: false, doc: "Whether the radio is disabled.")
  attr(:rest, :global, doc: "Additional attributes")

  def radio_control(assigns) do
    ~H"""
    <div
      class="noora-radio-control"
      data-state={
        case @checked do
          nil -> nil
          true -> "checked"
          false -> "unchecked"
        end
      }
      data-disabled={@disabled}
      {@rest}
    >
      <div data-part="circle"></div>
    </div>
    """
  end
end
