defmodule TuistWeb.Storybook.Tooltip do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  alias Noora.Icon

  def function, do: &Noora.Tooltip.tooltip/1
  def imports, do: [{Icon, alert_circle: 1}, {Icon, category: 1}]

  def template do
    """
    <div style="min-width: 300px; height: 80px;">
      <.psb-variation/>
    </div>
    """
  end

  def variations do
    [
      %Variation{
        id: :default,
        attributes: %{
          title: "Tooltip"
        },
        slots: [
          """
          <:trigger :let={attrs}>
            <span {attrs} style="color: var(--noora-surface-label-primary);" >
              <.alert_circle />
            </span>
          </:trigger>
          """
        ]
      },
      %Variation{
        id: :large,
        attributes: %{
          title: "Tooltip",
          description: "Insert tooltip description here. Three lines of text would look better.",
          size: "large"
        },
        slots: [
          """
          <:trigger :let={attrs}>
            <span {attrs} style="color: var(--noora-surface-label-primary);" >
              <.alert_circle />
            </span>
          </:trigger>
          <:icon>
            <.category />
          </:icon>
          """
        ]
      }
    ]
  end
end
