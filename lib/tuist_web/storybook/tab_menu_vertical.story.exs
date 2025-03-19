defmodule TuistWeb.Storybook.TabMenuVertical do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &TuistWeb.Noora.TabMenu.tab_menu_vertical/1
  def imports, do: [{TuistWeb.Noora.Icon, [category: 1]}]

  def variations do
    [
      %Variation{
        id: :tab_menu,
        attributes: %{
          label: "Dashboard"
        },
        slots: [
          """
          <:icon_left>
            <.category />
          </:icon_left>
          """
        ]
      }
    ]
  end
end
