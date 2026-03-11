defmodule TuistWeb.Storybook.Alert do
  @moduledoc false

  use PhoenixStorybook.Story, :component

  def function, do: &Noora.Alert.alert/1
  def imports, do: [{Noora.Button, link_button: 1}]

  def variations do
    [
      %VariationGroup{
        id: "Type",
        description: "Alert types: primary (default) for standard alerts, secondary for less prominent alerts",
        variations: [
          %Variation{
            id: :primary,
            attributes: %{
              id: "alert-type-primary",
              type: "primary",
              title: "Insert your text here",
              status: "error"
            }
          },
          %Variation{
            id: :secondary,
            attributes: %{
              id: "alert-type-secondary",
              type: "secondary",
              title: "Insert your text here",
              status: "error"
            }
          }
        ]
      },
      %VariationGroup{
        id: :size,
        description: "Sizes: small (compact), medium (standard), large (with description support)",
        variations: [
          %Variation{
            id: :small,
            attributes: %{
              id: "alert-size-small",
              size: "small",
              title: "Insert your text here",
              status: "error"
            }
          },
          %Variation{
            id: :medium,
            attributes: %{
              id: "alert-size-medium",
              size: "medium",
              title: "Insert your text here",
              status: "error"
            }
          },
          %Variation{
            id: :large,
            attributes: %{
              id: "alert-size-large",
              size: "large",
              title: "Insert your text here",
              description: "Insert your description here. Description in this case is usually two lines",
              status: "error"
            }
          }
        ]
      },
      %VariationGroup{
        id: :status_primary,
        description: "Status variations for primary alerts: error, information, success, warning",
        variations: [
          %Variation{
            id: :error,
            attributes: %{
              id: "alert-status-primary-error",
              status: "error",
              title: "Insert your text here"
            }
          },
          %Variation{
            id: :information,
            attributes: %{
              id: "alert-status-primary-information",
              status: "information",
              title: "Insert your text here"
            }
          },
          %Variation{
            id: :success,
            attributes: %{
              id: "alert-status-primary-success",
              status: "success",
              title: "Insert your text here"
            }
          },
          %Variation{
            id: :warning,
            attributes: %{
              id: "alert-status-primary-warning",
              status: "warning",
              title: "Insert your text here"
            }
          }
        ]
      },
      %VariationGroup{
        id: :status_secondary,
        description: "Status variations for secondary alerts: error, information, success, warning",
        variations: [
          %Variation{
            id: :error,
            attributes: %{
              id: "alert-status-secondary-error",
              type: "secondary",
              status: "error",
              title: "Insert your text here"
            }
          },
          %Variation{
            id: :information,
            attributes: %{
              id: "alert-status-secondary-information",
              type: "secondary",
              status: "information",
              title: "Insert your text here"
            }
          },
          %Variation{
            id: :success,
            attributes: %{
              id: "alert-status-secondary-success",
              type: "secondary",
              status: "success",
              title: "Insert your text here"
            }
          },
          %Variation{
            id: :warning,
            attributes: %{
              id: "alert-status-secondary-warning",
              type: "secondary",
              status: "warning",
              title: "Insert your text here"
            }
          }
        ]
      },
      %VariationGroup{
        id: :dismissible,
        description: "Dismissible alerts with close button for different sizes",
        variations: [
          %Variation{
            id: :dismissible_small,
            attributes: %{
              id: "alert-dismissible-small",
              dismissible: true,
              status: "error",
              size: "small",
              title: "Insert your text here"
            }
          },
          %Variation{
            id: :dismissible_medium,
            attributes: %{
              id: "alert-dismissible-medium",
              dismissible: true,
              status: "error",
              size: "medium",
              title: "Insert your text here"
            }
          },
          %Variation{
            id: :dismissible_with_actions,
            attributes: %{
              id: "alert-dismissible-large",
              dismissible: true,
              status: "error",
              size: "large",
              title: "Insert your text here",
              description: "Insert your description here. Description in this case is usually two lines"
            }
          }
        ]
      },
      %VariationGroup{
        id: :with_actions,
        description: "Alerts with action buttons for small and large sizes",
        variations: [
          %Variation{
            id: :with_actions_small,
            attributes: %{
              id: "alert-with-actions-small",
              status: "error",
              size: "small",
              title: "Insert your text here"
            },
            slots: [
              """
              <:action><.link_button size="medium" variant="secondary" underline label="Action" /></:action>
              """
            ]
          },
          %Variation{
            id: :with_actions_large,
            attributes: %{
              id: "alert-with-actions-large",
              status: "error",
              size: "large",
              title: "Insert your text here",
              description: "Insert your description here. Description in this case is usually two lines"
            },
            slots: [
              """
              <:action><.link_button size="large" variant="secondary" underline label="Action" /></:action>
              """
            ]
          }
        ]
      },
      %VariationGroup{
        id: :edge_cases,
        description: "Edge cases and special scenarios",
        variations: [
          %Variation{
            id: :long_title,
            attributes: %{
              id: "alert-edge-long-title",
              status: "information",
              title: "This is a very long title that might wrap to multiple lines in smaller containers or on mobile devices to test text wrapping behavior"
            }
          },
          %Variation{
            id: :long_description,
            attributes: %{
              id: "alert-edge-long-description",
              size: "large",
              status: "warning",
              title: "Important Notice",
              description: "This is a very long description that contains multiple sentences and important information. It should properly wrap and maintain readability even when the content extends beyond the typical two-line description. This helps test the layout behavior with extensive content."
            }
          },
          %Variation{
            id: :dismissible_with_actions_medium,
            attributes: %{
              id: "alert-combined-dismissible-actions",
              dismissible: true,
              status: "success",
              size: "medium",
              title: "Operation completed successfully"
            },
            slots: [
              """
              <:action><.link_button size="medium" variant="secondary" underline label="View Details" /></:action>
              <:action><.link_button size="medium" variant="secondary" underline label="Dismiss" /></:action>
              """
            ]
          }
        ]
      }
    ]
  end
end
