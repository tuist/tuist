defmodule TuistWeb.Storybook.Icon do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  alias Noora.Icon

  def function, do: &Icon.icon/1

  def template do
    """
    <button
      data-part="trigger"
      phx-click={Phoenix.LiveView.JS.toggle_attribute({"data-state", "open", "closed"})}
      style="display:inline-flex; align-items:center; justify-content:center; padding:.75rem; border:1px solid #d0d0d0; border-radius:10px; background:#fff; color:#1a1a1a; cursor:pointer;"
    >
      <.psb-variation/>
    </button>
    """
  end

  def variations do
    [
      %VariationGroup{
        id: :transitions,
        description:
          "Animated `<.icon>` transitions. Click a button to toggle its `data-state`; the icon reacts. `morph` tweens compatible filled paths; `crossfade_rotate` works for any pair; `auto` picks the best.",
        variations: [
          %Variation{
            id: :morph,
            attributes: %{
              id: "icon-morph",
              name: "selector",
              active_name: "selector_2",
              transition: "morph"
            }
          },
          %Variation{
            id: :crossfade_menu,
            attributes: %{
              id: "icon-crossfade-menu",
              name: "menu",
              active_name: "close",
              transition: "crossfade_rotate"
            }
          },
          %Variation{
            id: :crossfade_theme,
            attributes: %{
              id: "icon-crossfade-theme",
              name: "sun_high",
              active_name: "moon",
              transition: "crossfade_rotate"
            }
          },
          %Variation{
            id: :auto,
            attributes: %{
              id: "icon-auto",
              name: "player_play",
              active_name: "player_pause",
              transition: "auto"
            }
          }
        ]
      }
    ]
  end
end
