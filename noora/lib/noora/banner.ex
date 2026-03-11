defmodule Noora.Banner do
  @moduledoc """
  Renders a customizable banner component for displaying messages with different statuses (primary, error, success, warning, information), optional descriptions, and dismissible functionality. Supports a custom icon when the status is primary.

  ## Example

  ```elixir
  <.banner id="notice" status="success" title="Changes saved successfully" />
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

  def banner(assigns) do
    ~H"""
    <div id={@id} class="noora-banner" data-status={@status}>
      <.background_grid :if={@status == "primary"} />
      <.icon status={@status} icon={@icon} />
      <span data-part="title">{@title}</span>
      <span :if={@description} data-part="dot">•</span>
      <span :if={@description} data-part="description">{@description}</span>
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

  defp background_grid(assigns) do
    ~H"""
    <svg
      data-part="background"
      xmlns="http://www.w3.org/2000/svg"
      viewBox="0 0 1440 44"
      preserveAspectRatio="xMidYMid slice"
      fill="none"
    >
      <path
        d="M0.5 44V0M10.5 44V0M20.5 44V0M30.5 44V0M40.5 44V0M50.5 44V0M60.5 44V0M70.5 44V0M80.5 44V0M90.5 44V0M100.5 44V0M110.5 44V0M120.5 44V0M130.5 44V0M140.5 44V0M150.5 44V0M160.5 44V0M170.5 44V0M180.5 44V0M190.5 44V0M200.5 44V0M210.5 44V0M220.5 44V0M230.5 44V0M240.5 44V0M250.5 44V0M260.5 44V0M270.5 44V0M280.5 44V0M290.5 44V0M300.5 44V0M310.5 44V0M320.5 44V0M330.5 44V0M340.5 44V0M350.5 44V0M360.5 44V0M370.5 44V0M380.5 44V0M390.5 44V0M400.5 44V0M410.5 44V0M420.5 44V0M430.5 44V0M440.5 44V0M450.5 44V0M460.5 44V0M470.5 44V0M480.5 44V0M490.5 44V0M500.5 44V0M510.5 44V0M520.5 44V0M530.5 44V0M540.5 44V0M550.5 44V0M560.5 44V0M570.5 44V0M580.5 44V0M590.5 44V0M600.5 44V0M610.5 44V0M620.5 44V0M630.5 44V0M640.5 44V0M650.5 44V0M660.5 44V0M670.5 44V0M680.5 44V0M690.5 44V0M700.5 44V0M710.5 44V0M720.5 44V0M730.5 44V0M740.5 44V0M750.5 44V0M760.5 44V0M770.5 44V0M780.5 44V0M790.5 44V0M800.5 44V0M810.5 44V0M820.5 44V0M830.5 44V0M840.5 44V0M850.5 44V0M860.5 44V0M870.5 44V0M880.5 44V0M890.5 44V0M900.5 44V0M910.5 44V0M920.5 44V0M930.5 44V0M940.5 44V0M950.5 44V0M960.5 44V0M970.5 44V0M980.5 44V0M990.5 44V0M1000.5 44V0M1010.5 44V0M1020.5 44V0M1030.5 44V0M1040.5 44V0M1050.5 44V0M1060.5 44V0M1070.5 44V0M1080.5 44V0M1090.5 44V0M1100.5 44V0M1110.5 44V0M1120.5 44V0M1130.5 44V0M1140.5 44V0M1150.5 44V0M1160.5 44V0M1170.5 44V0M1180.5 44V0M1190.5 44V0M1200.5 44V0M1210.5 44V0M1220.5 44V0M1230.5 44V0M1240.5 44V0M1250.5 44V0M1260.5 44V0M1270.5 44V0M1280.5 44V0M1290.5 44V0M1300.5 44V0M1310.5 44V0M1320.5 44V0M1330.5 44V0M1340.5 44V0M1350.5 44V0M1360.5 44V0M1370.5 44V0M1380.5 44V0M1390.5 44V0M1400.5 44V0M1410.5 44V0M1420.5 44V0M1430.5 44V0M1440.5 44V0M0 9.5H1440M0 19.5H1440M0 29.5H1440M0 39.5H1440"
        stroke="url(#paint0_radial_278_2337)"
        stroke-width="0.5"
      />
      <defs>
        <radialGradient
          id="paint0_radial_278_2337"
          cx="0"
          cy="0"
          r="1"
          gradientUnits="userSpaceOnUse"
          gradientTransform="translate(720.25 22) scale(682.75 20.8546)"
        >
          <stop stop-color="currentColor" stop-opacity="0.15" />
          <stop offset="1" stop-color="currentColor" stop-opacity="0" />
        </radialGradient>
      </defs>
    </svg>
    """
  end
end
