defmodule TuistWeb.Storybook.Label do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &TuistWeb.Noora.Label.label/1

  def variations do
    [
      %Variation{
        id: :default,
        attributes: %{
          label: "Label",
          required: true,
          sublabel: "(Sublabel)"
        }
      }
    ]
  end
end
