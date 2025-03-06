defmodule TuistWeb.Storybook.Breadcrumbs do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &TuistWeb.Noora.Breadcrumbs.breadcrumbs/1

  def imports,
    do: [
      {TuistWeb.Noora.Breadcrumbs, [breadcrumb: 1, breadcrumb_item: 1]},
      {TuistWeb.Noora.Icon, [smart_home: 1]}
    ]

  def variations do
    [
      %Variation{
        id: :with_slashes,
        attributes: %{
          label: "Breadcrumbs"
        },
        slots: [
          """
          <.breadcrumb id="account-breadcrumb" label="tuist">
            <:icon><.smart_home /></:icon>
            <.breadcrumb_item value="1" label="Item 1" />
            <.breadcrumb_item value="2" label="Item 2" selected={true} />
          </.breadcrumb>
          <.breadcrumb id="project-breadcrumb" label="tuist">
            <.breadcrumb_item value="1" label="Item 1" />
          </.breadcrumb>
          """
        ]
      },
      %Variation{
        id: :with_arrows,
        attributes: %{
          label: "Breadcrumbs",
          style: "arrow"
        },
        slots: [
          """
          <.breadcrumb id="account-breadcrumb" label="tuist">
            <:icon><.smart_home /></:icon>
            <.breadcrumb_item value="1" label="Item 1" />
            <.breadcrumb_item value="2" label="Item 2" selected={true} />
          </.breadcrumb>
          <.breadcrumb id="project-breadcrumb" label="tuist">
            <.breadcrumb_item value="1" label="Item 1" />
          </.breadcrumb>
          """
        ]
      }
    ]
  end
end
