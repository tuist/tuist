defmodule TuistWeb.Storybook.TabMenuHorizontal do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  alias Noora.TabMenu

  def function, do: &TabMenu.tab_menu_horizontal/1

  def imports, do: [{TabMenu, [tab_menu_horizontal_item: 1]}, {Noora.Icon, [category: 1]}]

  def variations do
    [
      %Variation{
        id: :tab_menu,
        attributes: %{
          label: "Dashboard"
        },
        slots: [
          """
          <.tab_menu_horizontal_item label="General" selected>
            <:icon_left>
              <.category />
            </:icon_left>
          </.tab_menu_horizontal_item>
          <.tab_menu_horizontal_item label="Settings" />
          <.tab_menu_horizontal_item label="Members" />
          """
        ]
      }
    ]
  end
end
