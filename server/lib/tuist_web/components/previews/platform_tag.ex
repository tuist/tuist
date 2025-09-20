defmodule TuistWeb.Previews.PlatformTag do
  @moduledoc false
  use Phoenix.Component
  use Noora

  import TuistWeb.Previews.PlatformIcon

  alias Tuist.AppBuilds

  attr :platform, :string, required: true

  def platform_tag(assigns) do
    ~H"""
    <.tag label={AppBuilds.platform_string(@platform)} icon={platform_icon_name(@platform)} />
    """
  end

  attr :platform, :map, required: true

  def platform_cell(assigns) do
    ~H"""
    <.tag_cell label={AppBuilds.platform_string(@platform)} icon={platform_icon_name(@platform)} />
    """
  end
end
