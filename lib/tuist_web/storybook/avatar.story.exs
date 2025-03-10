defmodule TuistWeb.Storybook.Avatar do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &TuistWeb.Noora.Avatar.avatar/1

  def variations do
    [
      %Variation{
        id: :avatar,
        attributes: %{
          name: "Asmit Malakannawar"
        }
      },
      %Variation{
        id: :with_image,
        attributes: %{
          name: "Marek Fořt",
          image_href: "https://www.gravatar.com/avatar/292c129cf17a552c08b4d9dcf2c6c1f8"
        }
      },
      %Variation{
        id: :with_fallback,
        attributes: %{
          name: "Marek Fořt",
          image_href: "https://www.invalid.url",
          fallback: "placeholder"
        }
      },
      %Variation{
        id: :avatar_2xsmall_gray,
        attributes: %{
          name: "Asmit Malakannawar",
          size: "2xsmall",
          color: "gray"
        }
      },
      %Variation{
        id: :avatar_xsmall_red,
        attributes: %{
          name: "Asmit Malakannawar",
          size: "xsmall",
          color: "red"
        }
      },
      %Variation{
        id: :avatar_small_orange,
        attributes: %{
          name: "Asmit Malakannawar",
          size: "small",
          color: "orange"
        }
      },
      %Variation{
        id: :avatar_medium_yellow,
        attributes: %{
          name: "Asmit Malakannawar",
          size: "medium",
          color: "yellow"
        }
      },
      %Variation{
        id: :avatar_large_azure,
        attributes: %{
          name: "Asmit Malakannawar",
          size: "large",
          color: "azure"
        }
      },
      %Variation{
        id: :avatar_xlarge_blue,
        attributes: %{
          name: "Asmit Malakannawar",
          size: "xlarge",
          color: "blue"
        }
      },
      %Variation{
        id: :avatar_2xlarge_purple,
        attributes: %{
          name: "Asmit Malakannawar",
          size: "2xlarge",
          color: "purple"
        }
      }
    ]
  end
end
