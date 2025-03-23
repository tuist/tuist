defmodule TuistWeb.Storybook.Checkbox do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  def function, do: &TuistWeb.Noora.Checkbox.checkbox/1

  def variations do
    [
      %Variation{
        id: :default,
        attributes: %{label: "Enable notifications"}
      },
      %Variation{
        id: :disabled,
        attributes: %{label: "Disabled checkbox", disabled: true}
      },
      %Variation{
        id: :indeterminate,
        attributes: %{label: "Indeterminate", indeterminate: true}
      },
      %Variation{
        id: :description,
        attributes: %{label: "Description", description: "This is a description"}
      }
    ]
  end
end
