defmodule TuistWeb.Storybook.Banner do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &TuistWeb.Noora.Banner.banner/1
  def imports, do: [{TuistWeb.Noora.Icon, alert_circle: 1}]

  def variations do
    [
      %VariationGroup{
        id: :status,
        description: "Status",
        variations: [
          %Variation{
            id: :status_primary,
            attributes: %{
              status: "primary",
              title: "Primary status",
              description: "I am a primary banner"
            }
          },
          %Variation{
            id: :status_error,
            attributes: %{
              status: "error",
              title: "Error status",
              description: "I am an error banner"
            }
          },
          %Variation{
            id: :status_success,
            attributes: %{
              status: "success",
              title: "Success status",
              description: "I am a success banner"
            }
          },
          %Variation{
            id: :status_warning,
            attributes: %{
              status: "warning",
              title: "Warning status",
              description: "I am a warning banner"
            }
          },
          %Variation{
            id: :status_information,
            attributes: %{
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
              status: "primary",
              title: "Primary status",
              description: "I am a primary banner with a custom icon"
            },
            slots: [
              """
              <:icon>
                <.alert_circle />
              </:icon>
              """,
              "Primary"
            ]
          }
        ]
      },
      %Variation{
        id: :without_description,
        attributes: %{
          status: "primary",
          title: "Title"
        }
      },
      %Variation{
        id: :dismissible,
        attributes: %{
          status: "primary",
          title: "Primary status",
          dismissible: true
        },
        slots: ["Primary"]
      }
    ]
  end
end
