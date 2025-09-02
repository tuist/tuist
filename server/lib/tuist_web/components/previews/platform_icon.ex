defmodule TuistWeb.Previews.PlatformIcon do
  @moduledoc """
  A component used to render a preview's platform icon.
  """
  use Phoenix.Component
  use Noora

  attr :platform, :map, required: true

  def platform_icon(assigns) do
    ~H"""
    <.icon name={platform_icon_name(@platform)} />
    """
  end

  def platform_icon_name(:ios), do: "device_mobile"
  def platform_icon_name(:ios_simulator), do: "device_mobile_share"
  def platform_icon_name(:macos), do: "device_laptop"
  def platform_icon_name(:tvos), do: "device_desktop"
  def platform_icon_name(:tvos_simulator), do: "device_desktop_share"
  def platform_icon_name(:watchos), do: "device_watch"
  def platform_icon_name(:watchos_simulator), do: "device_watch_share"
  def platform_icon_name(:visionos), do: "device_vision_pro"
  def platform_icon_name(:visionos_simulator), do: "device_vision_pro_share"
end
