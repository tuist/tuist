defmodule TuistWeb.Storybook.Avatar do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &Noora.Avatar.avatar/1

  def variations do
    [
      %VariationGroup{
        id: :basic,
        description: "Basic avatar variations with initials and images",
        variations: [
          %Variation{
            id: :default,
            attributes: %{
              id: "avatar-basic-default",
              name: "Asmit Malakannawar"
            }
          },
          %Variation{
            id: :with_image,
            attributes: %{
              id: "avatar-basic-image",
              name: "Marek Fořt",
              image_href: "https://www.gravatar.com/avatar/292c129cf17a552c08b4d9dcf2c6c1f8"
            }
          },
          %Variation{
            id: :with_placeholder,
            attributes: %{
              id: "avatar-basic-placeholder",
              name: "Marek Fořt",
              image_href: "https://www.invalid.url",
              fallback: "placeholder"
            }
          }
        ]
      },
      %VariationGroup{
        id: :sizes,
        description: "Avatar sizes from 2xsmall to 2xlarge",
        variations: [
          %Variation{
            id: :size_2xsmall,
            attributes: %{
              id: "avatar-size-2xsmall",
              name: "Asmit Malakannawar",
              size: "2xsmall",
              color: "gray"
            }
          },
          %Variation{
            id: :size_small,
            attributes: %{
              id: "avatar-size-small",
              name: "Asmit Malakannawar",
              size: "small",
              color: "orange"
            }
          },
          %Variation{
            id: :size_medium,
            attributes: %{
              id: "avatar-size-medium",
              name: "Asmit Malakannawar",
              size: "medium",
              color: "yellow"
            }
          },
          %Variation{
            id: :size_large,
            attributes: %{
              id: "avatar-size-large",
              name: "Asmit Malakannawar",
              size: "large",
              color: "azure"
            }
          },
          %Variation{
            id: :size_xlarge,
            attributes: %{
              id: "avatar-size-xlarge",
              name: "Asmit Malakannawar",
              size: "xlarge",
              color: "blue"
            }
          },
          %Variation{
            id: :size_2xlarge,
            attributes: %{
              id: "avatar-size-2xlarge",
              name: "Asmit Malakannawar",
              size: "2xlarge",
              color: "purple"
            }
          },
        ]
      },
      %VariationGroup{
        id: :colors,
        description: "Available color options for avatars",
        variations: [
          %Variation{
            id: :color_gray,
            attributes: %{
              id: "avatar-color-gray",
              name: "John Doe",
              color: "gray"
            }
          },
          %Variation{
            id: :color_red,
            attributes: %{
              id: "avatar-color-red",
              name: "Jane Smith",
              color: "red"
            }
          },
          %Variation{
            id: :color_orange,
            attributes: %{
              id: "avatar-color-orange",
              name: "Bob Johnson",
              color: "orange"
            }
          },
          %Variation{
            id: :color_yellow,
            attributes: %{
              id: "avatar-color-yellow",
              name: "Alice Brown",
              color: "yellow"
            }
          },
          %Variation{
            id: :color_azure,
            attributes: %{
              id: "avatar-color-azure",
              name: "Charlie Davis",
              color: "azure"
            }
          },
          %Variation{
            id: :color_blue,
            attributes: %{
              id: "avatar-color-blue",
              name: "Emma Wilson",
              color: "blue"
            }
          },
          %Variation{
            id: :color_purple,
            attributes: %{
              id: "avatar-color-purple",
              name: "Frank Miller",
              color: "purple"
            }
          },
          %Variation{
            id: :color_pink,
            attributes: %{
              id: "avatar-color-pink",
              name: "Grace Taylor",
              color: "pink"
            }
          }
        ]
      },
      %VariationGroup{
        id: :edge_cases,
        description: "Edge cases and special name formats",
        variations: [
          %Variation{
            id: :single_name,
            attributes: %{
              id: "avatar-edge-single-name",
              name: "Madonna",
              color: "purple"
            }
          },
          %Variation{
            id: :three_names,
            attributes: %{
              id: "avatar-edge-three-names",
              name: "Mary Jane Watson",
              color: "red"
            }
          },
          %Variation{
            id: :hyphenated_name,
            attributes: %{
              id: "avatar-edge-hyphenated",
              name: "Anne-Marie Johnson",
              color: "blue"
            }
          },
          %Variation{
            id: :with_underscore,
            attributes: %{
              id: "avatar-edge-underscore",
              name: "john_doe_123",
              color: "gray"
            }
          },
          %Variation{
            id: :special_characters,
            attributes: %{
              id: "avatar-edge-special",
              name: "José García",
              color: "orange"
            }
          },
          %Variation{
            id: :empty_image_initials,
            attributes: %{
              id: "avatar-edge-failed-image",
              name: "Failed Image Test",
              image_href: "",
              fallback: "initials"
            }
          }
        ]
      }
    ]
  end
end
