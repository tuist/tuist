defmodule TuistWeb.Noora.TextInput do
  @moduledoc """
  Renders text input and digit input components with customizable types, labels, placeholders, prefixes, suffixes, and event handling.
  """
  use Phoenix.Component
  import TuistWeb.Noora.Utils
  import TuistWeb.Noora.Icon
  import TuistWeb.Noora.ShortcutKey
  import TuistWeb.Noora.Tooltip
  import TuistWeb.Noora.Label
  alias Phoenix.LiveView.JS

  attr :id, :string, required: true

  attr :type, :string,
    values: ~w(basic email card_number search password),
    default: "basic",
    doc: "Type of the input"

  attr :label, :string, default: nil, doc: "Label to be rendered in the input."
  attr :sublabel, :string, default: nil, doc: "Sublabel to be rendered in the input."

  attr :suffix_hint, :string,
    default: nil,
    doc:
      "Hint text to show as tooltip at the end of the input. Takes precedence over the suffix set by `type`."

  attr :placeholder, :string, default: nil, doc: "Placeholder text to be rendered in the input."
  attr :required, :boolean, default: false, doc: "Whether the input is required."

  attr :rest, :global

  slot :prefix,
    required: false,
    doc: "Prefix to be rendered in the input. Only shown when type is `basic`."

  slot :suffix,
    required: false,
    doc: "Suffix to be rendered in the input. Takes precedence over `suffix_hint`."

  def text_input(assigns) do
    ~H"""
    <div class="noora-text-input">
      <.label :if={@label} label={@label} sublabel={@sublabel} required={@required} data-part="label" />
      <div data-part="wrapper" data-type={@type}>
        <span :if={@type != "basic" or has_slot_content?(@prefix, assigns)} data-part="prefix">
          <.prefix type={@type} prefix={@prefix} />
        </span>
        <input
          id={@id}
          required={@required}
          type={type(@type)}
          placeholder={if @placeholder, do: @placeholder, else: placeholder(@type)}
          {@rest}
        />
        {# Suffix hint tooltip #}
        <div
          :if={not is_nil(@suffix_hint) and !has_slot_content?(@suffix, assigns)}
          data-part="suffix-hint"
        >
          <.tooltip id={"#{@id}-hint"} title={@suffix_hint}>
            <:trigger :let={attrs}>
              <span {attrs}><.alert_circle /></span>
            </:trigger>
          </.tooltip>
        </div>
        {# Type-based suffix #}
        <div
          :if={
            @type in ~w(card_number search password) and is_nil(@suffix_hint) and
              !has_slot_content?(@suffix, assigns)
          }
          data-part="suffix"
          data-type={@type}
        >
          <.type_suffix type={@type} input_id={@id} />
        </div>
        {# Custom suffix #}
        <span :if={has_slot_content?(@suffix, assigns)} data-part="suffix">
          {render_slot(@suffix)}
        </span>
      </div>
    </div>
    """
  end

  defp type("card_number"), do: "tel"
  defp type("search"), do: "text"
  defp type(type), do: type || "text"

  defp placeholder("password"), do: "• • • • • • • • • •"
  defp placeholder(_), do: nil

  defp prefix(%{type: "basic"} = assigns) do
    ~H"""
    {render_slot(@prefix)}
    """
  end

  defp prefix(%{type: "email"} = assigns) do
    ~H"""
    <.mail />
    """
  end

  defp prefix(%{type: "card_number"} = assigns) do
    ~H"""
    <.credit_card />
    """
  end

  defp prefix(%{type: "search"} = assigns) do
    ~H"""
    <.search />
    """
  end

  defp prefix(%{type: "password"} = assigns) do
    ~H"""
    <.lock_password />
    """
  end

  defp type_suffix(%{type: "card_number"} = assigns) do
    ~H"""
    <.custom_input_credit_card />
    """
  end

  defp type_suffix(%{type: "password"} = assigns) do
    ~H"""
    <button phx-click={JS.toggle_attribute({"type", "password", "text"}, to: "##{@input_id}")}>
      <span class="noora-text-input__password-toggle-text"><.eye /></span>
      <span class="noora-text-input__password-toggle-password"><.eye_off /></span>
    </button>
    """
  end

  defp type_suffix(assigns) do
    ~H"""
    <.shortcut_key size="small">
      ⌘K
    </.shortcut_key>
    """
  end

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
