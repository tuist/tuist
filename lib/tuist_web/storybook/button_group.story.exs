defmodule TuistWeb.Storybook.ButtonGroup do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def imports,
    do: [
      {TuistWeb.Noora.ButtonGroup, [button_group_item: 1]},
      {TuistWeb.Noora.Icon, chevron_left: 1, chevron_right: 1}
    ]

  def function, do: &TuistWeb.Noora.ButtonGroup.button_group/1

  def variations do
    [
      %Variation{
        id: :button_group_large,
        attributes: %{
          size: "large"
        },
        slots: [
          """
          <.button_group_item label="Button" />
          <.button_group_item label="Button" />
          """
        ]
      },
      %Variation{
        id: :button_group_medium,
        attributes: %{
          size: "medium"
        },
        slots: [
          """
          <.button_group_item label="Button" />
          <.button_group_item label="Button" />
          """
        ]
      },
      %Variation{
        id: :button_group_small,
        attributes: %{
          size: "small"
        },
        slots: [
          """
          <.button_group_item label="Button" />
          <.button_group_item label="Button" />
          """
        ]
      },
      %Variation{
        id: :button_group_medium_with_icons,
        attributes: %{
          size: "medium"
        },
        slots: [
          """
          <.button_group_item label="Button">
            <:icon_left><.chevron_left /></:icon_left>
          </.button_group_item>
          <.button_group_item icon_only>
            <.chevron_left />
          </.button_group_item>
          <.button_group_item label="Button">
            <:icon_left><.chevron_left /></:icon_left>
            <:icon_right><.chevron_right /></:icon_right>
          </.button_group_item>
          <.button_group_item icon_only>
            <.chevron_right />
          </.button_group_item>
          <.button_group_item label="Button">
            <:icon_right><.chevron_right /></:icon_right>
          </.button_group_item>
          """
        ]
      },
      %Variation{
        id: :button_group_medium_disabled,
        attributes: %{
          size: "medium"
        },
        slots: [
          """
          <.button_group_item label="Button" disabled>
            <:icon_left><.chevron_left /></:icon_left>
          </.button_group_item>
          <.button_group_item label="Button" />
          <.button_group_item label="Button" disabled>
            <:icon_right><.chevron_right /></:icon_right>
          </.button_group_item>
          """
        ]
      }
    ]
  end
end
