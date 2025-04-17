defmodule TuistWeb.Storybook.Alert do
  @moduledoc false

  use PhoenixStorybook.Story, :component

  def function, do: &TuistWeb.Noora.Alert.alert/1
  def imports, do: [{TuistWeb.Noora.Button, link_button: 1}]

  def variations do
    [
      %VariationGroup{
        id: "Type",
        variations: [
          %Variation{
            id: :primary,
            attributes: %{
              type: "primary",
              title: "Insert your text here",
              status: "error"
            }
          },
          %Variation{
            id: :secondary,
            attributes: %{
              type: "secondary",
              title: "Insert your text here",
              status: "error"
            }
          }
        ]
      },
      %VariationGroup{
        id: :size,
        variations: [
          %Variation{
            id: :small,
            attributes: %{
              size: "small",
              title: "Insert your text here",
              status: "error"
            }
          },
          %Variation{
            id: :medium,
            attributes: %{
              size: "medium",
              title: "Insert your text here",
              status: "error"
            }
          },
          %Variation{
            id: :large,
            attributes: %{
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
        variations: [
          %Variation{
            id: :error,
            attributes: %{
              status: "error",
              title: "Insert your text here"
            }
          },
          %Variation{
            id: :information,
            attributes: %{
              status: "information",
              title: "Insert your text here"
            }
          },
          %Variation{
            id: :success,
            attributes: %{
              status: "success",
              title: "Insert your text here"
            }
          },
          %Variation{
            id: :warning,
            attributes: %{
              status: "warning",
              title: "Insert your text here"
            }
          }
        ]
      },
      %VariationGroup{
        id: :status_secondary,
        variations: [
          %Variation{
            id: :error,
            attributes: %{
              type: "secondary",
              status: "error",
              title: "Insert your text here"
            }
          },
          %Variation{
            id: :information,
            attributes: %{
              type: "secondary",
              status: "information",
              title: "Insert your text here"
            }
          },
          %Variation{
            id: :success,
            attributes: %{
              type: "secondary",
              status: "success",
              title: "Insert your text here"
            }
          },
          %Variation{
            id: :warning,
            attributes: %{
              type: "secondary",
              status: "warning",
              title: "Insert your text here"
            }
          }
        ]
      },
      %VariationGroup{
        id: :dismissible,
        variations: [
          %Variation{
            id: :dismissible_small,
            attributes: %{
              dismissible: true,
              status: "error",
              size: "small",
              title: "Insert your text here"
            }
          },
          %Variation{
            id: :dismissible_medium,
            attributes: %{
              dismissible: true,
              status: "error",
              size: "medium",
              title: "Insert your text here"
            }
          },
          %Variation{
            id: :dismissible_with_actions,
            attributes: %{
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
        variations: [
          %Variation{
            id: :with_actions_small,
            attributes: %{
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
      }
    ]
  end
end
