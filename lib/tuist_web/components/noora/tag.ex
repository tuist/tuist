defmodule TuistWeb.Noora.Tag do
  @moduledoc """
  A tag component.

  It can optionally be rendered with an icon and a button to dismiss it.
  """

  use Phoenix.Component

  import TuistWeb.Noora.Icon
  import TuistWeb.Noora.DismissIcon

  attr :label, :string, required: true, doc: "The label of the tag."
  attr :dismissible, :boolean, default: false, doc: "Whether the tag can be dismissed."
  attr :on_dismiss, :string, default: nil, doc: "The event to trigger when the tag is dismissed."
  attr :icon, :string, default: nil, doc: "An icon to render in front of the label."
  attr :disabled, :boolean, default: false, doc: "Whether the tag is disabled."
  attr :rest, :global

  def tag(assigns) do
    ~H"""
    <div class="noora-tag" data-disabled={@disabled} aria-disabled={@disabled}>
      <div :if={@icon} data-part="icon">
        <.icon name={@icon} />
      </div>
      <span data-part="label">{@label}</span>
      <.dismiss_icon
        :if={@dismissible}
        on_dismiss={@on_dismiss}
        disabled={@disabled}
        size="small"
        data-part="dismiss-icon"
      />
    </div>
    """
  end
end
