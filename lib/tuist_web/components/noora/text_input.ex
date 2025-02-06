defmodule TuistWeb.Noora.TextInput do
  @moduledoc false
  use Phoenix.Component

  attr :id, :string, required: true

  attr :type, :string, values: ["alphanumeric", "numeric", "alphabetic"], default: "numeric"
  attr :characters, :integer, required: true, doc: "The number of characters in the input"
  attr :placeholder, :string, default: nil
  attr :otp, :boolean, default: false
  attr :error, :boolean, default: false
  attr :disabled, :boolean, default: false

  attr :on_change, :string,
    default: nil,
    doc:
      "Event handler for when the input changes. Triggers the event with value `{ value: string[],
    valueAsString: string }`"

  attr :on_complete, :string,
    default: nil,
    doc:
      "Event handler for when the input is complete. Triggers the event with value `{ value: string[],
    valueAsString: string }`"

  attr :on_invalid, :string,
    default: nil,
    doc:
      "Event handler for when the input is invalid. Triggers the event with value `{ value: string[],
    valueAsString: string }`"

  attr :rest, :global

  def digit_input(assigns) do
    ~H"""
    <div
      id={@id}
      class="noora-digit-input"
      phx-hook="NooraDigitInput"
      data-type={@type}
      data-placeholder={@placeholder}
      data-otp={@otp}
      data-disabled={@disabled}
      data-blur-on-complete
      data-on-change={@on_change}
      data-on-complete={@on_complete}
      data-on-invalid={@on_invalid}
      {@rest}
    >
      <div data-part="root">
        <input
          :for={index <- 0..(@characters - 1)}
          data-part="input"
          data-index={index}
          data-error={@error}
        />
      </div>
    </div>
    """
  end
end
