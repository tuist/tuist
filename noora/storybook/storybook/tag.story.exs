defmodule TuistWeb.Storybook.Tag do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &Noora.Tag.tag/1

  def variations do
    [
      %VariationGroup{
        id: :basic,
        description: "Basic tag configurations with and without icons",
        variations: [
          %Variation{
            id: :simple,
            attributes: %{
              id: "tag-simple",
              label: "Simple Tag"
            }
          },
          %Variation{
            id: :with_icon,
            attributes: %{
              id: "tag-with-icon",
              label: "Category",
              icon: "category"
            }
          },
          %Variation{
            id: :different_icon,
            attributes: %{
              id: "tag-user-icon",
              label: "User",
              icon: "user"
            }
          }
        ]
      },
      %VariationGroup{
        id: :dismissible_states,
        description: "Tags with different dismissible configurations",
        variations: [
          %Variation{
            id: :dismissible,
            attributes: %{
              id: "tag-dismissible",
              label: "Dismissible Tag",
              dismissible: true,
              icon: "category"
            }
          },
          %Variation{
            id: :not_dismissible,
            attributes: %{
              id: "tag-not-dismissible",
              label: "Fixed Tag",
              dismissible: false,
              icon: "category"
            }
          },
          %Variation{
            id: :dismissible_no_icon,
            attributes: %{
              id: "tag-dismissible-no-icon",
              label: "Remove Me",
              dismissible: true
            }
          }
        ]
      },
      %VariationGroup{
        id: :disabled_states,
        description: "Disabled tag variations",
        variations: [
          %Variation{
            id: :disabled_simple,
            attributes: %{
              id: "tag-disabled-simple",
              label: "Disabled Tag",
              disabled: true
            }
          },
          %Variation{
            id: :disabled_with_icon,
            attributes: %{
              id: "tag-disabled-icon",
              label: "Disabled",
              icon: "category",
              disabled: true
            }
          },
          %Variation{
            id: :disabled_dismissible,
            attributes: %{
              id: "tag-disabled-dismissible",
              label: "Disabled Dismissible",
              dismissible: true,
              icon: "category",
              disabled: true
            }
          }
        ]
      },
      %VariationGroup{
        id: :content_variations,
        description: "Tags with different content and labels",
        variations: [
          %Variation{
            id: :short_label,
            attributes: %{
              id: "tag-short",
              label: "New",
              dismissible: true
            }
          },
          %Variation{
            id: :long_label,
            attributes: %{
              id: "tag-long",
              label: "Very Long Tag Label That Might Wrap",
              dismissible: true,
              icon: "category"
            }
          },
          %Variation{
            id: :numbers,
            attributes: %{
              id: "tag-numbers",
              label: "v2.1.0",
              icon: "git-branch"
            }
          },
          %Variation{
            id: :status_tag,
            attributes: %{
              id: "tag-status",
              label: "In Progress",
              icon: "progress-x",
              dismissible: true
            }
          }
        ]
      }
    ]
  end
end
