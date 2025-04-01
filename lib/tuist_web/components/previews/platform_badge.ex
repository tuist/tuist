defmodule TuistWeb.Previews.PlatformBadge do
  @moduledoc """
  A component used to render an platform badge. It is used as a visual indicator for the platform a preview is targeting, for example iOS, macOS, watchOS, etc.
  """
  use Phoenix.Component
  use TuistWeb.Noora

  import TuistWeb.Previews.PlatformIcon

  alias Tuist.Previews

  attr :preview, :map, required: true

  def platform_badge(assigns) do
    ~H"""
    <.badge
      :if={not Enum.empty?(@preview.supported_platforms)}
      size="small"
      label={Previews.get_supported_platforms_case_values(@preview) |> hd()}
      color="neutral"
      style="light-fill"
    >
      <:icon>
        <.platform_icon platform={@preview.supported_platforms |> hd()} />
      </:icon>
    </.badge>
    """
  end
end
