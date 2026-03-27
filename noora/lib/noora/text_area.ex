defmodule Noora.TextArea do
  @moduledoc """
  Renders textarea components with customizable labels, placeholders, character counting, and event handling.

  ## Example

  ```elixir
  <.text_area name="description" label="Description" placeholder="Enter description" />
  <.text_area name="message" label="Message" required={true} show_required={true} />
  <.text_area name="notes" label="Notes" hint="Additional information" />
  <.text_area name="content" label="Content" max_length={500} />
  ```
  """
  use Phoenix.Component

  import Noora.HintText
  import Noora.Label

  alias Phoenix.HTML.FormField
  alias Phoenix.LiveView.JS

  attr(:id, :string, required: false)

  attr(:field, FormField, doc: "A Phoenix form field")

  attr(:label, :string, default: nil, doc: "Label to be rendered above the textarea.")
  attr(:sublabel, :string, default: nil, doc: "Sublabel to be rendered above the textarea.")
  attr(:hint, :string, default: nil, doc: "Hint text to be rendered below the textarea.")
  attr(:hint_variant, :string, default: "default", doc: "Hint text variant.")

  attr(:error, :string, doc: "Errors to be rendered below the textarea. Takes precedence over `hint`.")

  attr(:show_error_message, :boolean,
    default: true,
    doc: "Whether to show the error message below the textarea."
  )

  attr(:name, :string, doc: "The name of the textarea")
  attr(:value, :string, doc: "The value of the textarea")
  attr(:placeholder, :string, default: nil, doc: "Placeholder text to be rendered in the textarea.")
  attr(:required, :boolean, default: false, doc: "Whether the textarea is required.")
  attr(:show_required, :boolean, default: false, doc: "Whether the required indicator is shown.")

  attr(:rows, :integer, default: 4, doc: "Number of visible text lines for the textarea.")
  attr(:max_length, :integer, default: 200, doc: "Maximum number of characters allowed.")
  attr(:show_character_count, :boolean, default: true, doc: "Whether to show the character count.")

  attr(:resize, :string,
    values: ~w(none both horizontal vertical),
    default: "vertical",
    doc: "CSS resize property for the textarea."
  )

  attr(:disabled, :boolean, default: false, doc: "Whether the textarea is disabled.")

  attr(:rest, :global)

  def text_area(%{field: %FormField{} = field} = assigns) do
    assigns
    |> assign(field: nil, id: Map.get(assigns, :id, field.id))
    |> assign_new(:name, fn -> field.name end)
    |> assign_new(:value, fn -> field.value end)
    |> assign_new(:error, fn ->
      field.errors |> Enum.map(fn {message, _opts} -> message end) |> List.first()
    end)
    |> text_area()
  end

  def text_area(assigns) do
    assigns =
      assigns
      |> assign_new(:value, fn -> "" end)
      |> assign_new(:error, fn -> nil end)
      |> assign_new(:id, fn -> "text-area-#{System.unique_integer([:positive])}" end)

    character_count = String.length(assigns.value || "")
    resize = if assigns.disabled, do: "none", else: assigns.resize

    assigns =
      assigns
      |> assign(:character_count, character_count)
      |> assign(:resize, resize)

    ~H"""
    <div class="noora-text-area" data-error={@error} disabled={@disabled}>
      <.label
        :if={@label}
        label={@label}
        sublabel={@sublabel}
        required={@required and @show_required}
        disabled={@disabled}
        data-part="label"
      />
      <div data-part="wrapper" phx-click={JS.focus(to: "##{@id}")}>
        <textarea
          id={@id}
          name={@name}
          rows={@rows}
          required={@required}
          placeholder={@placeholder}
          maxlength={@max_length}
          style={"resize: #{@resize}"}
          disabled={@disabled}
          {@rest}
        >{@value}</textarea>
        <span :if={@show_character_count && !@disabled} data-part="character-count">
          {@character_count}/{@max_length}
        </span>
      </div>

      <.hint_text :if={!is_nil(@error) and @show_error_message} label={@error} variant="destructive" />
      <.hint_text :if={is_nil(@error) and @hint} label={@hint} variant={@hint_variant} />
    </div>
    """
  end
end
