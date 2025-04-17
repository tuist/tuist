defmodule TuistWeb.Storybook.Card do
  @moduledoc false
  use PhoenixStorybook.Story, :component

  alias TuistWeb.Noora.Card

  def function, do: &Card.card/1
  def layout, do: :one_column

  def imports, do: [{Card, [card_section: 1]}, {TuistWeb.Noora.Button, [button: 1]}]

  def variations do
    [
      %Variation{
        id: :card,
        attributes: %{
          style: "width: 350px",
          icon: "dashboard",
          title: "Recent test runs"
        },
        slots: [
          """
          <:actions>
            <.button variant="secondary" label="View more" size="medium" />
          </:actions>
          <.card_section style="width: 100%;">
            This is where the content of the card will be displayed.
          </.card_section>
          """
        ]
      }
    ]
  end
end
