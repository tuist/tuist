defmodule TuistWeb.Storybook.Banner do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &Noora.Banner.banner/1
  def layout, do: :one_column
  def imports, do: [{Noora.Icon, alert_circle: 1}]

  def variations do
    [
      %VariationGroup{
        id: :status,
        description: "Status",
        variations: [
          %Variation{
            id: :status_primary,
            attributes: %{
              id: "banner-status-primary",
              status: "primary",
              title: "Primary status",
              description: "I am a primary banner"
            }
          },
          %Variation{
            id: :status_error,
            attributes: %{
              id: "banner-status-error",
              status: "error",
              title: "Error status",
              description: "I am an error banner"
            }
          },
          %Variation{
            id: :status_success,
            attributes: %{
              id: "banner-status-success",
              status: "success",
              title: "Success status",
              description: "I am a success banner"
            }
          },
          %Variation{
            id: :status_warning,
            attributes: %{
              id: "banner-status-warning",
              status: "warning",
              title: "Warning status",
              description: "I am a warning banner"
            }
          },
          %Variation{
            id: :status_information,
            attributes: %{
              id: "banner-status-information",
              status: "information",
              title: "Information status",
              description: "I am an information banner"
            }
          }
        ]
      },
      %VariationGroup{
        id: :icon,
        description: "Custom Icon",
        variations: [
          %Variation{
            id: :icon_primary,
            attributes: %{
              id: "banner-icon-primary",
              status: "primary",
              title: "Primary status",
              description: "I am a primary banner with a custom icon"
            },
            slots: [
              """
              <:icon>
                <.alert_circle />
              </:icon>
              """
            ]
          }
        ]
      },
      %VariationGroup{
        id: :content_variations,
        description: "Different content configurations",
        variations: [
          %Variation{
            id: :without_description,
            attributes: %{
              id: "banner-no-description",
              status: "primary",
              title: "Title only banner"
            }
          },
          %Variation{
            id: :dismissible,
            attributes: %{
              id: "banner-dismissible",
              status: "warning",
              title: "Dismissible banner",
              description: "This banner can be dismissed by the user",
              dismissible: true
            }
          },
          %Variation{
            id: :long_content,
            attributes: %{
              id: "banner-long-content",
              status: "information",
              title: "Banner with longer content",
              description: "This is a banner with much longer descriptive text that demonstrates how the component handles multiple lines of content and text wrapping behavior"
            }
          }
        ]
      }
    ]
  end
end
