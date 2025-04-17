defmodule TuistWeb.Noora.Modal do
  @moduledoc """
  Renders a modal component with customizable headers, content, and footers, supporting various header types, sizes, and event handling.
  """

  use Phoenix.Component

  import TuistWeb.Noora.DismissIcon
  import TuistWeb.Noora.Icon
  import TuistWeb.Noora.Utils

  attr :id, :string, required: true, doc: "The modal's unique identifier."

  attr :title, :string, default: nil, doc: "Title of the modal"

  attr :description, :string,
    default: nil,
    doc: "Description of the modal. Only visible when header_size is 'large'"

  attr :header_type, :string,
    values: ~w(default icon success info warning error),
    default: "default",
    doc: "Type of the header"

  attr :header_size, :string, values: ~w(small large), default: "large", doc: "Size of the header"
  attr :on_dismiss, :string, default: nil, doc: "Event to emit when the dismiss icon is clicked."

  attr :on_open_change, :string,
    default: nil,
    doc: "An optional event to fire when the modal is opened or closed."

  slot :trigger,
    required: true,
    doc: "The modal's trigger. Should be a button that accepts the attributes provided by the slot."

  slot :header_icon, doc: "Icon to be rendered in the header when type is 'icon'"
  slot :header_button
  slot :footer, required: false, doc: "The modal's footer element."
  slot :inner_block

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      class="noora-modal"
      phx-hook="NooraModal"
      data-close-on-escape
      data-close-on-interact-outside
      data-on-open-change={@on_open_change}
    >
      {render_slot(@trigger, %{"data-part" => "trigger"})}
      <div data-part="backdrop"></div>
      <div data-part="positioner">
        <div data-part="content">
          <.modal_header
            :if={@title}
            title={@title}
            description={@description}
            type={@header_type}
            size={@header_size}
            on_dismiss={@on_dismiss}
          >
            <:header_button>{render_slot(@header_button)}</:header_button>
            {render_slot(@header_icon)}
          </.modal_header>
          <div data-part="body">{render_slot(@inner_block)}</div>
          <div :if={has_slot_content?(@footer, assigns)}>{render_slot(@footer)}</div>
        </div>
      </div>
    </div>
    """
  end

  attr :title, :string, required: true, doc: "Title of the modal"

  attr :description, :string,
    default: nil,
    doc: "Description of the modal. Only visible when size is 'large'"

  attr :type, :string,
    values: ~w(default icon success info warning error),
    default: "default",
    doc: "Type of the header"

  attr :size, :string, values: ~w(small large), default: "large", doc: "Size of the header"

  attr :on_dismiss, :string, default: nil, doc: "Event to emit when the dismiss icon is clicked."

  slot :inner_block, doc: "Icon to be rendered in the header when type is 'icon'"
  slot :header_button

  defp modal_header(assigns) do
    ~H"""
    <div data-part="header" data-type={@type} data-size={@size}>
      <.modal_header_icon :if={@type != "default"} type={@type}>
        {render_slot(@inner_block)}
      </.modal_header_icon>
      <div data-part="header-content">
        <div data-part="row">
          <span data-part="title">{@title}</span>
          <%= if not has_slot_content?(@header_button, assigns) do %>
            <.dismiss_icon data-part="close-trigger" phx-click={@on_dismiss} />
          <% end %>
        </div>
        <div :if={@size == "large"} data-part="description">
          {@description}
        </div>
      </div>
      <%= if has_slot_content?(@header_button, assigns) do %>
        {render_slot(@header_button)}
      <% end %>
    </div>
    """
  end

  defp modal_header_icon(%{type: "icon"} = assigns) do
    ~H"""
    <div data-part="icon">
      {render_slot(@inner_block)}
    </div>
    """
  end

  defp modal_header_icon(%{type: type} = assigns) when type in ["error", "information"] do
    ~H"""
    <div data-part="icon">
      <.alert_circle />
    </div>
    """
  end

  defp modal_header_icon(%{type: "success"} = assigns) do
    ~H"""
    <div data-part="icon">
      <.circle_check />
    </div>
    """
  end

  defp modal_header_icon(%{type: "warning"} = assigns) do
    ~H"""
    <div data-part="icon">
      <.alert_triangle />
    </div>
    """
  end

  attr :type, :string, values: ~w(default stretch), default: "default", doc: "Type of the footer"
  slot :action, doc: "Actions to be rendered in the footer"
  slot :inner_block

  def modal_footer(assigns) do
    ~H"""
    <div data-part="footer" data-type={@type}>
      <div :if={@type == "default"}>
        {render_slot(@inner_block)}
      </div>
      <div data-part="actions">
        <div :for={action <- @action}>
          {render_slot(action)}
        </div>
      </div>
    </div>
    """
  end
end
