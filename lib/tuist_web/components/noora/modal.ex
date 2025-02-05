defmodule TuistWeb.Noora.Modal do
  @moduledoc false

  use Phoenix.Component
  import TuistWeb.Noora.Utils
  import TuistWeb.Noora.DismissIcon
  alias TuistWeb.Noora.Icon

  attr :id, :string, required: true, doc: "The modal's unique identifier."

  attr :title, :string, required: true, doc: "Title of the modal"

  attr :description, :string,
    default: nil,
    doc: "Description of the modal. Only visible when header_size is 'large'"

  attr :header_type, :string,
    values: ~w(default icon success info warning error),
    default: "default",
    doc: "Type of the header"

  attr :header_size, :string, values: ~w(small large), default: "large", doc: "Size of the header"

  attr :on_open_change, :string,
    default: nil,
    doc: "An optional event to fire when the modal is opened or closed."

  slot :trigger,
    required: true,
    doc:
      "The modal's trigger. Should be a button that accepts the attributes provided by the slot."

  slot :header_icon, doc: "Icon to be rendered in the header when type is 'icon'"
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
            title={@title}
            description={@description}
            type={@header_type}
            size={@header_size}
            icon={@header_icon}
          />
          <div class="noora-modal__content">{render_slot(@inner_block)}</div>
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

  slot :icon, doc: "Icon to be rendered in the header when type is 'icon'"

  defp modal_header(assigns) do
    ~H"""
    <div class="noora-modal__header" data-type={@type} data-size={@size}>
      <.modal_header_icon :if={@type != "default"} type={@type} icon={@icon} />
      <div class="noora-modal__header-content">
        <div class="noora-modal__header-row">
          <span data-part="title">{@title}</span>
          <.dismiss_icon data-part="close-trigger" />
        </div>

        <div :if={@size == "large"} data-part="description">
          {@description}
        </div>
      </div>
    </div>
    """
  end

  defp modal_header_icon(%{type: "icon"} = assigns) do
    ~H"""
    <div class="noora-modal__header-icon">
      {render_slot(@icon)}
    </div>
    """
  end

  defp modal_header_icon(%{type: type} = assigns) when type in ["error", "information"] do
    ~H"""
    <div class="noora-modal__header-icon">
      <Icon.alert_circle />
    </div>
    """
  end

  defp modal_header_icon(%{type: "success"} = assigns) do
    ~H"""
    <div class="noora-modal__header-icon">
      <Icon.circle_check />
    </div>
    """
  end

  defp modal_header_icon(%{type: "warning"} = assigns) do
    ~H"""
    <div class="noora-modal__header-icon">
      <Icon.alert_triangle />
    </div>
    """
  end

  attr :type, :string, values: ~w(default stretch), default: "default", doc: "Type of the footer"
  slot :action, doc: "Actions to be rendered in the footer"
  slot :inner_block

  def modal_footer(assigns) do
    ~H"""
    <div class="noora-modal__footer" data-type={@type}>
      <div :if={@type == "default"}>
        {render_slot(@inner_block)}
      </div>
      <div class="noora-modal__footer__actions">
        <div :for={action <- @action}>
          {render_slot(action)}
        </div>
      </div>
    </div>
    """
  end
end
