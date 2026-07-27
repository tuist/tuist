defmodule TuistWeb.Storybook.WebComponents.Badge do
  @moduledoc false
  use Phoenix.Component
  use PhoenixStorybook.Story, :page

  import NooraStorybookWeb.WebComponentStory

  @badge_contract_path Path.expand("../../../components/badge.json", __DIR__)
  @external_resource @badge_contract_path
  @badge_contract @badge_contract_path |> File.read!() |> Jason.decode!()

  def doc, do: @badge_contract["description"]

  def render(assigns) do
    web_component_story(assign(assigns, :contract, @badge_contract))
  end
end
