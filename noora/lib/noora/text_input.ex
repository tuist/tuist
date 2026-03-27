defmodule Noora.TextInput do
  @moduledoc """
  Renders text input and digit input components with customizable types, labels, placeholders, prefixes, suffixes, and event handling.

  ## Example

  ```elixir
  <.text_input name="username" label="Username" placeholder="Enter username" />
  <.text_input type="email" name="email" label="Email" required={true} show_required={true} />
  <.text_input type="password" name="password" label="Password" hint="Must be at least 8 characters" />
  <.text_input type="search" name="search" placeholder="Search..." />

  <.digit_input id="otp-input" characters={6} otp={true} on_complete="verify_otp" />
  ```
  """
  use Phoenix.Component

  import Noora.HintText
  import Noora.Icon
  import Noora.Label
  import Noora.ShortcutKey
  import Noora.Tooltip
  import Noora.Utils

  alias Phoenix.HTML.FormField
  alias Phoenix.LiveView.JS

  attr(:id, :string, required: false)

  attr(:field, FormField, doc: "A Phoenix form field")

  attr(:type, :string,
    values: ~w(basic email card_number search password),
    default: "basic",
    doc: "Type of the input"
  )

  attr(:input_type, :string, default: "text", doc: "HTML input type when type is `basic`.")

  attr(:label, :string, default: nil, doc: "Label to be rendered in the input.")
  attr(:sublabel, :string, default: nil, doc: "Sublabel to be rendered in the input.")
  attr(:hint, :string, default: nil, doc: "Hint text to be rendered below the input.")
  attr(:hint_variant, :string, default: "default", doc: "Hint text variant.")

  attr(:error, :string, doc: "Errors to be rendered below the input. Takes precedence over `hint`.")

  attr(:show_error_message, :boolean,
    default: true,
    doc: "Whether to show the error message below the input."
  )

  attr(:show_prefix, :boolean,
    default: true,
    doc: "Whether to show the prefix."
  )

  attr(:show_suffix, :boolean,
    default: true,
    doc: "Whether to show the suffix."
  )

  attr(:suffix_hint, :string,
    default: nil,
    doc: "Hint text to show as tooltip at the end of the input. Takes precedence over the suffix set by `type`."
  )

  attr(:name, :string, doc: "The name of the input")
  attr(:value, :string, doc: "The value of the input")
  attr(:placeholder, :string, default: nil, doc: "Placeholder text to be rendered in the input.")
  attr(:required, :boolean, default: false, doc: "Whether the input is required.")
  attr(:show_required, :boolean, default: false, doc: "Whether the required indicator is shown.")
  attr(:min, :any, default: nil, doc: "Minimum value for number inputs.")
  attr(:max, :any, default: nil, doc: "Maximum value for number inputs.")
  attr(:step, :any, default: nil, doc: "Step value for number inputs.")

  attr(:disabled, :boolean, default: false, doc: "Whether the input is disabled.")

  attr(:rest, :global)

  slot(:prefix,
    required: false,
    doc: "Prefix to be rendered in the input. Only shown when type is `basic`."
  )

  slot(:suffix,
    required: false,
    doc: "Suffix to be rendered in the input. Takes precedence over `suffix_hint`."
  )

  def text_input(%{field: %FormField{} = field} = assigns) do
    assigns
    |> assign(field: nil, id: Map.get(assigns, :id, field.id))
    |> assign_new(:name, fn -> field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> assign_new(:error, fn ->
      field.errors |> Enum.map(fn {message, _opts} -> message end) |> List.first()
    end)
    |> text_input()
  end

  def text_input(assigns) do
    assigns =
      assigns
      |> assign_new(:value, fn -> "" end)
      |> assign_new(:error, fn -> nil end)
      |> assign_new(:id, fn -> "text-input-#{System.unique_integer([:positive])}" end)

    ~H"""
    <div class="noora-text-input">
      <.label
        :if={@label}
        label={@label}
        sublabel={@sublabel}
        required={@required and @show_required}
        disabled={@disabled}
        data-part="label"
      />
      <div
        data-part="wrapper"
        data-type={@type}
        data-error={@error}
        phx-click={JS.focus(to: "##{@id}")}
      >
        <span
          :if={(@show_prefix and @type != "basic") or has_slot_content?(@prefix, assigns)}
          data-part="prefix"
        >
          <.prefix type={@type} prefix={@prefix} />
        </span>
        <input
          id={@id}
          name={@name}
          value={@value}
          type={type(@type, @input_type)}
          required={@required}
          placeholder={if @placeholder, do: @placeholder, else: placeholder(@type)}
          min={@min}
          max={@max}
          step={@step}
          disabled={@disabled}
          {@rest}
        />
        {# Suffix hint tooltip #}
        <div
          :if={@show_suffix and not is_nil(@suffix_hint) and !has_slot_content?(@suffix, assigns)}
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
            @show_suffix and @type in ~w(card_number search password) and is_nil(@suffix_hint) and
              !has_slot_content?(@suffix, assigns)
          }
          data-part="suffix"
          data-type={@type}
        >
          <.type_suffix type={type(@type, @input_type)} input_id={@id} />
        </div>
        {# Custom suffix #}
        <span :if={@show_suffix and has_slot_content?(@suffix, assigns)} data-part="suffix">
          {render_slot(@suffix)}
        </span>
      </div>
      <.hint_text :if={!is_nil(@error) and @show_error_message} label={@error} variant="destructive" />
      <.hint_text :if={is_nil(@error) and @hint} label={@hint} variant={@hint_variant} />
    </div>
    """
  end

  defp type("card_number", _input_type), do: "tel"
  defp type("search", _input_type), do: "text"
  defp type(_type, input_type), do: input_type || "text"

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
    <button
      phx-click={JS.toggle_attribute({"type", "password", "text"}, to: "##{@input_id}")}
      type="button"
      tabindex="-1"
    >
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

  attr(:id, :string, required: true)

  attr(:type, :string, values: ["alphanumeric", "numeric", "alphabetic"], default: "numeric")
  attr(:characters, :integer, required: true, doc: "The number of characters in the input")
  attr(:placeholder, :string, default: nil)
  attr(:otp, :boolean, default: false)
  attr(:error, :boolean, default: false)
  attr(:disabled, :boolean, default: false)

  attr(:on_change, :string,
    default: nil,
    doc: "Event handler for when the input changes. Triggers the event with value `{ value: string[],
    valueAsString: string }`"
  )

  attr(:on_complete, :string,
    default: nil,
    doc: "Event handler for when the input is complete. Triggers the event with value `{ value: string[],
    valueAsString: string }`"
  )

  attr(:on_invalid, :string,
    default: nil,
    doc: "Event handler for when the input is invalid. Triggers the event with value `{ value: string[],
    valueAsString: string }`"
  )

  attr(:rest, :global)

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
