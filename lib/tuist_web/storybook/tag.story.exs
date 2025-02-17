defmodule TuistWeb.Storybook.Tag do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &TuistWeb.Noora.Tag.tag/1

  def variations do
    [
      %Variation{
        id: :tag,
        attributes: %{
          label: "Tag",
          dismissible: true,
          icon: "category"
        }
      },
      %Variation{
        id: :disabled,
        attributes: %{
          label: "Tag",
          dismissible: true,
          icon: "category",
          disabled: true
        }
      },
      %Variation{
        id: :not_dismissible,
        attributes: %{
          label: "Tag",
          dismissible: false,
          icon: "category"
        }
      }
    ]
  end
end
