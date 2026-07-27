defmodule TuistWeb.Storybook.WebComponents.Button do
  @moduledoc false
  use Phoenix.Component
  use PhoenixStorybook.Story, :page

  import NooraStorybookWeb.WebComponentStory

  @button_contract_path Path.expand("../../../components/button.json", __DIR__)
  @external_resource @button_contract_path
  @button_contract @button_contract_path |> File.read!() |> Jason.decode!()

  def doc, do: @button_contract["description"]

  def render(assigns) do
    web_component_story(assign(assigns, :contract, @button_contract))
  end
end
