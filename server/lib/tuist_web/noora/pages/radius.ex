defmodule TuistWeb.Noora.Pages.Radius do
  @moduledoc false
  use TuistWeb.Noora.Page,
    title: "Radius",
    description:
      "Corner radii for controls, cards, and overlays. Nested surfaces use a smaller radius than the surface that contains them, so their corners stay concentric."

  alias TuistWeb.Noora.Tokens

  def content(assigns) do
    assigns = assign(assigns, tokens: Tokens.section("Radius"))

    ~H"""
    <section id="scale" data-part="section">
      <h2><a href="#scale">Scale</a></h2>
      <div data-part="radius-tiles">
        <div :for={token <- @tokens}>
          <div data-part="tile" style={"border-radius: var(#{token.name})"}></div>
          <code>{token.name}</code>
          <span data-part="value">{token.value}</span>
        </div>
      </div>
    </section>
    """
  end
end
