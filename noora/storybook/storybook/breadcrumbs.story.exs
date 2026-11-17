defmodule TuistWeb.Storybook.Breadcrumbs do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  alias Noora.Breadcrumbs

  def function, do: &Breadcrumbs.breadcrumbs/1

  def imports, do: [{Breadcrumbs, [breadcrumb: 1, breadcrumb_item: 1]}, {Noora.Icon, [smart_home: 1]}]

  def variations do
    [
      %VariationGroup{
        id: :styles,
        description: "Different separator styles between breadcrumb items",
        variations: [
          %Variation{
            id: :slash_style,
            attributes: %{
              id: "breadcrumbs-slash",
              style: "slash"
            },
            slots: [
              """
              <.breadcrumb id="home-breadcrumb" label="Home">
                <:icon><.smart_home /></:icon>
              </.breadcrumb>
              <.breadcrumb id="products-breadcrumb" label="Products">
                <.breadcrumb_item id="electronics-item" value="electronics" label="Electronics" />
                <.breadcrumb_item id="phones-item" value="phones" label="Phones" selected={true} />
              </.breadcrumb>
              <.breadcrumb id="category-breadcrumb" label="iPhone 15" />
              """
            ]
          },
          %Variation{
            id: :arrow_style,
            attributes: %{
              id: "breadcrumbs-arrow",
              style: "arrow"
            },
            slots: [
              """
              <.breadcrumb id="home-breadcrumb-arrow" label="Home">
                <:icon><.smart_home /></:icon>
              </.breadcrumb>
              <.breadcrumb id="products-breadcrumb-arrow" label="Products">
                <.breadcrumb_item id="electronics-item-arrow" value="electronics" label="Electronics" />
                <.breadcrumb_item id="phones-item-arrow" value="phones" label="Phones" selected={true} />
              </.breadcrumb>
              <.breadcrumb id="category-breadcrumb-arrow" label="iPhone 15" />
              """
            ]
          }
        ]
      },
      %VariationGroup{
        id: :configurations,
        description: "Different breadcrumb configurations and features",
        variations: [
          %Variation{
            id: :with_avatars,
            attributes: %{
              id: "breadcrumbs-avatars",
              style: "slash"
            },
            slots: [
              """
              <.breadcrumb id="org-breadcrumb" label="Tuist" show_avatar avatar_color="blue" />
              <.breadcrumb id="project-breadcrumb" label="iOS App" show_avatar avatar_color="green">
                <.breadcrumb_item id="feature-item" value="feature" label="Features" show_avatar avatar_color="orange" />
                <.breadcrumb_item id="auth-item" value="auth" label="Authentication" show_avatar avatar_color="purple" selected={true} />
              </.breadcrumb>
              <.breadcrumb id="current-breadcrumb" label="Login Screen" show_avatar avatar_color="red" />
              """
            ]
          },
          %Variation{
            id: :simple_path,
            attributes: %{
              id: "breadcrumbs-simple",
              style: "slash"
            },
            slots: [
              """
              <.breadcrumb id="dashboard-breadcrumb" label="Dashboard">
                <:icon><.smart_home /></:icon>
              </.breadcrumb>
              <.breadcrumb id="settings-breadcrumb" label="Settings" />
              <.breadcrumb id="profile-breadcrumb" label="Profile" />
              """
            ]
          },
          %Variation{
            id: :without_dropdowns,
            attributes: %{
              id: "breadcrumbs-no-dropdown",
              style: "arrow"
            },
            slots: [
              """
              <.breadcrumb id="simple-home" label="Home">
                <:icon><.smart_home /></:icon>
              </.breadcrumb>
              <.breadcrumb id="simple-docs" label="Documentation" />
              <.breadcrumb id="simple-guides" label="Guides" />
              <.breadcrumb id="simple-current" label="Getting Started" />
              """
            ]
          }
        ]
      },
      %VariationGroup{
        id: :dropdown_variations,
        description: "Breadcrumbs with different dropdown configurations",
        variations: [
          %Variation{
            id: :many_items,
            attributes: %{
              id: "breadcrumbs-many",
              style: "slash"
            },
            slots: [
              """
              <.breadcrumb id="org-many" label="Organization">
                <:icon><.smart_home /></:icon>
                <.breadcrumb_item id="team1" value="team1" label="Team Alpha" />
                <.breadcrumb_item id="team2" value="team2" label="Team Beta" />
                <.breadcrumb_item id="team3" value="team3" label="Team Gamma" />
                <.breadcrumb_item id="team4" value="team4" label="Team Delta" selected={true} />
              </.breadcrumb>
              <.breadcrumb id="project-many" label="Project X" />
              """
            ]
          },
          %Variation{
            id: :mixed_avatars,
            attributes: %{
              id: "breadcrumbs-mixed",
              style: "arrow"
            },
            slots: [
              """
              <.breadcrumb id="company-mixed" label="Company" show_avatar avatar_color="blue" />
              <.breadcrumb id="dept-mixed" label="Engineering">
                <.breadcrumb_item id="backend" value="backend" label="Backend Team" show_avatar avatar_color="red" />
                <.breadcrumb_item id="frontend" value="frontend" label="Frontend Team" show_avatar avatar_color="green" selected={true} />
              </.breadcrumb>
              <.breadcrumb id="current-mixed" label="React Components" />
              """
            ]
          }
        ]
      }
    ]
  end
end
