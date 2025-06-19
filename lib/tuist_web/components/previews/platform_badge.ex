defmodule TuistWeb.Previews.PlatformBadge do
  @moduledoc """
  A component used to render an platform badge. It is used as a visual indicator for the platform a preview is targeting, for example iOS, macOS, watchOS, etc.
  """
  use Phoenix.Component
  use Noora

  import TuistWeb.Previews.PlatformIcon

  alias Tuist.AppBuilds

  attr :platform, :map, required: true

  def platform_badge(assigns) do
    ~H"""
    <.badge
      size="small"
      label={AppBuilds.platform_string(@platform)}
      color="neutral"
      style="light-fill"
    >
      <:icon>
        <.platform_icon platform={@platform} />
      </:icon>
    </.badge>
    """
  end
end
