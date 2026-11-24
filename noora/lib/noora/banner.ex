defmodule Noora.Banner do
  @moduledoc """
  Renders a customizable banner component for displaying messages with different statuses (primary, error, success, warning, information), optional descriptions, and dismissible functionality. Supports a custom icon when the status is primary, whose background is an animated dither wave drawn by the `NooraDitherWave` hook.

  ## Example

  ```elixir
  <.banner id="notice" status="success" title="Changes saved successfully" />
  ```

  With a link:

  ```elixir
  <.banner id="release" status="information" title="Tuist 5 is out">
    <:action><.link_button label="Read the release notes" size="large" href="/blog" /></:action>
  </.banner>
  ```
  """
  use Phoenix.Component

  import Noora.DismissIcon

  alias Noora.Icon
  alias Phoenix.LiveView.JS

  attr(:id, :string, required: true)

  attr(:status, :string,
    values: ~w(primary error success warning information),
    default: "primary",
    doc: "The status of the banner"
  )

  attr(:title, :string,
    required: true,
    doc: "The title of the banner"
  )

  attr(:description, :string, default: nil, doc: "The description of the banner")

  attr(:dismissible, :boolean,
    default: false,
    doc: "Whether the banner is dismissible or not"
  )

  slot(:icon, required: false, doc: "A custom icon. Only applicable when status is primary")

  slot(:action,
    doc:
      "An optional link after the title and description, such as Learn more. Pass a large `link_button`; its `icon_left` and `icon_right` slots add arrows."
  )

  def banner(assigns) do
    ~H"""
    <div id={@id} class="noora-banner" data-status={@status}>
      <canvas
        :if={@status == "primary"}
        id={"#{@id}-dither"}
        data-part="background"
        phx-hook="NooraDitherWave"
        phx-update="ignore"
        aria-hidden="true"
        data-colors="--noora-banner-dither-shallow,--noora-banner-dither-deep"
      >
      </canvas>
      <.icon status={@status} icon={@icon} />
      <span data-part="title">{@title}</span>
      <span :if={@description} data-part="dot">•</span>
      <span :if={@description} data-part="description">{@description}</span>
      <span :if={@action != []} data-part="dot">•</span>
      <div :if={@action != []} data-part="action">
        {render_slot(@action)}
      </div>
      <div :if={@dismissible} data-part="dismiss-icon">
        <.dismiss_icon phx-click={JS.hide(to: "##{@id}")} />
      </div>
    </div>
    """
  end

  defp icon(%{status: "primary"} = assigns) do
    ~H"""
    <div :if={@icon} data-part="icon">
      {render_slot(@icon)}
    </div>
    """
  end

  defp icon(%{status: status} = assigns) when status in ["error", "information"] do
    ~H"""
    <div data-part="icon">
      <Icon.alert_circle />
    </div>
    """
  end

  defp icon(%{status: "success"} = assigns) do
    ~H"""
    <div data-part="icon">
      <Icon.circle_check />
    </div>
    """
  end

  defp icon(%{status: "warning"} = assigns) do
    ~H"""
    <div data-part="icon">
      <Icon.alert_triangle />
    </div>
    """
  end
end
