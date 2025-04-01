defmodule TuistWeb.Previews.PlatformIcon do
  @moduledoc """
  A component used to render a preview's platform icon.
  """
  alias Tuist.Previews
  use Phoenix.Component
  use TuistWeb.Noora

  attr :platform, :map, required: true

  def platform_icon(assigns) do
    ~H"""
    <.icon name={icon_name(@platform)} />
    """
  end

  attr :platform, :map, required: true

  def platform_cell(assigns) do
    ~H"""
    <.tag_cell label={Previews.platform_string(@platform)} icon={icon_name(@platform)} />
    """
  end

  defp icon_name(:ios), do: "device_mobile"
  defp icon_name(:ios_simulator), do: "device_mobile"
  defp icon_name(:macos), do: "device_desktop"
  defp icon_name(:tvos), do: "device_tv"
  defp icon_name(:tvos_simulator), do: "device_tv"
  defp icon_name(:watchos), do: "device_watch"
  defp icon_name(:watch_os_simulator), do: "device_watch"
  defp icon_name(:visionos), do: "device_vision_pro"
  defp icon_name(:visionos_simulator), do: "device_vision_pro"
end
